//
//  WindowManager.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Manages shared document state and node locking across windows
@Observable
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// The shared document across all windows
    private(set) var document: OutlineDocument?

    /// Loading state
    var isLoading = true
    var loadError: Error?

    /// Map of nodeId -> windowId for locked nodes
    private var nodeLocks: [UUID: UUID] = [:]

    /// Pending zoom for next window (set before opening new tab via Cmd+T)
    var pendingZoom: UUID?

    /// Track active tabs and their zoom states
    private var tabZoomStates: [UUID: UUID?] = [:]  // windowId -> zoomedNodeId

    /// Track active tabs and their collapse states (per-tab collapsed node IDs)
    private var tabCollapseStates: [UUID: Set<UUID>] = [:]  // windowId -> collapsedNodeIds

    /// Track active tabs and their font sizes
    private var tabFontSizes: [UUID: Double] = [:]  // windowId -> fontSize

    /// Track active tabs and their always-on-top states
    private var tabAlwaysOnTop: [UUID: Bool] = [:]  // windowId -> isAlwaysOnTop

    /// Ordered list of tab window IDs (for tracking active tab index)
    private var tabOrder: [UUID] = []

    private init() {
        // OPTIMISTIC UI: Create placeholder document synchronously
        // This ensures the loading view is never shown
        setupPlaceholderDocument()
    }

    /// Create placeholder document immediately for optimistic UI
    private func setupPlaceholderDocument() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, d HH:mm"  // e.g., "Tue, 27 15:30"
        let dateTitle = dateFormatter.string(from: Date())

        let placeholderRoot = OutlineNode(title: "__root__")
        let placeholderNode = OutlineNode(title: dateTitle)
        placeholderRoot.addChild(placeholderNode)

        let placeholderDoc = OutlineDocument(root: placeholderRoot)
        placeholderDoc.autoSaveEnabled = false  // Don't save placeholder

        // Set up for immediate display
        self.document = placeholderDoc
        self.autoZoomNodeId = placeholderNode.id
        self.placeholderNodeId = placeholderNode.id
        self.placeholderNodeTitle = dateTitle
        self.isLoading = false  // Show UI immediately!
        self.isLoadingInBackground = true

        print("[WindowManager] Placeholder ready in init - UI visible immediately")
    }

    // MARK: - Tab Tracking

    /// Register a tab when it appears
    func registerTab(windowId: UUID) {
        if tabZoomStates[windowId] == nil {
            tabZoomStates[windowId] = nil
        }
        if tabCollapseStates[windowId] == nil {
            tabCollapseStates[windowId] = []
        }
        if tabFontSizes[windowId] == nil {
            tabFontSizes[windowId] = 13.0
        }
        if tabAlwaysOnTop[windowId] == nil {
            tabAlwaysOnTop[windowId] = false
        }
        // Add to tab order if not already present
        if !tabOrder.contains(windowId) {
            tabOrder.append(windowId)
        }
    }

    /// Update a tab's zoom state
    func registerTabZoom(windowId: UUID, zoomedNodeId: UUID?) {
        tabZoomStates[windowId] = zoomedNodeId
    }

    /// Update a tab's collapse state
    func registerTabCollapseState(windowId: UUID, collapsedNodeIds: Set<UUID>) {
        tabCollapseStates[windowId] = collapsedNodeIds
    }

    /// Get a tab's collapse state
    func getTabCollapseState(windowId: UUID) -> Set<UUID> {
        return tabCollapseStates[windowId] ?? []
    }

    /// Update a tab's font size
    func registerTabFontSize(windowId: UUID, fontSize: Double) {
        tabFontSizes[windowId] = fontSize
    }

    /// Get a tab's font size
    func getTabFontSize(windowId: UUID) -> Double {
        return tabFontSizes[windowId] ?? 13.0
    }

    /// Update a tab's always-on-top state
    func registerTabAlwaysOnTop(windowId: UUID, isAlwaysOnTop: Bool) {
        tabAlwaysOnTop[windowId] = isAlwaysOnTop
    }

    /// Get a tab's always-on-top state
    func getTabAlwaysOnTop(windowId: UUID) -> Bool {
        return tabAlwaysOnTop[windowId] ?? false
    }

    /// Toggle collapse state for a node in a specific tab
    func toggleNodeCollapse(nodeId: UUID, windowId: UUID) {
        var collapsed = tabCollapseStates[windowId] ?? []
        if collapsed.contains(nodeId) {
            collapsed.remove(nodeId)
        } else {
            collapsed.insert(nodeId)
        }
        tabCollapseStates[windowId] = collapsed
    }

    /// Collapse a node in a specific tab
    func collapseNode(nodeId: UUID, windowId: UUID) {
        var collapsed = tabCollapseStates[windowId] ?? []
        collapsed.insert(nodeId)
        tabCollapseStates[windowId] = collapsed
    }

    /// Expand a node in a specific tab
    func expandNode(nodeId: UUID, windowId: UUID) {
        var collapsed = tabCollapseStates[windowId] ?? []
        collapsed.remove(nodeId)
        tabCollapseStates[windowId] = collapsed
    }

    /// Check if a node is collapsed in a specific tab
    func isNodeCollapsed(nodeId: UUID, windowId: UUID) -> Bool {
        return tabCollapseStates[windowId]?.contains(nodeId) ?? false
    }

    /// Collapse all nodes in a specific tab
    func collapseAllNodes(windowId: UUID) {
        guard let doc = document else { return }
        var collapsed = Set<UUID>()
        for node in doc.root.flattened() {
            if node.hasChildren {
                collapsed.insert(node.id)
            }
        }
        tabCollapseStates[windowId] = collapsed
    }

    /// Expand all children of a node in a specific tab
    func expandAllChildren(of nodeId: UUID, windowId: UUID) {
        guard let doc = document,
              let node = doc.root.find(id: nodeId) else { return }
        var collapsed = tabCollapseStates[windowId] ?? []
        collapsed.remove(nodeId)
        for child in node.flattened() {
            collapsed.remove(child.id)
        }
        tabCollapseStates[windowId] = collapsed
    }

    /// Collapse all children of a node in a specific tab
    func collapseAllChildren(of nodeId: UUID, windowId: UUID) {
        guard let doc = document,
              let node = doc.root.find(id: nodeId) else { return }
        var collapsed = tabCollapseStates[windowId] ?? []
        for child in node.flattened() {
            if child.hasChildren {
                collapsed.insert(child.id)
            }
        }
        tabCollapseStates[windowId] = collapsed
    }

    /// Remove a tab when it closes
    func unregisterTab(windowId: UUID) {
        tabZoomStates.removeValue(forKey: windowId)
        tabCollapseStates.removeValue(forKey: windowId)
        tabFontSizes.removeValue(forKey: windowId)
        tabAlwaysOnTop.removeValue(forKey: windowId)
        tabOrder.removeAll { $0 == windowId }
    }

    // MARK: - Document Loading

    /// Pending auto-zoom node for first tab on launch
    private(set) var autoZoomNodeId: UUID?

    /// Whether we're still loading the real document in background
    private(set) var isLoadingInBackground = false

    /// The placeholder node that was created before real document loaded
    private var placeholderNodeId: UUID?
    private var placeholderNodeTitle: String = ""
    private var placeholderNodeChildren: [OutlineNode] = []

    func loadDocumentIfNeeded() async {
        // Placeholder was already created in init() for optimistic UI
        guard isLoadingInBackground else { return }  // Already loaded real document

        // Load real document in background
        loadError = nil

        do {
            let icloud = iCloudManager.shared

            // Re-check iCloud availability
            await icloud.checkICloudAvailability()

            var realDoc: OutlineDocument

            if icloud.isICloudAvailable {
                print("[WindowManager] Loading real document from iCloud in background...")
                realDoc = try await icloud.loadDocument()
            } else {
                print("[WindowManager] Loading real document from local in background...")
                realDoc = try icloud.loadLocalDocument()
            }

            print("[WindowManager] Real document loaded, nodes: \(realDoc.root.children.count)")

            // Capture any content user typed into placeholder while loading
            guard let placeholderDoc = self.document,
                  let placeholderId = self.placeholderNodeId,
                  let currentPlaceholder = placeholderDoc.root.find(id: placeholderId) else {
                // Placeholder was deleted somehow, just use real doc
                realDoc.autoSaveEnabled = true
                self.document = realDoc
                self.autoZoomNodeId = nil
                print("[WindowManager] Placeholder not found, using real document as-is")
                icloud.scheduleAutoSave(for: realDoc)
                isLoadingInBackground = false
                return
            }

            // Deep copy the placeholder node (preserves user's content and same ID)
            let mergedNode = currentPlaceholder.deepCopy()

            // Remove from placeholder's parent (if any)
            mergedNode.parent = nil

            // Add to real document (at the end)
            realDoc.root.addChild(mergedNode)

            // The autoZoomNodeId is already set to the placeholder's ID
            // which is now the same as mergedNode.id (since deepCopy preserves ID)

            print("[WindowManager] Merged placeholder content into real document")
            print("[WindowManager] Auto-zoom node: '\(mergedNode.title)' (\(mergedNode.id.uuidString.prefix(8)))")

            // CRITICAL: Set focus BEFORE switching documents to prevent focus loss
            // When document changes, SwiftUI re-renders and checks isFocused
            // If focusedNodeId isn't set, the text field will resign first responder
            if let firstChild = mergedNode.children.first {
                realDoc.focusedNodeId = firstChild.id
                print("[WindowManager] Pre-set focus to first child: \(firstChild.id.uuidString.prefix(8))")
            } else {
                // No children - create one and focus it
                let emptyChild = OutlineNode(title: "")
                mergedNode.addChild(emptyChild)
                realDoc.focusedNodeId = emptyChild.id
                print("[WindowManager] Created empty child and pre-set focus: \(emptyChild.id.uuidString.prefix(8))")
            }

            // Switch to real document (focus is already set, so text field won't lose focus)
            realDoc.autoSaveEnabled = true
            self.document = realDoc

            // Increment focus version after a short delay to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                realDoc.focusVersion += 1
                print("[WindowManager] Focus version incremented")
            }

            // Trigger save for the new node
            icloud.scheduleAutoSave(for: realDoc)

        } catch {
            print("[WindowManager] Load error: \(error)")
            loadError = error
            // Keep the placeholder document so user doesn't lose their work
            // They can try again later
        }

        isLoadingInBackground = false
    }

    /// Consume the auto-zoom node ID (call once from first tab)
    func consumeAutoZoomNodeId() -> UUID? {
        let id = autoZoomNodeId
        autoZoomNodeId = nil
        return id
    }

    func reloadDocument() async {
        document = nil
        placeholderNodeId = nil
        isLoadingInBackground = false
        await loadDocumentIfNeeded()
    }

    // MARK: - Node Locking

    /// Check if a node is locked by a different window
    func isNodeLocked(_ nodeId: UUID, for windowId: UUID) -> Bool {
        guard let lockingWindowId = nodeLocks[nodeId] else { return false }
        return lockingWindowId != windowId
    }

    /// Try to acquire a lock on a node for a window
    func tryLock(nodeId: UUID, for windowId: UUID) -> Bool {
        if let existingLock = nodeLocks[nodeId] {
            return existingLock == windowId
        }
        nodeLocks[nodeId] = windowId
        return true
    }

    /// Release a lock on a node
    func releaseLock(nodeId: UUID, for windowId: UUID) {
        guard nodeLocks[nodeId] == windowId else { return }
        nodeLocks.removeValue(forKey: nodeId)
    }

    /// Release all locks held by a window
    func releaseAllLocks(for windowId: UUID) {
        nodeLocks = nodeLocks.filter { $0.value != windowId }
    }

    // MARK: - New Tab

    #if os(macOS)
    /// Open a new native tab zoomed to the specified node
    func openNewTab(zoomedTo nodeId: UUID?) {
        pendingZoom = nodeId

        // Check if there's a current window
        guard NSApp.keyWindow != nil else {
            // No window, just open a new one
            if let url = URL(string: "lineout://new") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        // Trigger native "New Tab" which creates a new window in the same tab group
        NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
    }
    #endif
}

// MARK: - Environment Key for Window ID

struct WindowIdKey: EnvironmentKey {
    static let defaultValue: UUID = UUID()
}

extension EnvironmentValues {
    var windowId: UUID {
        get { self[WindowIdKey.self] }
        set { self[WindowIdKey.self] = newValue }
    }
}
