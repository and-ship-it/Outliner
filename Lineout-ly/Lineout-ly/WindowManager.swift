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

/// Manages shared document state across windows
@Observable
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// The shared document across all windows
    private(set) var document: OutlineDocument?

    /// Loading state
    var isLoading = true
    var loadError: Error?

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
        // Start loading - will show loading indicator briefly
        self.isLoading = true
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

    /// Whether document has been loaded
    private var documentLoaded = false

    func loadDocumentIfNeeded() async {
        guard !documentLoaded else { return }  // Already loaded
        documentLoaded = true

        loadError = nil
        isLoading = true

        do {
            let icloud = iCloudManager.shared

            // Check iCloud availability
            await icloud.checkICloudAvailability()

            // Ensure week filename is set before checking cache
            icloud.updateCurrentWeekFileName()

            var doc: OutlineDocument

            // Try loading from JSON cache first (preserves UUIDs)
            if let cachedRoot = LocalNodeCache.shared.load() {
                print("[WindowManager] Loaded from JSON cache, nodes: \(cachedRoot.children.count)")
                doc = OutlineDocument(root: cachedRoot)

                // Still set up iCloud for sync (but don't wait for download)
                if icloud.isICloudAvailable {
                    try? await icloud.setupOnFirstLaunch()
                }
            } else if icloud.isICloudAvailable {
                print("[WindowManager] No cache found, loading from iCloud...")
                doc = try await icloud.loadDocument()

                // Assign sort indices and save to cache for next launch
                doc.root.assignSortIndices()
                try? LocalNodeCache.shared.save(doc.root)
                print("[WindowManager] Saved initial cache from iCloud document")
            } else {
                print("[WindowManager] No cache, loading from local storage...")
                doc = try icloud.loadLocalDocument()

                // Assign sort indices and save to cache for next launch
                doc.root.assignSortIndices()
                try? LocalNodeCache.shared.save(doc.root)
                print("[WindowManager] Saved initial cache from local document")
            }

            print("[WindowManager] Document loaded, nodes: \(doc.root.children.count)")

            doc.autoSaveEnabled = true
            self.document = doc
            self.isLoading = false

        } catch {
            print("[WindowManager] Load error: \(error)")
            loadError = error
            isLoading = false
        }
    }

    func reloadDocument() async {
        document = nil
        documentLoaded = false
        await loadDocumentIfNeeded()
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
