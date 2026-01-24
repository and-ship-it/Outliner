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

    struct TabState: Codable {
        var zoomedNodeId: String?  // UUID string
    }

    struct SessionState: Codable {
        var focusedNodeId: String?  // UUID string
        var tabs: [TabState]
        var fontSize: Double
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

    private let sessionKey = "savedSessionState"

    private init() {}

    // MARK: - Save Session

    /// Save the current session state
    func saveSession(document: OutlineDocument, tabs: [TabState], fontSize: Double) {
        let state = SessionState(
            focusedNodeId: document.focusedNodeId?.uuidString,
            tabs: tabs,
            fontSize: fontSize,
            timestamp: Date()
        )

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: sessionKey)
            print("[Session] Saved session with \(tabs.count) tab(s)")
        } catch {
            print("[Session] Failed to save session: \(error)")
        }
    }

    /// Save session from current window state
    #if os(macOS)
    func saveCurrentSession() {
        guard let document = WindowManager.shared.document else { return }

        // Get tab states from WindowManager
        var tabStates = WindowManager.shared.getCurrentTabStates()

        // If no tabs tracked, add at least one
        if tabStates.isEmpty {
            tabStates.append(TabState(zoomedNodeId: nil))
        }

        // Get font size from UserDefaults (SceneStorage default)
        let fontSize = UserDefaults.standard.double(forKey: "fontSize")

        saveSession(document: document, tabs: tabStates, fontSize: fontSize > 0 ? fontSize : 13.0)
    }
    #endif

    // MARK: - Load Session

    /// Load the saved session state
    func loadSavedSession() -> SessionState? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else {
            print("[Session] No saved session found")
            return nil
        }

        do {
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

            // Expand ancestors to make it visible
            if let node = document.root.find(id: focusedId) {
                var current = node.parent
                while let parent = current {
                    if parent.isCollapsed {
                        parent.expand()
                    }
                    current = parent.parent
                }
            }
            print("[Session] Restored focus to node: \(focusedIdString)")
        }

        // Store tab states for window restoration
        pendingSessionRestore = state

        #if os(macOS)
        // Restore additional tabs if needed
        if state.tabs.count > 1 {
            // Open additional tabs after a short delay to let the first window load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for i in 1..<state.tabs.count {
                    let tabState = state.tabs[i]
                    if let zoomIdString = tabState.zoomedNodeId,
                       let zoomId = UUID(uuidString: zoomIdString) {
                        WindowManager.shared.pendingZoom = zoomId
                    }
                    NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
                }
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

    /// Clear the pending session restore
    func clearPendingRestore() {
        pendingSessionRestore = nil
    }
}
