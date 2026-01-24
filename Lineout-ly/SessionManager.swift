//
//  SessionManager.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
#if os(macOS)
import AppKit
#endif

/// Manages session state persistence and restoration
@Observable
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    // MARK: - Session State Model

    struct TabState: Codable, Equatable {
        var zoomedNodeId: String?  // UUID string
        var collapsedNodeIds: [String]  // Array of collapsed node UUIDs for this tab
        var fontSize: Double  // Font size for this tab
        var isAlwaysOnTop: Bool  // Whether this tab's window floats above others

        init(
            zoomedNodeId: String? = nil,
            collapsedNodeIds: [String] = [],
            fontSize: Double = 13.0,
            isAlwaysOnTop: Bool = false
        ) {
            self.zoomedNodeId = zoomedNodeId
            self.collapsedNodeIds = collapsedNodeIds
            self.fontSize = fontSize
            self.isAlwaysOnTop = isAlwaysOnTop
        }
    }

    struct SessionState: Codable {
        var focusedNodeId: String?  // UUID string
        var tabs: [TabState]
        var activeTabIndex: Int  // Which tab was last active
        var autocompleteEnabled: Bool  // Word autocomplete setting
        var timestamp: Date
    }

    // MARK: - Settings

    /// Whether to restore previous session on launch (stored in UserDefaults)
    var restorePreviousSession: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: "restorePreviousSession") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "restorePreviousSession")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "restorePreviousSession")
        }
    }

    // MARK: - State

    private(set) var pendingSessionRestore: SessionState?
    private(set) var hasRestoredSession = false

    private let sessionFileName = "session.json"

    private init() {}

    // MARK: - Session File URL

    /// Get the session file URL (in the same folder as main.md)
    private var sessionFileURL: URL? {
        if let appFolder = iCloudManager.shared.appFolderURL {
            return appFolder.appendingPathComponent(sessionFileName)
        }
        // Fallback to local
        return iCloudManager.shared.localFallbackURL.appendingPathComponent(sessionFileName)
    }

    // MARK: - Save Session

    /// Save the current session state
    func saveSession(
        document: OutlineDocument,
        tabs: [TabState],
        activeTabIndex: Int,
        autocompleteEnabled: Bool
    ) {
        let state = SessionState(
            focusedNodeId: document.focusedNodeId?.uuidString,
            tabs: tabs,
            activeTabIndex: activeTabIndex,
            autocompleteEnabled: autocompleteEnabled,
            timestamp: Date()
        )

        guard let url = sessionFileURL else {
            print("[Session] No session file URL available")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
            print("[Session] Saved session to \(url.lastPathComponent) with \(tabs.count) tab(s)")
            for (i, tab) in tabs.enumerated() {
                print("[Session]   Tab \(i): zoom=\(tab.zoomedNodeId ?? "nil"), collapsed=\(tab.collapsedNodeIds.count) nodes, fontSize=\(tab.fontSize), alwaysOnTop=\(tab.isAlwaysOnTop)")
            }
        } catch {
            print("[Session] Failed to save session: \(error)")
        }
    }

    /// Save session from current window state
    #if os(macOS)
    func saveCurrentSession() {
        guard let document = WindowManager.shared.document else { return }

        // Get tab states from WindowManager (includes zoom, collapse, fontSize, alwaysOnTop)
        var tabStates = WindowManager.shared.getCurrentTabStates()

        // If no tabs tracked, add at least one with default state
        if tabStates.isEmpty {
            let collapsedIds = getCollapsedNodeIds(from: document.root)
            tabStates.append(TabState(
                zoomedNodeId: nil,
                collapsedNodeIds: collapsedIds,
                fontSize: 13.0,
                isAlwaysOnTop: false
            ))
        }

        // Get active tab index
        let activeTabIndex = WindowManager.shared.getActiveTabIndex()

        // Get autocomplete setting from UserDefaults
        let autocompleteEnabled = UserDefaults.standard.object(forKey: "autocompleteEnabled") == nil
            ? true  // Default to true
            : UserDefaults.standard.bool(forKey: "autocompleteEnabled")

        saveSession(
            document: document,
            tabs: tabStates,
            activeTabIndex: activeTabIndex,
            autocompleteEnabled: autocompleteEnabled
        )
    }

    /// Helper to get all collapsed node IDs from the tree
    private func getCollapsedNodeIds(from root: OutlineNode) -> [String] {
        var collapsedIds: [String] = []
        for node in root.flattened() {
            if node.isCollapsed {
                collapsedIds.append(node.id.uuidString)
            }
        }
        return collapsedIds
    }
    #endif

    // MARK: - Load Session

    /// Load the saved session state
    func loadSavedSession() -> SessionState? {
        guard let url = sessionFileURL else {
            print("[Session] No session file URL available")
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Session] No saved session file found at \(url.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(SessionState.self, from: data)
            print("[Session] Loaded session from \(state.timestamp) with \(state.tabs.count) tab(s)")
            return state
        } catch {
            print("[Session] Failed to load session: \(error)")
            return nil
        }
    }

    /// Restore session on app launch
    func restoreSessionIfNeeded(document: OutlineDocument) {
        guard restorePreviousSession, !hasRestoredSession else {
            // Start fresh - collapse all and go home
            if !restorePreviousSession {
                document.collapseAll()
                document.focusedNodeId = document.root.children.first?.id
            }
            return
        }

        hasRestoredSession = true

        guard let state = loadSavedSession() else {
            return
        }

        // Restore focused node
        if let focusedIdString = state.focusedNodeId,
           let focusedId = UUID(uuidString: focusedIdString),
           document.root.find(id: focusedId) != nil {
            document.focusedNodeId = focusedId
            print("[Session] Restored focus to node: \(focusedIdString)")
        }

        // Restore autocomplete setting
        UserDefaults.standard.set(state.autocompleteEnabled, forKey: "autocompleteEnabled")
        print("[Session] Restored autocomplete: \(state.autocompleteEnabled)")

        // Store tab states for window restoration
        pendingSessionRestore = state

        #if os(macOS)
        // Populate the queues for all tabs
        var zoomQueue: [UUID?] = []
        var collapseQueue: [Set<UUID>] = []
        var fontSizeQueue: [Double] = []
        var alwaysOnTopQueue: [Bool] = []

        for tabState in state.tabs {
            // Zoom ID
            if let zoomIdString = tabState.zoomedNodeId {
                zoomQueue.append(UUID(uuidString: zoomIdString))
            } else {
                zoomQueue.append(nil)
            }

            // Collapsed node IDs
            let collapsedSet = Set(tabState.collapsedNodeIds.compactMap { UUID(uuidString: $0) })
            collapseQueue.append(collapsedSet)

            // Font size
            fontSizeQueue.append(tabState.fontSize)

            // Always on top
            alwaysOnTopQueue.append(tabState.isAlwaysOnTop)
        }

        WindowManager.shared.pendingZoomQueue = zoomQueue
        WindowManager.shared.pendingCollapseQueue = collapseQueue
        WindowManager.shared.pendingFontSizeQueue = fontSizeQueue
        WindowManager.shared.pendingAlwaysOnTopQueue = alwaysOnTopQueue
        WindowManager.shared.pendingActiveTabIndex = state.activeTabIndex

        // Restore additional tabs if needed
        if state.tabs.count > 1 {
            // Open additional tabs with staggered delays to ensure proper queue consumption
            for i in 1..<state.tabs.count {
                let delay = 0.5 + Double(i - 1) * 0.3  // 0.5s for first, then +0.3s each
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
                }
            }

            // After all tabs are created, switch to the active tab
            let totalDelay = 0.5 + Double(state.tabs.count - 2) * 0.3 + 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                WindowManager.shared.selectActiveTab()
            }
        }
        #endif
    }

    /// Get the zoom ID for a specific tab index during restoration
    func getRestoredZoomId(forTabIndex index: Int) -> UUID? {
        guard let state = pendingSessionRestore,
              index < state.tabs.count,
              let zoomIdString = state.tabs[index].zoomedNodeId else {
            return nil
        }
        return UUID(uuidString: zoomIdString)
    }

    /// Get the collapsed node IDs for a specific tab index during restoration
    func getRestoredCollapsedNodeIds(forTabIndex index: Int) -> Set<UUID> {
        guard let state = pendingSessionRestore,
              index < state.tabs.count else {
            return []
        }
        return Set(state.tabs[index].collapsedNodeIds.compactMap { UUID(uuidString: $0) })
    }

    /// Clear the pending session restore
    func clearPendingRestore() {
        pendingSessionRestore = nil
    }
}
