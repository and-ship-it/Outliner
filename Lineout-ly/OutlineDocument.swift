//
//  OutlineDocument.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// The main document model managing the outline tree state
@Observable
@MainActor
final class OutlineDocument {
    /// The invisible root node - its children are the top-level items
    var root: OutlineNode

    /// Currently focused/selected node
    var focusedNodeId: UUID?

    /// When true, cursor should be positioned at end of text when focus changes
    /// Used for merge-up behavior (backspace on empty bullet)
    var cursorAtEndOnNextFocus: Bool = false

    /// When set, cursor should be positioned at this character offset on next focus.
    /// Takes priority over cursorAtEndOnNextFocus. Reset to nil after use.
    var cursorOffsetOnNextFocus: Int? = nil

    /// Increments to force a focus refresh even when focusedNodeId hasn't changed
    var focusVersion: Int = 0

    /// Current zoom root (nil = document root, showing all top-level items)
    var zoomedNodeId: UUID?

    /// Multi-selection: set of selected node IDs (for progressive Cmd+A)
    var selectedNodeIds: Set<UUID> = []

    /// Version counter - increments on any structural change to trigger re-renders
    var structureVersion: Int = 0

    /// Whether auto-save is enabled (set to false during loading)
    var autoSaveEnabled: Bool = true

    /// Flag to prevent re-syncing incoming remote changes back to CloudKit
    var isApplyingRemoteChanges: Bool = false

    /// Undo manager for tracking changes
    let undoManager = UndoManager()

    // MARK: - Initialization

    init(root: OutlineNode) {
        self.root = root
        // Ensure there's always at least one node
        if root.children.isEmpty {
            let emptyNode = OutlineNode(title: "")
            root.addChild(emptyNode)
            self.focusedNodeId = emptyNode.id
        }
    }

    /// Convenience initializer that creates a default root node
    convenience init() {
        self.init(root: OutlineNode(title: "__root__"))
    }

    /// Call this after any structural change (collapse, expand, move, add, delete)
    /// Pass dirtyNodeIds to track which nodes changed for CloudKit sync.
    private func structureDidChange(dirtyNodeIds: Set<UUID> = []) {
        structureVersion += 1
        if !isApplyingRemoteChanges && !dirtyNodeIds.isEmpty {
            ChangeTracker.shared.markDirty(dirtyNodeIds)
        }
        scheduleAutoSave()
    }

    /// Call this after content changes (title, body edits)
    func contentDidChange(nodeId: UUID? = nil) {
        if !isApplyingRemoteChanges, let nodeId = nodeId {
            ChangeTracker.shared.markDirty(nodeId)
        }
        scheduleAutoSave()
    }

