//
//  ContentView.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Root view for each window - manages zoom state per window
struct ContentView: View {
    /// Unique ID for this window instance
    @State private var windowId = UUID()

    #if os(macOS)
    /// Environment action to open new windows
    @Environment(\.openWindow) private var openWindow
    #endif

    /// Zoomed node ID for this window (persisted per scene/window)
    @SceneStorage("zoomedNodeId") private var zoomedNodeIdString: String = ""

    /// Font size for this window (persisted per scene/window)
    @SceneStorage("fontSize") private var fontSize: Double = 13.0

    /// Focus mode - dims everything except the focused bullet
    @State private var isFocusMode: Bool = false

    /// Search mode - shows search bar
    @State private var isSearching: Bool = false

    /// Always on top mode - window floats above others
    @State private var isAlwaysOnTop: Bool = false

    /// Per-tab collapsed node IDs (separate from document's node.isCollapsed)
    @State private var collapsedNodeIds: Set<UUID> = []

    /// Whether collapse state has been initialized
    @State private var collapseStateInitialized: Bool = false

    /// Computed zoom ID
    private var zoomedNodeId: UUID? {
        get { UUID(uuidString: zoomedNodeIdString) }
    }

    private func setZoomedNodeId(_ id: UUID?) {
        zoomedNodeIdString = id?.uuidString ?? ""
    }

    /// Tab title based on zoom state
    private var tabTitle: String {
        guard let document = WindowManager.shared.document else { return "Lineout" }

        // Get week name for home title (e.g., "2025-Jan-W05")
        let weekName = iCloudManager.shared.currentWeekFileName.replacingOccurrences(of: ".md", with: "")

        guard let zoomId = zoomedNodeId,
              let zoomedNode = document.root.find(id: zoomId) else {
            return weekName.isEmpty ? "Home" : weekName
        }
        // Use the zoomed node's title, or "Untitled" if empty
        let title = zoomedNode.title.isEmpty ? "Untitled" : zoomedNode.title
        // Truncate if too long
        return String(title.prefix(25))
    }

