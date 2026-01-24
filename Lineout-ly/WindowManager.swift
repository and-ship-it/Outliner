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

    /// Track active tabs and their zoom states
    private var tabZoomStates: [UUID: UUID?] = [:]  // windowId -> zoomedNodeId

    private init() {}

    /// Pop the next pending zoom from the queue (for session restore)
    func popPendingZoom() -> UUID? {
        guard !pendingZoomQueue.isEmpty else { return nil }
        return pendingZoomQueue.removeFirst()
    }

    // MARK: - Tab Tracking

    /// Register a tab when it appears
    func registerTab(windowId: UUID) {
        if tabZoomStates[windowId] == nil {
            tabZoomStates[windowId] = nil
        }
    }

    /// Update a tab's zoom state
    func registerTabZoom(windowId: UUID, zoomedNodeId: UUID?) {
        tabZoomStates[windowId] = zoomedNodeId
    }

    /// Remove a tab when it closes
    func unregisterTab(windowId: UUID) {
        tabZoomStates.removeValue(forKey: windowId)
    }

    /// Get all current tab states for session saving
    func getCurrentTabStates() -> [SessionManager.TabState] {
        return tabZoomStates.map { (_, zoomId) in
            SessionManager.TabState(zoomedNodeId: zoomId?.uuidString)
        }
    }

    // MARK: - Document Loading

    func loadDocumentIfNeeded() async {
        guard document == nil else { return }

        isLoading = true
        loadError = nil

        do {
            let icloud = iCloudManager.shared

            // Re-check iCloud availability
            icloud.checkICloudAvailability()

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

            // Restore previous session if enabled
            SessionManager.shared.restoreSessionIfNeeded(document: doc)

        } catch {
            print("[WindowManager] Load error: \(error)")
            loadError = error
        }

        isLoading = false
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