    /// Schedule an auto-save via iCloudManager
    private func scheduleAutoSave() {
        guard autoSaveEnabled else { return }
        iCloudManager.shared.scheduleAutoSave(for: self)

        // Enqueue dirty nodes into CKSyncEngine for CloudKit push
        if #available(macOS 14.0, iOS 17.0, *) {
            CloudKitSyncEngine.shared.schedulePendingChanges()
        }
    }

    // MARK: - Computed Properties

    var focusedNode: OutlineNode? {
        guard let id = focusedNodeId else { return nil }
        return root.find(id: id)
    }

    var zoomedNode: OutlineNode? {
        guard let id = zoomedNodeId else { return nil }
        return root.find(id: id)
    }

    /// The effective root for display (either zoomed node or document root)
    var displayRoot: OutlineNode {
        zoomedNode ?? root
    }

    /// Breadcrumb path from root to current zoom
    var breadcrumbs: [OutlineNode] {
        guard let zoomed = zoomedNode else { return [] }
        return zoomed.pathFromRoot().dropFirst().dropLast() // Remove __root__ and current
            .map { $0 }
    }

    /// All visible nodes respecting collapse and zoom state (uses node.isCollapsed)
    /// Note: For per-tab collapse state, use visibleNodes(collapsedNodeIds:) instead
    var visibleNodes: [OutlineNode] {
        displayRoot.flattenedVisible()
    }

    /// Compute visible nodes using per-tab zoom and collapse state
    func visibleNodes(zoomedNodeId: UUID?, collapsedNodeIds: Set<UUID>) -> [OutlineNode] {
        var result: [OutlineNode] = []

        // Get the effective root for this tab's zoom state
        if let zoomId = zoomedNodeId, let zoomed = root.find(id: zoomId) {
            // When zoomed, include the zoomed node itself first (it appears at depth 0 in the view)
            result.append(zoomed)
            // Then add its visible children (if not collapsed)
            if !collapsedNodeIds.contains(zoomed.id) {
                result.append(contentsOf: flattenedVisible(from: zoomed, collapsedNodeIds: collapsedNodeIds))
            }
        } else {
            // Not zoomed - just return visible children of root
            result = flattenedVisible(from: root, collapsedNodeIds: collapsedNodeIds)
        }

        return result
    }

    /// Helper to flatten visible nodes with per-tab collapse state
    private func flattenedVisible(from node: OutlineNode, collapsedNodeIds: Set<UUID>) -> [OutlineNode] {
        var result: [OutlineNode] = []
        for child in node.children {
            result.append(child)
            if !collapsedNodeIds.contains(child.id) {
                result.append(contentsOf: flattenedVisible(from: child, collapsedNodeIds: collapsedNodeIds))
            }
        }
        return result
    }

    // MARK: - Search

    /// Search all nodes (including collapsed) for matching text
    func search(query: String) -> [OutlineNode] {
        guard !query.isEmpty else { return [] }
        let lowercasedQuery = query.lowercased()
        return root.flattened().filter { node in
            node.title.lowercased().contains(lowercasedQuery) ||
            node.body.lowercased().contains(lowercasedQuery)
        }
    }

    /// Navigate to a search result - expands parents and focuses the node
    func navigateToSearchResult(_ node: OutlineNode) {
        // Expand all ancestors to make the node visible
        var current = node.parent
        while let parent = current {
            if parent.isCollapsed {
                parent.expand()
            }
            current = parent.parent
        }
        structureDidChange()
        focusedNodeId = node.id
    }

    // MARK: - Focus Operations

    func setFocus(_ node: OutlineNode?) {
        print("[DEBUG] OutlineDocument.setFocus: node='\(node?.title.prefix(20) ?? "nil")' (id: \(node?.id.uuidString.prefix(8) ?? "nil")), current focusedNodeId=\(focusedNodeId?.uuidString.prefix(8) ?? "nil")")
        // Clear multi-selection when changing focus
        if node?.id != focusedNodeId {
            clearSelection()
        }
        focusedNodeId = node?.id
        print("[DEBUG] OutlineDocument.setFocus: DONE - focusedNodeId is now \(focusedNodeId?.uuidString.prefix(8) ?? "nil")")
    }

    func moveFocusUp() {
        moveFocusUp(zoomedNodeId: nil, collapsedNodeIds: nil)
    }

    func moveFocusUp(zoomedNodeId: UUID?, collapsedNodeIds: Set<UUID>?) {
        guard let focused = focusedNode else {
            // Focus first visible node
            let visible = self.visibleNodes(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds ?? [])
            focusedNodeId = visible.first?.id
            focusVersion += 1
            return
        }

        let visible = self.visibleNodes(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds ?? [])
        guard let index = visible.firstIndex(of: focused), index > 0 else { return }
        focusedNodeId = visible[index - 1].id
        focusVersion += 1  // Force cursor refresh
    }

    func moveFocusDown() {
        moveFocusDown(zoomedNodeId: nil, collapsedNodeIds: nil)
    }

    func moveFocusDown(zoomedNodeId: UUID?, collapsedNodeIds: Set<UUID>?) {
        guard let focused = focusedNode else {
            // Focus first visible node
            let visible = self.visibleNodes(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds ?? [])
            focusedNodeId = visible.first?.id
            focusVersion += 1
            return
        }

        let visible = self.visibleNodes(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds ?? [])
        guard let index = visible.firstIndex(of: focused), index < visible.count - 1 else { return }
        focusedNodeId = visible[index + 1].id
        focusVersion += 1  // Force cursor refresh
    }

    func focusParent() {
        guard let focused = focusedNode, let parent = focused.parent else { return }
        // Don't focus the invisible root or go above zoom level
        if parent.isRoot || parent.id == zoomedNodeId { return }
        focusedNodeId = parent.id
        focusVersion += 1  // Force cursor refresh
    }

    func focusFirstChild() {
        guard let focused = focusedNode, let child = focused.firstChild else { return }
        // Expand if collapsed
        if focused.isCollapsed {
            focused.expand()
        }
        focusedNodeId = child.id
        focusVersion += 1  // Force cursor refresh
    }

    // MARK: - Multi-Selection (Progressive Cmd+A)

    /// Clear multi-selection
    func clearSelection() {
        selectedNodeIds.removeAll()
    }

    /// Check if a node is in the multi-selection
    func isNodeSelected(_ nodeId: UUID) -> Bool {
        selectedNodeIds.contains(nodeId)
    }

    /// Expand selection progressively:
    /// 1. First call: Select focused node and all siblings (children of same parent)
    /// 2. Second call: Add parent and all its siblings
    /// 3. Continue expanding up the tree
    func expandSelectionProgressively() {
        guard let focused = focusedNode else { return }

        if selectedNodeIds.isEmpty {
            // First expansion: select focused node + all siblings
            if let parent = focused.parent {
                for sibling in parent.children {
                    selectedNodeIds.insert(sibling.id)
                    // Also include all descendants of each sibling
                    addDescendantsToSelection(sibling)
                }
            } else {
                // No parent (shouldn't happen normally), just select focused
                selectedNodeIds.insert(focused.id)
                addDescendantsToSelection(focused)
            }
        } else {
            // Find the highest selected node and expand from its parent
            if let expansionNode = findHighestSelectedNode() {
                if let parent = expansionNode.parent, !parent.isRoot {
                    // Select parent and all its siblings
                    if let grandparent = parent.parent {
                        for sibling in grandparent.children {
                            selectedNodeIds.insert(sibling.id)
                            addDescendantsToSelection(sibling)
                        }
                    }
                }
                // If already at root level, selection is complete
            }
        }
    }

    /// Add all descendants of a node to the selection
    private func addDescendantsToSelection(_ node: OutlineNode) {
        for child in node.children {
            selectedNodeIds.insert(child.id)
            addDescendantsToSelection(child)
        }
    }

    /// Find the highest (closest to root) selected node
    private func findHighestSelectedNode() -> OutlineNode? {
        var highestNode: OutlineNode? = nil
        var minDepth = Int.max

        for nodeId in selectedNodeIds {
            if let node = root.find(id: nodeId) {
                if node.depth < minDepth {
                    minDepth = node.depth
                    highestNode = node
                }
            }
        }

        return highestNode
    }

    /// Select focused row and extend selection down (Shift+Down)
    func selectRowDown() {
        print("[DEBUG] selectRowDown: CALLED, selectedNodeIds.count=\(selectedNodeIds.count), focusedNodeId=\(focusedNodeId?.uuidString.prefix(8) ?? "nil")")
        let visible = visibleNodes
        guard !visible.isEmpty else {
            print("[DEBUG] selectRowDown: no visible nodes, returning")
            return
        }

        if selectedNodeIds.isEmpty {
            // First press: select the focused node
            if let focusedId = focusedNodeId {
                print("[DEBUG] selectRowDown: first press, selecting focused node")
                selectedNodeIds.insert(focusedId)
            }
        } else {
            // Find the lowest selected node and select the next one
            var lowestIndex = -1
            for (index, node) in visible.enumerated() {
                if selectedNodeIds.contains(node.id) {
                    lowestIndex = max(lowestIndex, index)
                }
            }
            print("[DEBUG] selectRowDown: lowestIndex=\(lowestIndex), visible.count=\(visible.count)")

            // Select the next node if there is one
            if lowestIndex >= 0 && lowestIndex < visible.count - 1 {
                let nextNode = visible[lowestIndex + 1]
                print("[DEBUG] selectRowDown: extending to next node '\(nextNode.title.prefix(20))'")
                selectedNodeIds.insert(nextNode.id)
            } else {
                print("[DEBUG] selectRowDown: cannot extend further")
            }
        }
        print("[DEBUG] selectRowDown: DONE, selectedNodeIds.count=\(selectedNodeIds.count)")
    }

    /// Select focused row and extend selection up (Shift+Up)
    func selectRowUp() {
        print("[DEBUG] selectRowUp: CALLED, selectedNodeIds.count=\(selectedNodeIds.count), focusedNodeId=\(focusedNodeId?.uuidString.prefix(8) ?? "nil")")
        let visible = visibleNodes
        guard !visible.isEmpty else {
            print("[DEBUG] selectRowUp: no visible nodes, returning")
            return
        }

        if selectedNodeIds.isEmpty {
            // First press: select the focused node
            if let focusedId = focusedNodeId {
                print("[DEBUG] selectRowUp: first press, selecting focused node")
                selectedNodeIds.insert(focusedId)
            }
        } else {
            // Find the highest selected node and select the previous one
            var highestIndex = Int.max
            for (index, node) in visible.enumerated() {
                if selectedNodeIds.contains(node.id) {
                    highestIndex = min(highestIndex, index)
                }
            }
            print("[DEBUG] selectRowUp: highestIndex=\(highestIndex), visible.count=\(visible.count)")

            // Select the previous node if there is one
            if highestIndex > 0 && highestIndex < Int.max {
                let prevNode = visible[highestIndex - 1]
                print("[DEBUG] selectRowUp: extending to prev node '\(prevNode.title.prefix(20))'")
                selectedNodeIds.insert(prevNode.id)
            } else {
                print("[DEBUG] selectRowUp: cannot extend further")
            }
        }
        print("[DEBUG] selectRowUp: DONE, selectedNodeIds.count=\(selectedNodeIds.count)")
    }

    // MARK: - Collapse/Expand

    func toggleFocused() {
        focusedNode?.toggle()
        structureDidChange()
    }

    func collapseFocused() {
        guard let focused = focusedNode else { return }
        if focused.isCollapsed {
            // Already collapsed, go to parent
            focusParent()
        } else {
            focused.collapse()
            structureDidChange()
        }
    }

    func expandFocused() {
        guard let focused = focusedNode else { return }
        if !focused.isCollapsed && focused.hasChildren {
            // Already expanded, go to first child
            focusFirstChild()
        } else {
            focused.expand()
            structureDidChange()
        }
    }

    func toggleNode(_ node: OutlineNode) {
        node.toggle()
        structureDidChange()
    }

    func collapseNode(_ node: OutlineNode) {
        node.collapse()
        structureDidChange()
    }

    func expandNode(_ node: OutlineNode) {
        node.expand()
        structureDidChange()
    }

    func collapseAllChildren(of node: OutlineNode) {
        node.collapseAll()
        structureDidChange()
    }

    func expandAllChildren(of node: OutlineNode) {
        node.expandAll()
        structureDidChange()
    }

    /// Collapse all nodes in the entire document
    func collapseAll() {
        for child in root.children {
            child.collapseAll()
        }
        structureDidChange()
    }

    // MARK: - Zoom Operations

    func zoomIn() {
        guard let focused = focusedNode else { return }
        zoomedNodeId = focused.id
    }

    func zoomOut() {
        guard let zoomed = zoomedNode, let parent = zoomed.parent else {
            zoomedNodeId = nil
            return
        }
        // Don't zoom to invisible root
        if parent.isRoot {
            // Going to root - delete empty auto-created bullet
            deleteNodeIfEmpty(zoomed.id)
            zoomedNodeId = nil
        } else {
            zoomedNodeId = parent.id
        }
    }

    func zoomToRoot() {
        // Delete empty auto-created bullet before going home
        if let zoomId = zoomedNodeId {
            deleteNodeIfEmpty(zoomId)
        }
        zoomedNodeId = nil
    }

    /// Delete a node if it's empty (used for auto-created bullets when going home)
    /// A node is considered "empty" if:
    /// - It has no children, OR
    /// - All its children have empty titles, empty bodies, and no grandchildren
    func deleteNodeIfEmpty(_ nodeId: UUID) {
        guard let node = root.find(id: nodeId),
              node.parent != nil else { return }

        // Check if node is empty
        let isEmpty: Bool
        if node.children.isEmpty {
            isEmpty = true
        } else {
            // Check if all children are empty
            isEmpty = node.children.allSatisfy { child in
                child.title.isEmpty && child.body.isEmpty && child.children.isEmpty
            }
        }

        guard isEmpty else {
            print("[Document] Node not empty, keeping: \(node.title)")
            return
        }

        print("[Document] Deleting empty auto-created node: \(node.title)")

        // Track deletion for CloudKit sync
        if !isApplyingRemoteChanges {
            ChangeTracker.shared.markDeletedWithDescendants(node)
        }

        // Remove the node (no undo for auto-cleanup)
        node.removeFromParent()

        // Focus the first remaining node
        if let firstNode = root.children.first {
            focusedNodeId = firstNode.id
            focusVersion += 1
        }

        structureDidChange()
    }

    func zoomTo(_ node: OutlineNode) {
        zoomedNodeId = node.id
        focusedNodeId = node.children.first?.id
    }

    // MARK: - Node Creation

    @discardableResult
    func createSiblingBelow(withTitle title: String = "") -> OutlineNode? {
        let previousFocusId = focusedNodeId

        guard let focused = focusedNode, let _ = focused.parent else {
            // Create at root level
            let newNode = OutlineNode(title: title)
            root.addChild(newNode)

            // Register undo
            undoManager.registerUndo(withTarget: self) { doc in
                doc.deleteNodeForUndo(newNode.id, restoreFocusTo: previousFocusId)
            }
            undoManager.setActionName("New Bullet")

            structureDidChange(dirtyNodeIds: [newNode.id])

            // Defer focus to next run loop to allow SwiftUI to create the view
            DispatchQueue.main.async { [weak self] in
                self?.focusedNodeId = newNode.id
            }

            return newNode
        }

        let newNode = OutlineNode(title: title)
        focused.insertSiblingBelow(newNode)

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.deleteNodeForUndo(newNode.id, restoreFocusTo: previousFocusId)
        }
        undoManager.setActionName("New Bullet")

        structureDidChange(dirtyNodeIds: [newNode.id])

        // Defer focus to next run loop to allow SwiftUI to create the view
        DispatchQueue.main.async { [weak self] in
            self?.focusedNodeId = newNode.id
        }

        return newNode
    }

    @discardableResult
    func createSiblingAbove() -> OutlineNode? {
        let previousFocusId = focusedNodeId

        guard let focused = focusedNode, focused.parent != nil else {
            // Create at root level (at beginning)
            let newNode = OutlineNode()
            root.addChild(newNode, at: 0)

            // Register undo
            undoManager.registerUndo(withTarget: self) { doc in
                doc.deleteNodeForUndo(newNode.id, restoreFocusTo: previousFocusId)
            }
            undoManager.setActionName("New Bullet")

            structureDidChange(dirtyNodeIds: [newNode.id])

            // Defer focus to next run loop to allow SwiftUI to create the view
            DispatchQueue.main.async { [weak self] in
                self?.focusedNodeId = newNode.id
            }

            return newNode
        }

        let newNode = OutlineNode()
        focused.insertSiblingAbove(newNode)

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.deleteNodeForUndo(newNode.id, restoreFocusTo: previousFocusId)
        }
        undoManager.setActionName("New Bullet")

        structureDidChange(dirtyNodeIds: [newNode.id])

        // Defer focus to next run loop to allow SwiftUI to create the view
        DispatchQueue.main.async { [weak self] in
            self?.focusedNodeId = newNode.id
        }

        return newNode
    }

    @discardableResult
    func createChild() -> OutlineNode? {
        guard let focused = focusedNode else {
            return createSiblingBelow()
        }

        let previousFocusId = focusedNodeId
        let wasCollapsed = focused.isCollapsed

        let newNode = OutlineNode()
        focused.addChild(newNode, at: 0)
        focused.expand()

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.deleteNodeForUndo(newNode.id, restoreFocusTo: previousFocusId)
            if wasCollapsed, let parent = doc.root.find(id: focused.id) {
                parent.collapse()
            }
        }
        undoManager.setActionName("New Bullet")

        structureDidChange(dirtyNodeIds: [newNode.id])

        // Defer focus to next run loop to allow SwiftUI to create the view
        DispatchQueue.main.async { [weak self] in
            self?.focusedNodeId = newNode.id
        }

        return newNode
    }

    // MARK: - Smart Paste

    /// Insert parsed nodes at cursor position
    /// When zoomed, nodes are inserted as children of the zoomed node
    @discardableResult
    func smartPasteNodes(_ nodes: [OutlineNode], cursorAtEnd: Bool, cursorAtStart: Bool, zoomedNodeId: UUID? = nil) -> OutlineNode? {
        guard !nodes.isEmpty else { return nil }
        print("[SmartPaste] smartPasteNodes called with \(nodes.count) nodes, cursorAtEnd=\(cursorAtEnd), cursorAtStart=\(cursorAtStart), zoomed=\(zoomedNodeId != nil)")

        // If zoomed, insert as children of the zoomed node
        if let zoomId = zoomedNodeId, let zoomedNode = root.find(id: zoomId) {
            return insertNodesAsChildren(nodes, of: zoomedNode)
        }

        guard let focused = focusedNode else {
            // No focus - insert at root level
            if let lastChild = root.children.last {
                return insertNodesAsSiblings(nodes, below: lastChild)
            } else {
                // Empty document - add as children of root
                for node in nodes {
                    root.addChild(node)
                }
                let allDirtyIds = Set(nodes.flatMap { $0.flattened().map(\.id) })
                structureDidChange(dirtyNodeIds: allDirtyIds)
                return nodes.first
            }
        }

        // If focused node is empty, replace with first pasted node
        if focused.title.isEmpty && focused.body.isEmpty && !focused.hasChildren {
            let firstNode = nodes[0]
            let previousTitle = focused.title
            let previousBody = focused.body
            let previousIsTask = focused.isTask
            let previousIsTaskCompleted = focused.isTaskCompleted

            // Update focused node with first pasted content
            focused.title = firstNode.title
            focused.isTask = firstNode.isTask
            focused.isTaskCompleted = firstNode.isTaskCompleted

            // Add first node's children to focused
            for child in firstNode.children {
                focused.addChild(child)
            }

            // Register undo for the replacement
            let focusedId = focused.id
            let childIds = firstNode.children.map { $0.id }
            undoManager.registerUndo(withTarget: self) { doc in
                guard let node = doc.root.find(id: focusedId) else { return }
                node.title = previousTitle
                node.body = previousBody
                node.isTask = previousIsTask
                node.isTaskCompleted = previousIsTaskCompleted
                // Remove children that were added
                for childId in childIds {
                    if let child = node.children.first(where: { $0.id == childId }) {
                        child.removeFromParent()
                    }
                }
                doc.structureDidChange()
            }

            // Insert remaining nodes as siblings if there are more
            if nodes.count > 1 {
                let remainingNodes = Array(nodes.dropFirst())
                _ = insertNodesAsSiblings(remainingNodes, below: focused)
            }

            undoManager.setActionName("Paste")
            var pastedDirtyIds = Set<UUID>([focused.id])
            pastedDirtyIds.formUnion(childIds.map { $0 })
            structureDidChange(dirtyNodeIds: pastedDirtyIds)
            return focused
        }

        // Insert as siblings based on cursor position
        if cursorAtStart {
            return insertNodesAbove(nodes, anchor: focused)
        } else {
            return insertNodesAsSiblings(nodes, below: focused)
        }
    }

    /// Insert nodes as siblings below the anchor node
    @discardableResult
    func insertNodesAsSiblings(_ nodes: [OutlineNode], below anchor: OutlineNode) -> OutlineNode? {
        guard !nodes.isEmpty else { return nil }
        guard let parent = anchor.parent, let anchorIndex = anchor.indexInParent else {
            // Anchor is root or has no parent - add as children of root
            for node in nodes {
                root.addChild(node)
            }
            let nodeIds = nodes.map { $0.id }
            let allDirtyIds = Set(nodes.flatMap { $0.flattened().map(\.id) })
            undoManager.registerUndo(withTarget: self) { doc in
                doc.removeNodesForUndo(nodeIds)
            }
            undoManager.setActionName("Paste")
            structureDidChange(dirtyNodeIds: allDirtyIds)
            return nodes.first
        }

        let previousFocusId = focusedNodeId

        // Insert all nodes as siblings, in order after anchor
        var insertIndex = anchorIndex + 1
        for node in nodes {
            parent.addChild(node, at: insertIndex)
            insertIndex += 1
        }

        // Register undo - remove all inserted nodes
        let nodeIds = nodes.map { $0.id }
        let allDirtyIds = Set(nodes.flatMap { $0.flattened().map(\.id) })
        undoManager.registerUndo(withTarget: self) { doc in
            doc.removeNodesForUndo(nodeIds)
            doc.focusedNodeId = previousFocusId
        }
        undoManager.setActionName("Paste")

        structureDidChange(dirtyNodeIds: allDirtyIds)
        return nodes.first
    }

    /// Insert nodes as siblings above the anchor node
    @discardableResult
    func insertNodesAbove(_ nodes: [OutlineNode], anchor: OutlineNode) -> OutlineNode? {
        guard !nodes.isEmpty else { return nil }
        guard let parent = anchor.parent, let anchorIndex = anchor.indexInParent else {
            // Anchor is root or has no parent - add as children of root at beginning
            for (i, node) in nodes.enumerated() {
                root.addChild(node, at: i)
            }
            let nodeIds = nodes.map { $0.id }
            let allDirtyIds = Set(nodes.flatMap { $0.flattened().map(\.id) })
            undoManager.registerUndo(withTarget: self) { doc in
                doc.removeNodesForUndo(nodeIds)
            }
            undoManager.setActionName("Paste")
            structureDidChange(dirtyNodeIds: allDirtyIds)
            return nodes.first
        }

        let previousFocusId = focusedNodeId

        // Insert all nodes above anchor, in order
        var insertIndex = anchorIndex
        for node in nodes {
            parent.addChild(node, at: insertIndex)
            insertIndex += 1
        }

        // Register undo - remove all inserted nodes
        let nodeIds = nodes.map { $0.id }
        let allDirtyIds = Set(nodes.flatMap { $0.flattened().map(\.id) })
        undoManager.registerUndo(withTarget: self) { doc in
            doc.removeNodesForUndo(nodeIds)
            doc.focusedNodeId = previousFocusId
        }
        undoManager.setActionName("Paste")

        structureDidChange(dirtyNodeIds: allDirtyIds)
        return nodes.first
    }

    /// Insert nodes as children of a parent node
    @discardableResult
    func insertNodesAsChildren(_ nodes: [OutlineNode], of parent: OutlineNode) -> OutlineNode? {
        guard !nodes.isEmpty else { return nil }

        let previousFocusId = focusedNodeId

        // Insert all nodes as children at the end
        for node in nodes {
            parent.addChild(node)
        }

        // Register undo - remove all inserted nodes
        let nodeIds = nodes.map { $0.id }
        let allDirtyIds = Set(nodes.flatMap { $0.flattened().map(\.id) })
        undoManager.registerUndo(withTarget: self) { doc in
            doc.removeNodesForUndo(nodeIds)
            doc.focusedNodeId = previousFocusId
        }
        undoManager.setActionName("Paste")

        structureDidChange(dirtyNodeIds: allDirtyIds)
        return nodes.first
    }

    /// Remove nodes by ID (for undo operations)
    private func removeNodesForUndo(_ nodeIds: [UUID]) {
        for nodeId in nodeIds {
            if let node = root.find(id: nodeId) {
                if !isApplyingRemoteChanges {
                    ChangeTracker.shared.markDeletedWithDescendants(node)
                }
                node.removeFromParent()
            }
        }
        ensureMinimumNode()
        structureDidChange()
    }

    // MARK: - Node Deletion

    func deleteFocused() {
        guard let focused = focusedNode else { return }
        // Don't allow deleting date nodes
        guard !focused.isDateNode else { return }

        // Check if this is the last node - if so, just clear it instead of deleting
        let visible = visibleNodes
        print("[DEBUG] deleteFocused: visible.count=\(visible.count), focused='\(focused.title.prefix(20))'")
        if visible.count == 1 && focused == visible.first {
            // Last node - clear its content but keep it (with undo)
            print("[DEBUG] deleteFocused: LAST NODE CASE - clearing instead of deleting")
            let oldTitle = focused.title
            let oldBody = focused.body
            focused.title = ""
            focused.body = ""

            // Force focus refresh by incrementing focusVersion
            print("[DEBUG] deleteFocused: incrementing focusVersion from \(focusVersion) to \(focusVersion + 1)")
            focusVersion += 1

            undoManager.registerUndo(withTarget: self) { doc in
                if let node = doc.root.find(id: focused.id) {
                    node.title = oldTitle
                    node.body = oldBody
                }
                doc.structureDidChange()
            }
            undoManager.setActionName("Clear Bullet")
            structureDidChange()
            return
        }

        // Save state for undo
        let nodeCopy = focused.deepCopy()
        let parentId = focused.parent?.id
        let indexInParent = focused.indexInParent ?? 0
        let previousFocusId = focusedNodeId

        // Clean up linked Apple Reminders before deletion
        cleanupReminders(for: focused)

        // If deleting a metadata child (note/link), sync the cleared field to its parent's reminder
        if let childType = focused.reminderChildType,
           let parent = focused.parent,
           parent.reminderIdentifier != nil,
           !ReminderSyncEngine.shared.isApplyingReminderChanges {
            // Remove the child first, then sync — the sync will see no note/link child and clear the field
            focused.removeFromParent()
            ReminderSyncEngine.shared.syncMetadataChildrenToReminder(parent)
            // Ensure at least one node exists and handle focus/undo
            ensureMinimumNode()
            structureDidChange()
            return
        }

        // If deleting a reminder parent, also clean up its metadata children
        if focused.reminderIdentifier != nil {
            let metaChildren = focused.children.filter { $0.reminderChildType != nil }
            for child in metaChildren {
                child.removeFromParent()
            }
        }

        // Move to trash before deleting
        TrashBin.shared.trash(focused)

        // Track deletion for CloudKit sync
        if !isApplyingRemoteChanges {
            ChangeTracker.shared.markDeletedWithDescendants(focused)
        }

        // Find previous node to focus (merge up behavior for backspace)
        // Set flag to position cursor at end of text (merge up)
        if let index = visible.firstIndex(of: focused) {
            if index > 0 {
                cursorAtEndOnNextFocus = true  // Position cursor at end for merge-up
                focusedNodeId = visible[index - 1].id
                focusVersion += 1  // Force text field to re-evaluate cursor position
            } else if index < visible.count - 1 {
                focusedNodeId = visible[index + 1].id
            } else {
                focusedNodeId = nil
            }
        }

        focused.removeFromParent()

        // Ensure there's always at least one node
        ensureMinimumNode()

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.restoreNodeForUndo(nodeCopy, parentId: parentId, atIndex: indexInParent, restoreFocusTo: previousFocusId)
        }
        undoManager.setActionName("Delete")

        structureDidChange()
    }

    /// Merge the current bullet with the previous one (backspace at beginning of text)
    /// The text from the current bullet is appended to the previous bullet
    func mergeWithPrevious(textToMerge: String, zoomedNodeId: UUID?, collapsedNodeIds: Set<UUID>) {
        guard let focused = focusedNode else { return }
        // Don't merge date nodes or reminder metadata children
        guard !focused.isDateNode else { return }
        guard focused.reminderChildType == nil else { return }

        let visible = self.visibleNodes(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        guard let index = visible.firstIndex(of: focused), index > 0 else { return }

        let previousNode = visible[index - 1]
        // Don't merge into a date node
        guard !previousNode.isDateNode else { return }
        let previousTitle = previousNode.title

        // Save state for undo
        let currentNodeCopy = focused.deepCopy()
        let parentId = focused.parent?.id
        let indexInParent = focused.indexInParent ?? 0
        let previousFocusId = focusedNodeId
        let originalPreviousTitle = previousTitle

        // Append current text to previous node
        previousNode.title = previousTitle + textToMerge

        // Move to trash before deleting
        TrashBin.shared.trash(focused)

        // Track deletion and modification for CloudKit sync
        if !isApplyingRemoteChanges {
            ChangeTracker.shared.markDeleted(focused.id)
            ChangeTracker.shared.markDirty(previousNode.id)
        }

        // Delete current node
        focused.removeFromParent()

        // Focus the previous node with cursor at the merge point
        // (end of the original previous text, before the appended text)
        cursorOffsetOnNextFocus = previousTitle.count
        focusedNodeId = previousNode.id
        focusVersion += 1

        // Ensure there's always at least one node
        ensureMinimumNode()

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            // Restore previous node's title
            if let prevNode = doc.root.find(id: previousNode.id) {
                prevNode.title = originalPreviousTitle
            }
            // Restore deleted node
            doc.restoreNodeForUndo(currentNodeCopy, parentId: parentId, atIndex: indexInParent, restoreFocusTo: previousFocusId)
        }
        undoManager.setActionName("Merge Bullets")

        structureDidChange()
    }

    /// Delete the focused node and all its children
    func deleteFocusedWithChildren() {
        guard let focused = focusedNode else { return }
        // Don't allow deleting date nodes
        guard !focused.isDateNode else { return }

        // Check if this is the last top-level node - if so, just clear it instead of deleting
        let visible = visibleNodes
        print("[DEBUG] deleteFocusedWithChildren: visible.count=\(visible.count), focused='\(focused.title.prefix(20))'")
        if visible.count == 1 && focused == visible.first {
            // Last node - clear its content and children but keep it (with undo)
            print("[DEBUG] deleteFocusedWithChildren: LAST NODE CASE - clearing instead of deleting")
            let oldTitle = focused.title
            let oldBody = focused.body
            let oldChildren = focused.children.map { $0.deepCopy() }

            focused.title = ""
            focused.body = ""
            focused.children.removeAll()

            // Force focus refresh by incrementing focusVersion
            print("[DEBUG] deleteFocusedWithChildren: incrementing focusVersion from \(focusVersion) to \(focusVersion + 1)")
            focusVersion += 1

            undoManager.registerUndo(withTarget: self) { doc in
                if let node = doc.root.find(id: focused.id) {
                    node.title = oldTitle
                    node.body = oldBody
                    for child in oldChildren {
                        node.addChild(child)
                    }
                }
                doc.structureDidChange()
            }
            undoManager.setActionName("Clear Bullet")
            structureDidChange()
            return
        }

        // Save state for undo
        let nodeCopy = focused.deepCopy()
        let parentId = focused.parent?.id
        let indexInParent = focused.indexInParent ?? 0
        let previousFocusId = focusedNodeId

        // Clean up linked Apple Reminders before deletion (node + all descendants)
        cleanupReminders(for: focused)

        // If deleting a metadata child (note/link), sync the cleared field to its parent's reminder
        cleanupMetadataChild(focused)

        // Move to trash before deleting (includes all children)
        TrashBin.shared.trash(focused)

        // Track deletion for CloudKit sync (node + all descendants)
        if !isApplyingRemoteChanges {
            ChangeTracker.shared.markDeletedWithDescendants(focused)
        }

        // Find next sibling or parent to focus (skip over children since they'll be deleted)
        if let nextSibling = focused.nextSibling {
            focusedNodeId = nextSibling.id
        } else if let prevSibling = focused.previousSibling {
            focusedNodeId = prevSibling.id
        } else if let parent = focused.parent, !parent.isRoot {
            focusedNodeId = parent.id
        } else {
            focusedNodeId = nil
        }

        // Remove the node (children are automatically removed with it)
        focused.removeFromParent()

        // Ensure there's always at least one node
        ensureMinimumNode()

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.restoreNodeForUndo(nodeCopy, parentId: parentId, atIndex: indexInParent, restoreFocusTo: previousFocusId)
        }
        undoManager.setActionName("Delete")

        structureDidChange()
    }

    /// Ensures there's always at least one node in the document
    private func ensureMinimumNode() {
        if root.children.isEmpty {
            let newNode = OutlineNode(title: "")
            root.addChild(newNode)
            focusedNodeId = newNode.id
        }
    }

    // MARK: - Copy/Cut Selected

    /// Copy selected nodes to clipboard as markdown
    func copySelected() {
        guard !selectedNodeIds.isEmpty else { return }

        // Get selected nodes sorted by visible position (top to bottom)
        let selectedNodes = selectedNodeIds.compactMap { root.find(id: $0) }
        let visible = visibleNodes
        let sortedNodes = selectedNodes.sorted { n1, n2 in
            let i1 = visible.firstIndex(of: n1) ?? 0
            let i2 = visible.firstIndex(of: n2) ?? 0
            return i1 < i2
        }

        // Filter to top-level selected only (exclude children of selected parents)
        let topLevelSelected = sortedNodes.filter { node in
            !node.pathFromRoot().dropLast().contains { selectedNodeIds.contains($0.id) }
        }

        // Convert to markdown
        var markdown = ""
        for node in topLevelSelected {
            markdown += nodeToMarkdown(node, indent: 0)
        }

        // Put on pasteboard
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = markdown
        #endif

        print("[Copy] Copied \(topLevelSelected.count) nodes to clipboard")
    }

    /// Cut selected nodes (copy + delete)
    func cutSelected() {
        copySelected()
        deleteSelected()
    }

    /// Convert a node and its children to markdown format
    private func nodeToMarkdown(_ node: OutlineNode, indent: Int) -> String {
        var result = ""
        let indentStr = String(repeating: "  ", count: indent)

        // Format the bullet
        if node.isTask {
            let checkbox = node.isTaskCompleted ? "[x]" : "[ ]"
            result += "\(indentStr)- \(checkbox) \(node.title)\n"
        } else {
            result += "\(indentStr)- \(node.title)\n"
        }

        // Add body if present
        if !node.body.isEmpty {
            let bodyLines = node.body.components(separatedBy: "\n")
            for line in bodyLines {
                result += "\(indentStr)  \(line)\n"
            }
        }

        // Add children recursively
        for child in node.children {
            result += nodeToMarkdown(child, indent: indent + 1)
        }

        return result
    }

    /// Delete all selected nodes and position cursor at nearest remaining bullet
    func deleteSelected() {
        guard !selectedNodeIds.isEmpty else { return }

        // Find the topmost selected node to determine where to place cursor after
        var topmostIndex = Int.max
        let visible = visibleNodes

        // Collect all selected nodes with their restore info
        struct NodeRestoreInfo {
            let nodeCopy: OutlineNode
            let parentId: UUID?
            let indexInParent: Int
        }
        var restoreInfos: [NodeRestoreInfo] = []
        var nodesToDelete: [OutlineNode] = []

        for nodeId in selectedNodeIds {
            if let node = root.find(id: nodeId) {
                // Only save top-level selected nodes (not children of other selected nodes)
                let isChildOfSelected = node.pathFromRoot().dropLast().contains { selectedNodeIds.contains($0.id) }
                if !isChildOfSelected {
                    restoreInfos.append(NodeRestoreInfo(
                        nodeCopy: node.deepCopy(),
                        parentId: node.parent?.id,
                        indexInParent: node.indexInParent ?? 0
                    ))
                }
                nodesToDelete.append(node)

                // Track topmost visible position
                if let index = visible.firstIndex(of: node), index < topmostIndex {
                    topmostIndex = index
                }
            }
        }

        let previousFocusId = focusedNodeId

        // Find the next focus target (first non-selected node above the topmost selected)
        var nextFocusId: UUID? = nil
        if topmostIndex > 0 && topmostIndex < Int.max {
            // Look for the nearest non-selected node above
            for i in (0..<topmostIndex).reversed() {
                let candidate = visible[i]
                if !selectedNodeIds.contains(candidate.id) {
                    nextFocusId = candidate.id
                    break
                }
            }
        }

        // If no node above, try to find one below all selected
        if nextFocusId == nil {
            for node in visible {
                if !selectedNodeIds.contains(node.id) {
                    nextFocusId = node.id
                    break
                }
            }
        }

        // Clean up linked Apple Reminders and delete
        for node in nodesToDelete {
            cleanupReminders(for: node)
            cleanupMetadataChild(node)
            TrashBin.shared.trash(node)
            // Track deletion for CloudKit sync
            if !isApplyingRemoteChanges {
                ChangeTracker.shared.markDeletedWithDescendants(node)
            }
            node.removeFromParent()
        }

        // Clear selection
        selectedNodeIds.removeAll()

        // Ensure minimum node exists
        ensureMinimumNode()

        // Set focus to nearest remaining node
        if let focusId = nextFocusId {
            focusedNodeId = focusId
        } else {
            // Focus first available node
            focusedNodeId = root.children.first?.id
        }

        // Register undo - restore all deleted nodes
        undoManager.registerUndo(withTarget: self) { doc in
            // Restore in reverse order to maintain correct indices
            for info in restoreInfos.reversed() {
                doc.restoreNodeForUndo(info.nodeCopy, parentId: info.parentId, atIndex: info.indexInParent, restoreFocusTo: nil)
            }
            doc.focusedNodeId = previousFocusId
            doc.structureDidChange()
        }
        undoManager.setActionName("Delete Selected")

        structureDidChange()
    }

    // MARK: - Undo Helpers

    /// Delete a node for undo (used when undoing creation)
    private func deleteNodeForUndo(_ nodeId: UUID, restoreFocusTo focusId: UUID?) {
        guard let node = root.find(id: nodeId) else { return }

        // Track deletion for CloudKit sync
        if !isApplyingRemoteChanges {
            ChangeTracker.shared.markDeletedWithDescendants(node)
        }

        // Save state for redo
        let nodeCopy = node.deepCopy()
        let parentId = node.parent?.id
        let indexInParent = node.indexInParent ?? 0
        let currentFocusId = focusedNodeId

        node.removeFromParent()
        ensureMinimumNode()
        focusedNodeId = focusId

        // Register redo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.restoreNodeForUndo(nodeCopy, parentId: parentId, atIndex: indexInParent, restoreFocusTo: currentFocusId)
        }

        structureDidChange()
    }

    /// Restore a node for undo (used when undoing deletion)
    private func restoreNodeForUndo(_ nodeCopy: OutlineNode, parentId: UUID?, atIndex index: Int, restoreFocusTo focusId: UUID?) {
        // Find the parent
        let parent: OutlineNode
        if let pid = parentId, let p = root.find(id: pid) {
            parent = p
        } else {
            parent = root
        }

        // Check if node already exists (shouldn't happen, but be safe)
        if root.find(id: nodeCopy.id) != nil {
            return
        }

        // Insert at the correct position
        let safeIndex = min(index, parent.children.count)
        parent.addChild(nodeCopy, at: safeIndex)

        // Mark restored node and descendants as dirty for CloudKit sync
        let restoredIds = Set(nodeCopy.flattened().map(\.id) + [nodeCopy.id])

        // Save state for redo
        let currentFocusId = focusedNodeId

        // Restore focus
        if let fid = focusId {
            focusedNodeId = fid
        } else {
            focusedNodeId = nodeCopy.id
        }

        // Register redo (delete again)
        undoManager.registerUndo(withTarget: self) { doc in
            doc.deleteNodeForUndo(nodeCopy.id, restoreFocusTo: currentFocusId)
        }

        structureDidChange(dirtyNodeIds: restoredIds)
    }

    // MARK: - Node Movement

    func moveUp() {
        guard let focused = focusedNode,
              let parent = focused.parent,
              let index = focused.indexInParent,
              index > 0 else { return }
        // Don't allow moving date nodes or reminder metadata children
        guard !focused.isDateNode else { return }
        guard focused.reminderChildType == nil else { return }

        let swappedSibling = parent.children[index - 1]
        parent.children.remove(at: index)
        parent.children.insert(focused, at: index - 1)

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveDownForUndo(focused.id)
        }
        undoManager.setActionName("Move Up")

        structureDidChange(dirtyNodeIds: [focused.id, swappedSibling.id])
    }

    func moveDown() {
        guard let focused = focusedNode,
              let parent = focused.parent,
              let index = focused.indexInParent,
              index < parent.children.count - 1 else { return }
        // Don't allow moving date nodes or reminder metadata children
        guard !focused.isDateNode else { return }
        guard focused.reminderChildType == nil else { return }

        let swappedSibling = parent.children[index + 1]
        parent.children.remove(at: index)
        parent.children.insert(focused, at: index + 1)

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveUpForUndo(focused.id)
        }
        undoManager.setActionName("Move Down")

        structureDidChange(dirtyNodeIds: [focused.id, swappedSibling.id])
    }

    /// Check if the focused node can be indented (has a previous sibling to become child of)
    func canIndent() -> Bool {
        guard let focused = focusedNode,
              focused.parent != nil,
              focused.previousSibling != nil else { return false }
        return true
    }

    /// Check if the focused node can be outdented (has a grandparent to move to)
    /// If zoomBoundaryId is set, prevents outdenting direct children of the zoomed node
    func canOutdent(zoomBoundaryId: UUID? = nil) -> Bool {
        guard let focused = focusedNode,
              let parent = focused.parent,
              parent.parent != nil else { return false }
        // Cannot outdent beyond zoom boundary — zoom out first
        if let boundaryId = zoomBoundaryId, parent.id == boundaryId { return false }
        return true
    }

    func indent() {
        // Multi-selection indent
        if !selectedNodeIds.isEmpty {
            indentSelected()
            return
        }

        // Single node indent
        guard let focused = focusedNode,
              let parent = focused.parent,
              let previousSibling = focused.previousSibling else { return }
        // Don't allow indenting date nodes or reminder metadata children
        guard !focused.isDateNode else { return }
        guard focused.reminderChildType == nil else { return }

        let originalParentId = parent.id
        let originalIndex = focused.indexInParent ?? 0

        focused.removeFromParent()
        previousSibling.addChild(focused)
        previousSibling.expand()

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveNodeForUndo(focused.id, toParentId: originalParentId, atIndex: originalIndex)
        }
        undoManager.setActionName("Indent")

        structureDidChange(dirtyNodeIds: [focused.id])
        checkReminderReschedule(focused)
    }

    /// Indent all selected nodes
    func indentSelected() {
        // Get selected nodes sorted by position (top to bottom)
        let selectedNodes = selectedNodeIds.compactMap { root.find(id: $0) }
        guard !selectedNodes.isEmpty else { return }

        let visible = visibleNodes
        let sortedByPosition = selectedNodes.sorted { n1, n2 in
            let i1 = visible.firstIndex(of: n1) ?? 0
            let i2 = visible.firstIndex(of: n2) ?? 0
            return i1 < i2  // Top to bottom
        }

        // Group consecutive siblings together
        // Each group will be indented under the previous sibling of the first node
        var groups: [[OutlineNode]] = []
        var currentGroup: [OutlineNode] = []

        for node in sortedByPosition {
            if currentGroup.isEmpty {
                currentGroup.append(node)
            } else if let lastNode = currentGroup.last,
                      lastNode.parent === node.parent,
                      let lastIndex = lastNode.indexInParent,
                      let nodeIndex = node.indexInParent,
                      nodeIndex == lastIndex + 1 {
                // Consecutive sibling - add to current group
                currentGroup.append(node)
            } else {
                // Not consecutive - start new group
                groups.append(currentGroup)
                currentGroup = [node]
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        // Store restore info for undo
        var restoreInfos: [(nodeId: UUID, parentId: UUID, index: Int)] = []

        // Process each group: move all nodes to be children of the previous sibling of the first node
        for group in groups {
            guard let firstNode = group.first,
                  let previousSibling = firstNode.previousSibling else { continue }

            // Move all nodes in the group to be children of previousSibling
            for node in group {
                guard let parent = node.parent else { continue }
                restoreInfos.append((node.id, parent.id, node.indexInParent ?? 0))
                node.removeFromParent()
                previousSibling.addChild(node)  // Adds at end, maintains order
            }
            previousSibling.expand()
        }

        guard !restoreInfos.isEmpty else { return }

        let movedIds = Set(restoreInfos.map(\.nodeId))

        // Register undo for all moves
        undoManager.registerUndo(withTarget: self) { doc in
            // Restore in reverse order
            for info in restoreInfos.reversed() {
                doc.moveNodeForUndo(info.nodeId, toParentId: info.parentId, atIndex: info.index)
            }
        }
        undoManager.setActionName("Indent")

        structureDidChange(dirtyNodeIds: movedIds)
    }

    func outdent(zoomBoundaryId: UUID? = nil) {
        // Multi-selection outdent
        if !selectedNodeIds.isEmpty {
            outdentSelected(zoomBoundaryId: zoomBoundaryId)
            return
        }

        // Single node outdent
        guard let focused = focusedNode,
              let parent = focused.parent,
              let grandparent = parent.parent else { return }
        // Don't allow outdenting date nodes or reminder metadata children
        guard !focused.isDateNode else { return }
        guard focused.reminderChildType == nil else { return }
        // Cannot outdent beyond zoom boundary — zoom out first
        if let boundaryId = zoomBoundaryId, parent.id == boundaryId { return }

        // Get parent's index to insert after it
        guard let parentIndex = parent.indexInParent else { return }

        let originalParentId = parent.id
        let originalIndex = focused.indexInParent ?? 0

        focused.removeFromParent()
        grandparent.addChild(focused, at: parentIndex + 1)

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveNodeForUndo(focused.id, toParentId: originalParentId, atIndex: originalIndex)
        }
        undoManager.setActionName("Outdent")

        structureDidChange(dirtyNodeIds: [focused.id])
        checkReminderReschedule(focused)
    }

    /// Outdent all selected nodes
    func outdentSelected(zoomBoundaryId: UUID? = nil) {
        // Get selected nodes sorted by position (process from top to bottom)
        let selectedNodes = selectedNodeIds.compactMap { root.find(id: $0) }
        guard !selectedNodes.isEmpty else { return }

        // Sort by visible position (top to bottom)
        let visible = visibleNodes
        let sortedNodes = selectedNodes.sorted { n1, n2 in
            let i1 = visible.firstIndex(of: n1) ?? 0
            let i2 = visible.firstIndex(of: n2) ?? 0
            return i1 < i2
        }

        // Store restore info for undo
        var restoreInfos: [(nodeId: UUID, parentId: UUID, index: Int)] = []

        // Track insertion offset for nodes being inserted after the same parent
        var insertionOffsets: [UUID: Int] = [:]

        for node in sortedNodes {
            guard let parent = node.parent,
                  let grandparent = parent.parent,
                  let parentIndex = parent.indexInParent else { continue }

            // Skip if parent is also selected (will be moved together)
            if selectedNodeIds.contains(parent.id) { continue }

            // Cannot outdent beyond zoom boundary
            if let boundaryId = zoomBoundaryId, parent.id == boundaryId { continue }

            restoreInfos.append((node.id, parent.id, node.indexInParent ?? 0))

            // Calculate insertion index with offset for multiple nodes
            let offset = insertionOffsets[parent.id] ?? 0
            let insertIndex = parentIndex + 1 + offset
            insertionOffsets[parent.id] = offset + 1

            node.removeFromParent()
            grandparent.addChild(node, at: insertIndex)
        }

        guard !restoreInfos.isEmpty else { return }

        let movedIds = Set(restoreInfos.map(\.nodeId))

        // Register undo for all moves
        undoManager.registerUndo(withTarget: self) { doc in
            // Restore in reverse order
            for info in restoreInfos.reversed() {
                doc.moveNodeForUndo(info.nodeId, toParentId: info.parentId, atIndex: info.index)
            }
        }
        undoManager.setActionName("Outdent")

        structureDidChange(dirtyNodeIds: movedIds)
    }

    /// Move a node to be a sibling after a target node (for iOS drag-drop)
    func moveNodeAfter(nodeId: UUID, targetId: UUID) {
        guard let node = root.find(id: nodeId),
              let target = root.find(id: targetId),
              let targetParent = target.parent,
              let targetIndex = target.indexInParent else { return }

        // Don't allow moving a node to be after itself
        guard nodeId != targetId else { return }

        // Don't allow moving a node to be its own descendant
        if target.isDescendant(of: node) { return }

        // Save state for undo
        let originalParentId = node.parent?.id
        let originalIndex = node.indexInParent ?? 0
        let previousFocusId = focusedNodeId

        // Remove from current position
        node.removeFromParent()

        // Calculate new index (after target, but adjust if we removed from before target)
        var newIndex = targetIndex + 1
        if let origParentId = originalParentId,
           origParentId == targetParent.id,
           originalIndex < targetIndex {
            newIndex -= 1
        }

        // Insert at new position
        targetParent.addChild(node, at: newIndex)

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveNodeForUndo(nodeId, toParentId: originalParentId ?? doc.root.id, atIndex: originalIndex)
            doc.focusedNodeId = previousFocusId
        }
        undoManager.setActionName("Move")

        structureDidChange(dirtyNodeIds: [nodeId])
        checkReminderReschedule(node)
    }

    /// Move multiple selected nodes to be siblings after a target node (for iOS drag-drop)
    func moveSelectedNodesAfter(targetId: UUID) {
        guard !selectedNodeIds.isEmpty else { return }

        let target = root.find(id: targetId)
        guard let targetParent = target?.parent,
              let targetIndex = target?.indexInParent else { return }

        // Get selected nodes sorted by their current position (to maintain relative order)
        let selectedNodes = selectedNodeIds.compactMap { root.find(id: $0) }
        let sortedNodes = selectedNodes.sorted { n1, n2 in
            let visible = visibleNodes
            let i1 = visible.firstIndex(of: n1) ?? 0
            let i2 = visible.firstIndex(of: n2) ?? 0
            return i1 < i2
        }

        // Save state for undo
        struct MoveInfo {
            let nodeId: UUID
            let originalParentId: UUID?
            let originalIndex: Int
        }
        var moveInfos: [MoveInfo] = []
        for node in sortedNodes {
            moveInfos.append(MoveInfo(
                nodeId: node.id,
                originalParentId: node.parent?.id,
                originalIndex: node.indexInParent ?? 0
            ))
        }
        let previousFocusId = focusedNodeId

        // Remove all selected nodes first
        for node in sortedNodes {
            // Skip if this is the target or a descendant would cause issues
            if node.id == targetId { continue }
            if target?.isDescendant(of: node) == true { continue }
            node.removeFromParent()
        }

        // Insert after target in reverse order to maintain relative positions
        var insertIndex = targetIndex + 1
        for node in sortedNodes {
            if node.id == targetId { continue }
            if target?.isDescendant(of: node) == true { continue }
            targetParent.addChild(node, at: insertIndex)
            insertIndex += 1
        }

        // Register undo
        undoManager.registerUndo(withTarget: self) { doc in
            // Restore in reverse order
            for info in moveInfos.reversed() {
                doc.moveNodeForUndo(info.nodeId, toParentId: info.originalParentId ?? doc.root.id, atIndex: info.originalIndex)
            }
            doc.focusedNodeId = previousFocusId
        }
        undoManager.setActionName("Move")

        let movedIds = Set(sortedNodes.map { $0.id })
        structureDidChange(dirtyNodeIds: movedIds)
        for movedNode in sortedNodes {
            checkReminderReschedule(movedNode)
        }
    }

    // MARK: - Reminder Cleanup on Delete

    /// Remove Apple Reminders linked to a node and its descendants before deletion.
    private func cleanupReminders(for node: OutlineNode) {
        guard !ReminderSyncEngine.shared.isApplyingReminderChanges else { return }
        let nodesToCheck = [node] + node.flattened()
        for n in nodesToCheck where n.reminderIdentifier != nil {
            ReminderSyncEngine.shared.removeReminder(for: n)
        }
    }

    /// When deleting a metadata child (note/link), sync the cleared field back to the parent's reminder
    /// so the inbound sync doesn't recreate it.
    private func cleanupMetadataChild(_ node: OutlineNode) {
        guard node.reminderChildType != nil,
              let parent = node.parent,
              parent.reminderIdentifier != nil,
              !ReminderSyncEngine.shared.isApplyingReminderChanges else { return }
        // After the node is removed from parent, sync will see no note/link child and clear the field
        // We schedule this to run after removeFromParent() completes
        let parentNode = parent
        DispatchQueue.main.async {
            ReminderSyncEngine.shared.syncMetadataChildrenToReminder(parentNode)
        }
    }

    // MARK: - Reminder Reschedule Hook

    /// After moving a node (indent, outdent, drag-drop), check if its reminder
    /// due date needs updating based on the new date node ancestor.
    /// Also checks descendants in case a parent with synced children was moved.
    private func checkReminderReschedule(_ node: OutlineNode) {
        guard !ReminderSyncEngine.shared.isApplyingReminderChanges else { return }
        let nodesToCheck = [node] + node.flattened()
        for n in nodesToCheck {
            guard n.reminderIdentifier != nil else { continue }
            if let newDate = DateStructureManager.shared.inferredDueDate(for: n) {
                ReminderSyncEngine.shared.updateDueDate(for: n, newDate: newDate)
            }
        }
    }

    // MARK: - Movement Undo Helpers

    private func moveUpForUndo(_ nodeId: UUID) {
        guard let node = root.find(id: nodeId),
              let parent = node.parent,
              let index = node.indexInParent,
              index > 0 else { return }

        parent.children.remove(at: index)
        parent.children.insert(node, at: index - 1)

        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveDownForUndo(nodeId)
        }

        structureDidChange()
    }

    private func moveDownForUndo(_ nodeId: UUID) {
        guard let node = root.find(id: nodeId),
              let parent = node.parent,
              let index = node.indexInParent,
              index < parent.children.count - 1 else { return }

        parent.children.remove(at: index)
        parent.children.insert(node, at: index + 1)

        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveUpForUndo(nodeId)
        }

        structureDidChange()
    }

    private func moveNodeForUndo(_ nodeId: UUID, toParentId: UUID, atIndex: Int) {
        guard let node = root.find(id: nodeId),
              let newParent = root.find(id: toParentId) else { return }

        let currentParentId = node.parent?.id ?? root.id
        let currentIndex = node.indexInParent ?? 0

        node.removeFromParent()
        let safeIndex = min(atIndex, newParent.children.count)
        newParent.addChild(node, at: safeIndex)

        undoManager.registerUndo(withTarget: self) { doc in
            doc.moveNodeForUndo(nodeId, toParentId: currentParentId, atIndex: currentIndex)
        }

        structureDidChange(dirtyNodeIds: [nodeId])
    }
}

