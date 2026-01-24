//
//  OutlineDocument.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
import SwiftUI
import Combine

/// The main document model managing the outline tree state
@Observable
@MainActor
final class OutlineDocument {
    /// The invisible root node - its children are the top-level items
    var root: OutlineNode

    /// Currently focused/selected node
    var focusedNodeId: UUID?

    /// Current zoom root (nil = document root, showing all top-level items)
    var zoomedNodeId: UUID?

    /// Version counter - increments on any structural change to trigger re-renders
    var structureVersion: Int = 0

    /// Whether auto-save is enabled (set to false during loading)
    var autoSaveEnabled: Bool = true

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
    private func structureDidChange() {
        structureVersion += 1
        scheduleAutoSave()
    }

    /// Call this after content changes (title, body edits)
    func contentDidChange() {
        scheduleAutoSave()
    }

    /// Schedule an auto-save via iCloudManager
    private func scheduleAutoSave() {
        guard autoSaveEnabled else { return }
        iCloudManager.shared.scheduleAutoSave(for: self)
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

    /// All visible nodes respecting collapse and zoom state
    var visibleNodes: [OutlineNode] {
        displayRoot.flattenedVisible()
    }

    // MARK: - Focus Operations

    func setFocus(_ node: OutlineNode?) {
        focusedNodeId = node?.id
    }

    func moveFocusUp() {
        guard let focused = focusedNode else {
            // Focus first visible node
            focusedNodeId = visibleNodes.first?.id
            return
        }

        let visible = visibleNodes
        guard let index = visible.firstIndex(of: focused), index > 0 else { return }
        focusedNodeId = visible[index - 1].id
    }

    func moveFocusDown() {
        guard let focused = focusedNode else {
            // Focus first visible node
            focusedNodeId = visibleNodes.first?.id
            return
        }

        let visible = visibleNodes
        guard let index = visible.firstIndex(of: focused), index < visible.count - 1 else { return }
        focusedNodeId = visible[index + 1].id
    }

    func focusParent() {
        guard let focused = focusedNode, let parent = focused.parent else { return }
        // Don't focus the invisible root or go above zoom level
        if parent.isRoot || parent.id == zoomedNodeId { return }
        focusedNodeId = parent.id
    }

    func focusFirstChild() {
        guard let focused = focusedNode, let child = focused.firstChild else { return }
        // Expand if collapsed
        if focused.isCollapsed {
            focused.expand()
        }
        focusedNodeId = child.id
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
            zoomedNodeId = nil
        } else {
            zoomedNodeId = parent.id
        }
    }

    func zoomToRoot() {
        zoomedNodeId = nil
    }

    func zoomTo(_ node: OutlineNode) {
        zoomedNodeId = node.id
        focusedNodeId = node.children.first?.id
    }

    // MARK: - Node Creation

    @discardableResult
    func createSiblingBelow(withTitle title: String = "") -> OutlineNode? {
        guard let focused = focusedNode, let _ = focused.parent else {
            // Create at root level
            let newNode = OutlineNode(title: title)
            root.addChild(newNode)
            structureDidChange()

            // Defer focus to next run loop to allow SwiftUI to create the view
            DispatchQueue.main.async { [weak self] in
                self?.focusedNodeId = newNode.id
            }

            return newNode
        }

        let newNode = OutlineNode(title: title)
        focused.insertSiblingBelow(newNode)
        structureDidChange()

        // Defer focus to next run loop to allow SwiftUI to create the view
        DispatchQueue.main.async { [weak self] in
            self?.focusedNodeId = newNode.id
        }

        return newNode
    }

    @discardableResult
    func createSiblingAbove() -> OutlineNode? {
        guard let focused = focusedNode, focused.parent != nil else {
            // Create at root level (at beginning)
            let newNode = OutlineNode()
            root.addChild(newNode, at: 0)
            structureDidChange()

            // Defer focus to next run loop to allow SwiftUI to create the view
            DispatchQueue.main.async { [weak self] in
                self?.focusedNodeId = newNode.id
            }

            return newNode
        }

        let newNode = OutlineNode()
        focused.insertSiblingAbove(newNode)
        structureDidChange()

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

        let newNode = OutlineNode()
        focused.addChild(newNode, at: 0)
        focused.expand()
        structureDidChange()

        // Defer focus to next run loop to allow SwiftUI to create the view
        DispatchQueue.main.async { [weak self] in
            self?.focusedNodeId = newNode.id
        }

        return newNode
    }

    // MARK: - Node Deletion

    func deleteFocused() {
        guard let focused = focusedNode else { return }

        // Check if this is the last node - if so, just clear it instead of deleting
        let visible = visibleNodes
        if visible.count == 1 && focused == visible.first {
            // Last node - clear its content but keep it
            focused.title = ""
            focused.body = ""
            return
        }

        // Move to trash before deleting
        TrashBin.shared.trash(focused)

        // Find next node to focus
        if let index = visible.firstIndex(of: focused) {
            if index < visible.count - 1 {
                focusedNodeId = visible[index + 1].id
            } else if index > 0 {
                focusedNodeId = visible[index - 1].id
            } else {
                focusedNodeId = nil
            }
        }

        focused.removeFromParent()

        // Ensure there's always at least one node
        ensureMinimumNode()

        structureDidChange()
    }

    /// Delete the focused node and all its children
    func deleteFocusedWithChildren() {
        guard let focused = focusedNode else { return }

        // Check if this is the last top-level node - if so, just clear it instead of deleting
        let visible = visibleNodes
        if visible.count == 1 && focused == visible.first {
            // Last node - clear its content and children but keep it
            focused.title = ""
            focused.body = ""
            focused.children.removeAll()
            return
        }

        // Move to trash before deleting (includes all children)
        TrashBin.shared.trash(focused)

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

    // MARK: - Node Movement

    func moveUp() {
        guard let focused = focusedNode,
              let parent = focused.parent,
              let index = focused.indexInParent,
              index > 0 else { return }

        parent.children.remove(at: index)
        parent.children.insert(focused, at: index - 1)
        structureDidChange()
    }

    func moveDown() {
        guard let focused = focusedNode,
              let parent = focused.parent,
              let index = focused.indexInParent,
              index < parent.children.count - 1 else { return }

        parent.children.remove(at: index)
        parent.children.insert(focused, at: index + 1)
        structureDidChange()
    }

    func indent() {
        guard let focused = focusedNode,
              let previousSibling = focused.previousSibling else { return }

        focused.removeFromParent()
        previousSibling.addChild(focused)
        previousSibling.expand()
        structureDidChange()
    }

    func outdent() {
        guard let focused = focusedNode,
              let parent = focused.parent,
              let grandparent = parent.parent else { return }

        // Get parent's index to insert after it
        guard let parentIndex = parent.indexInParent else { return }

        focused.removeFromParent()
        grandparent.addChild(focused, at: parentIndex + 1)
        structureDidChange()
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
