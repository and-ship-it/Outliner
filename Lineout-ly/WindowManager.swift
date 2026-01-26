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

    /// Pending zoom for next window (set before opening new tab)
    var pendingZoom: UUID?

    /// Queue of pending zooms for session restore (each new tab pops one)
    var pendingZoomQueue: [UUID?] = []

    /// Queue of pending collapse states for session restore
    var pendingCollapseQueue: [Set<UUID>] = []

    /// Queue of pending font sizes for session restore
    var pendingFontSizeQueue: [Double] = []

    /// Queue of pending always-on-top states for session restore
    var pendingAlwaysOnTopQueue: [Bool] = []

    /// Index of the tab that should be active after restore
    var pendingActiveTabIndex: Int = 0

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

    private init() {}

    /// Pop the next pending zoom from the queue (for session restore)
    func popPendingZoom() -> UUID? {
        guard !pendingZoomQueue.isEmpty else { return nil }
        return pendingZoomQueue.removeFirst()
    }

    /// Pop the next pending collapse state from the queue (for session restore)
    func popPendingCollapseState() -> Set<UUID>? {
        guard !pendingCollapseQueue.isEmpty else { return nil }
        return pendingCollapseQueue.removeFirst()
    }

    /// Pop the next pending font size from the queue (for session restore)
    func popPendingFontSize() -> Double? {
        guard !pendingFontSizeQueue.isEmpty else { return nil }
        return pendingFontSizeQueue.removeFirst()
    }

    /// Pop the next pending always-on-top state from the queue (for session restore)
    func popPendingAlwaysOnTop() -> Bool? {
        guard !pendingAlwaysOnTopQueue.isEmpty else { return nil }
        return pendingAlwaysOnTopQueue.removeFirst()
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

    /// Get all current tab states for session saving (in tab order)
    func getCurrentTabStates() -> [SessionManager.TabState] {
        return tabOrder.compactMap { windowId in
            guard tabZoomStates[windowId] != nil else { return nil }
            let zoomId = tabZoomStates[windowId] ?? nil
            let collapsedIds = tabCollapseStates[windowId] ?? []
            let fontSize = tabFontSizes[windowId] ?? 13.0
            let isAlwaysOnTop = tabAlwaysOnTop[windowId] ?? false
            return SessionManager.TabState(
                zoomedNodeId: zoomId?.uuidString,
                collapsedNodeIds: collapsedIds.map { $0.uuidString },
                fontSize: fontSize,
                isAlwaysOnTop: isAlwaysOnTop
            )
        }
    }

    /// Get the index of the currently active tab
    func getActiveTabIndex() -> Int {
        #if os(macOS)
        guard let keyWindow = NSApp.keyWindow,
              let tabGroup = keyWindow.tabGroup else {
            return 0
        }

        // Find the index of the key window in the tab group
        for (index, window) in tabGroup.windows.enumerated() {
            if window == keyWindow {
                return index
            }
        }
        #endif
        return 0
    }

    /// Select the tab at the pending active index
    func selectActiveTab() {
        #if os(macOS)
        guard let window = NSApp.keyWindow,
              let tabGroup = window.tabGroup,
              pendingActiveTabIndex < tabGroup.windows.count else {
            return
        }

        let targetWindow = tabGroup.windows[pendingActiveTabIndex]
        targetWindow.makeKeyAndOrderFront(nil)
        print("[Session] Switched to tab index: \(pendingActiveTabIndex)")
        #endif
    }

    // MARK: - Document Loading

    /// Pending auto-zoom node for first tab on launch
    private(set) var autoZoomNodeId: UUID?

    func loadDocumentIfNeeded() async {
        guard document == nil else { return }

        isLoading = true
        loadError = nil

        do {
            let icloud = iCloudManager.shared

            // Re-check iCloud availability
            await icloud.checkICloudAvailability()

            var doc: OutlineDocument

            if icloud.isICloudAvailable {
                print("[WindowManager] Loading from iCloud...")
                doc = try await icloud.loadDocument()
            } else {
                print("[WindowManager] iCloud not available, loading from local...")
                doc = try icloud.loadLocalDocument()
            }

            doc.autoSaveEnabled = true
            self.document = doc
            print("[WindowManager] Document loaded, nodes: \(doc.root.children.count)")
            print("[WindowManager] Current week file: \(icloud.currentWeekFileName)")

            // Auto-zoom on launch: create new bullet and prepare to zoom into it
            let newNode = OutlineNode(title: "")
            doc.root.addChild(newNode, at: 0)  // Insert at top
            autoZoomNodeId = newNode.id
            doc.focusedNodeId = newNode.id
            print("[WindowManager] Auto-zoom: created new node \(newNode.id.uuidString.prefix(8))")

            // Trigger save for the new node
            doc.autoSaveEnabled = true
            icloud.scheduleAutoSave(for: doc)

        } catch {
            print("[WindowManager] Load error: \(error)")
            loadError = error
        }

        isLoading = false
    }

    /// Consume the auto-zoom node ID (call once from first tab)
    func consumeAutoZoomNodeId() -> UUID? {
        let id = autoZoomNodeId
        autoZoomNodeId = nil
        return id
    }

    func reloadDocument() async {
        document = nil
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