// MARK: - Remote Changes (CloudKit Sync)

extension OutlineDocument {
    /// Apply incoming remote changes from CloudKit without triggering outbound sync.
    /// Called by CloudKitSyncEngine when new records are fetched.
    @MainActor
    func applyRemoteChanges(_ changes: [NodeRecordMapper.RemoteNodeChange]) {
        guard !changes.isEmpty else { return }

        isApplyingRemoteChanges = true
        defer {
            isApplyingRemoteChanges = false
            structureVersion += 1
            scheduleAutoSave()
        }

        for change in changes {
            applyRemoteChange(change)
        }

        print("[Sync] Applied \(changes.count) remote changes")
    }

    /// Apply a single remote node change (upsert)
    @MainActor
    private func applyRemoteChange(_ change: NodeRecordMapper.RemoteNodeChange) {
        if let existingNode = root.find(id: change.nodeId) {
            // Update existing node
            // Skip title update if user is actively editing this node
            if focusedNodeId != change.nodeId {
                existingNode.title = change.title
            }
            existingNode.body = change.body
            existingNode.isTask = change.isTask
            existingNode.isTaskCompleted = change.isTaskCompleted
            existingNode.sortIndex = change.sortIndex
            existingNode.lastModifiedLocally = change.modifiedLocally
            existingNode.cloudKitSystemFields = change.systemFieldsData
            existingNode.reminderIdentifier = change.reminderIdentifier
            existingNode.reminderListName = change.reminderListName
            existingNode.reminderTimeHour = change.reminderTimeHour
            existingNode.reminderTimeMinute = change.reminderTimeMinute
            existingNode.reminderChildType = change.reminderChildType
            existingNode.isDateNode = change.isDateNode
            existingNode.dateNodeDate = change.dateNodeDate

            // Check if parent changed (node was moved remotely)
            let currentParentId = existingNode.parent?.id
            if change.parentId != currentParentId && !(change.parentId == nil && existingNode.parent?.isRoot == true) {
                // Re-parent the node
                existingNode.removeFromParent()
                let newParent: OutlineNode
                if let parentId = change.parentId, let found = root.find(id: parentId) {
                    newParent = found
                } else {
                    newParent = root
                }
                // Insert sorted by sortIndex
                let insertIndex = newParent.children.firstIndex(where: { $0.sortIndex > change.sortIndex })
                    ?? newParent.children.endIndex
                newParent.addChild(existingNode, at: insertIndex)
            }
        } else {
            // Create new node
            let newNode = OutlineNode(
                id: change.nodeId,
                title: change.title,
                body: change.body,
                isTask: change.isTask,
                isTaskCompleted: change.isTaskCompleted,
                sortIndex: change.sortIndex,
                lastModifiedLocally: change.modifiedLocally,
                cloudKitSystemFields: change.systemFieldsData,
                reminderIdentifier: change.reminderIdentifier,
                reminderListName: change.reminderListName,
                reminderTimeHour: change.reminderTimeHour,
                reminderTimeMinute: change.reminderTimeMinute,
                reminderChildType: change.reminderChildType,
                isDateNode: change.isDateNode,
                dateNodeDate: change.dateNodeDate
            )

            // Find parent
            let parent: OutlineNode
            if let parentId = change.parentId, let found = root.find(id: parentId) {
                parent = found
            } else {
                parent = root
            }

            // Insert sorted by sortIndex
            let insertIndex = parent.children.firstIndex(where: { $0.sortIndex > change.sortIndex })
                ?? parent.children.endIndex
            parent.addChild(newNode, at: insertIndex)
        }
    }