    var body: some View {
        let zoomBinding = Binding<UUID?>(
            get: { zoomedNodeId },
            set: { setZoomedNodeId($0) }
        )

        Group {
            if WindowManager.shared.isLoading {
                loadingView
            } else if let error = WindowManager.shared.loadError {
                errorView(error)
            } else if let document = WindowManager.shared.document {
                documentView(document, zoomBinding: zoomBinding)
            }
        }
        .environment(\.windowId, windowId)
        .focusedSceneValue(\.zoomedNodeId, zoomBinding)
        .task {
            await WindowManager.shared.loadDocumentIfNeeded()

            // Check for pending zoom from Cmd+T (new tab from current) - takes priority
            if let pending = WindowManager.shared.pendingZoom {
                print("[Session] Tab \(windowId) using pendingZoom: \(pending)")
                setZoomedNodeId(pending)
                // Set focus to first child of zoomed node so cursor is visible and functional
                if let doc = WindowManager.shared.document,
                   let zoomedNode = doc.root.find(id: pending) {
                    if let firstChild = zoomedNode.children.first {
                        doc.focusedNodeId = firstChild.id
                    } else {
                        // If no children, focus the zoomed node itself
                        doc.focusedNodeId = pending
                    }
                }
                WindowManager.shared.pendingZoom = nil
            }
            // Legacy: Check for pending state from session restore queue
            else if !WindowManager.shared.pendingZoomQueue.isEmpty {
                // Pop zoom state
                let zoomId = WindowManager.shared.popPendingZoom()
                print("[Session] Tab \(windowId) popped zoom: \(zoomId?.uuidString ?? "nil")")
                if let zoomId {
                    setZoomedNodeId(zoomId)
                }

                // Pop collapse state
                if let collapseState = WindowManager.shared.popPendingCollapseState() {
                    collapsedNodeIds = collapseState
                    collapseStateInitialized = true
                    WindowManager.shared.registerTabCollapseState(windowId: windowId, collapsedNodeIds: collapseState)
                    print("[Session] Tab \(windowId) popped collapse state: \(collapseState.count) collapsed nodes")
                }

                // Pop font size
                if let restoredFontSize = WindowManager.shared.popPendingFontSize() {
                    fontSize = restoredFontSize
                    WindowManager.shared.registerTabFontSize(windowId: windowId, fontSize: restoredFontSize)
                    print("[Session] Tab \(windowId) popped fontSize: \(restoredFontSize)")
                }

                // Pop always-on-top state
                if let restoredAlwaysOnTop = WindowManager.shared.popPendingAlwaysOnTop() {
                    isAlwaysOnTop = restoredAlwaysOnTop
                    WindowManager.shared.registerTabAlwaysOnTop(windowId: windowId, isAlwaysOnTop: restoredAlwaysOnTop)
                    print("[Session] Tab \(windowId) popped alwaysOnTop: \(restoredAlwaysOnTop)")
                }
            }
            // Default: Auto-zoom into fresh bullet (new window/tab without special context)
            else if let doc = WindowManager.shared.document {
                // Create new bullet at top and zoom into it
                let newNode = OutlineNode(title: "")
                doc.root.addChild(newNode, at: 0)
                setZoomedNodeId(newNode.id)
                doc.focusedNodeId = newNode.id
                collapseStateInitialized = true  // Start fresh
                print("[Launch] Auto-zoom: created new node \(newNode.id.uuidString.prefix(8)) for new window")
                iCloudManager.shared.scheduleAutoSave(for: doc)
            }

            // If no collapse state was restored, initialize from document
            if !collapseStateInitialized {
                if let doc = WindowManager.shared.document {
                    // Initialize collapse state from document's node.isCollapsed
                    var initialCollapsed = Set<UUID>()
                    for node in doc.root.flattened() {
                        if node.isCollapsed {
                            initialCollapsed.insert(node.id)
                        }
                    }
                    collapsedNodeIds = initialCollapsed
                    WindowManager.shared.registerTabCollapseState(windowId: windowId, collapsedNodeIds: initialCollapsed)
                }
                collapseStateInitialized = true
            }

            // Register initial font size and always-on-top state
            WindowManager.shared.registerTabFontSize(windowId: windowId, fontSize: fontSize)
            WindowManager.shared.registerTabAlwaysOnTop(windowId: windowId, isAlwaysOnTop: isAlwaysOnTop)
        }
        .onDisappear {
            // Release all locks when window closes
            WindowManager.shared.releaseAllLocks(for: windowId)
            // Unregister the tab to clean up state
            WindowManager.shared.unregisterTab(windowId: windowId)
        }
        .onChange(of: zoomedNodeIdString) { _, newValue in
            // Track zoom changes for session save
            WindowManager.shared.registerTabZoom(windowId: windowId, zoomedNodeId: UUID(uuidString: newValue))
        }
        .onChange(of: fontSize) { _, newValue in
            // Track font size changes for session save
            WindowManager.shared.registerTabFontSize(windowId: windowId, fontSize: newValue)
        }
        .onChange(of: isAlwaysOnTop) { _, newValue in
            // Track always-on-top changes for session save
            WindowManager.shared.registerTabAlwaysOnTop(windowId: windowId, isAlwaysOnTop: newValue)
        }
        .onAppear {
            // Register this tab with WindowManager
            WindowManager.shared.registerTab(windowId: windowId)

            #if os(macOS)
            // Store openWindow action for use when no windows exist
            WindowOpener.shared.openWindowAction = {
                openWindow(id: "main")
            }
            #endif
        }
        #if os(macOS)
        .background(WindowAccessor(windowId: windowId, title: tabTitle, isAlwaysOnTop: isAlwaysOnTop))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // When any window becomes key (active), ensure focus is refreshed
            guard let doc = WindowManager.shared.document else { return }

            // Refresh focus to ensure cursor appears after tab close
            if doc.focusedNodeId != nil {
                doc.focusVersion += 1
                print("[Focus] Window became key, refreshing focus (version: \(doc.focusVersion))")
            }
        }
        #endif
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your outline...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to load document")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task {
                    await WindowManager.shared.reloadDocument()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func documentView(_ document: OutlineDocument, zoomBinding: Binding<UUID?>) -> some View {
        OutlineView(
            document: document,
            zoomedNodeId: zoomBinding,
            windowId: windowId,
            fontSize: $fontSize,
            isFocusMode: $isFocusMode,
            isSearching: $isSearching,
            collapsedNodeIds: $collapsedNodeIds
        )
        .focusedSceneValue(\.document, document)
        .focusedSceneValue(\.fontSize, $fontSize)
        .focusedSceneValue(\.isFocusMode, $isFocusMode)
        .focusedSceneValue(\.isSearching, $isSearching)
        .focusedSceneValue(\.isAlwaysOnTop, $isAlwaysOnTop)
        .focusedSceneValue(\.undoManager, document.undoManager)
        .focusedSceneValue(\.collapsedNodeIds, $collapsedNodeIds)
        .onChange(of: collapsedNodeIds) { _, newValue in
            // Sync collapse state to WindowManager for session saving
            WindowManager.shared.registerTabCollapseState(windowId: windowId, collapsedNodeIds: newValue)
        }
    }
}

// MARK: - Window Accessor (for native tab support, title, and always on top)

#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    let windowId: UUID
    let title: String
    let isAlwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // Enable automatic tabbing
                window.tabbingMode = .automatic
                // Set initial title
                window.title = title
                // Set initial window level
                window.level = isAlwaysOnTop ? .floating : .normal
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update window title and level when they change
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.title = title
                window.level = isAlwaysOnTop ? .floating : .normal
            }
        }
    }
}
#endif

#Preview {
    ContentView()
}