    /// Apply remote deletions from CloudKit
    @MainActor
    func applyRemoteDeletions(_ nodeIds: [UUID]) {
        guard !nodeIds.isEmpty else { return }

        isApplyingRemoteChanges = true
        defer {
            isApplyingRemoteChanges = false
            structureVersion += 1
            scheduleAutoSave()
        }

        for nodeId in nodeIds {
            if let node = root.find(id: nodeId) {
                // If the user is focused on this node, move focus
                if focusedNodeId == nodeId {
                    let visible = visibleNodes
                    if let index = visible.firstIndex(of: node) {
                        if index > 0 {
                            focusedNodeId = visible[index - 1].id
                        } else if index < visible.count - 1 {
                            focusedNodeId = visible[index + 1].id
                        } else {
                            focusedNodeId = nil
                        }
                    }
                }
                node.removeFromParent()
            }
        }

        // Ensure minimum node
        if root.children.isEmpty {
            let newNode = OutlineNode(title: "")
            root.addChild(newNode)
            focusedNodeId = newNode.id
        }

        print("[Sync] Applied \(nodeIds.count) remote deletions")
    }
}

// MARK: - Document Creation

extension OutlineDocument {
    /// Creates an empty document with one blank bullet (for new documents)
    @MainActor
    static func createEmpty() -> OutlineDocument {
        let root = OutlineNode(title: "__root__")
        // Start with one empty bullet - init will handle this, but be explicit
        let emptyNode = OutlineNode(title: "")
        root.addChild(emptyNode)
        let doc = OutlineDocument(root: root)
        doc.focusedNodeId = emptyNode.id
        return doc
    }

    @MainActor
    static func sample() -> OutlineDocument {
        OutlineDocument(root: MarkdownCodec.sampleOutline())
    }

    @MainActor
    static func createSample() -> OutlineDocument {
        let root = OutlineNode(title: "__root__")
        // Create basic sample structure
        let inbox = OutlineNode(title: "Inbox", body: "Quick capture area")
        inbox.addChild(OutlineNode(title: "New idea"))

        let today = OutlineNode(title: "Today", body: "Focus on these")
        today.addChild(OutlineNode(title: "First task"))
        today.addChild(OutlineNode(title: "Second task"))

        let projects = OutlineNode(title: "Projects")
        let project1 = OutlineNode(title: "Project Alpha")
        project1.addChild(OutlineNode(title: "Research"))
        project1.addChild(OutlineNode(title: "Design"))
        projects.addChild(project1)

        root.addChild(inbox)
        root.addChild(today)
        root.addChild(projects)

        return OutlineDocument(root: root)
    }
}
