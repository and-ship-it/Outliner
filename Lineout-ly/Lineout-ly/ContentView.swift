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

    /// Scene phase for background/foreground detection
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    /// Environment action to open new windows
    @Environment(\.openWindow) private var openWindow
    #endif

    /// Zoomed node ID for this window (persisted per scene/window)
    @SceneStorage("zoomedNodeId") private var zoomedNodeIdString: String = ""

    /// Font size for this window (persisted per scene/window)
    #if os(iOS)
    @SceneStorage("fontSize") private var fontSize: Double = 18.0
    #else
    @SceneStorage("fontSize") private var fontSize: Double = 13.0
    #endif

    /// Focus mode - dims everything except the focused bullet
    @State private var isFocusMode: Bool = false

    /// Search mode - shows search bar
    @State private var isSearching: Bool = false

    /// Always on top mode - window floats above others
    @State private var isAlwaysOnTop: Bool = false

    /// Per-tab collapsed node IDs (separate from document's node.isCollapsed)
    @State private var collapsedNodeIds: Set<UUID> = []

    /// Navigation history for tab switcher (iOS and macOS)
    @State private var navigationHistory = NavigationHistoryManager()

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
            return weekName.isEmpty ? "This Week" : weekName
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
                // Focus the zoomed node itself (it appears at the top when zoomed)
                if let doc = WindowManager.shared.document {
                    doc.focusedNodeId = pending
                    doc.focusVersion += 1
                }
                WindowManager.shared.pendingZoom = nil
            }
            // Default: Start at home (root level) — reset any persisted zoom
            if WindowManager.shared.pendingZoom == nil {
                zoomedNodeIdString = ""
            }

            // Register initial font size and always-on-top state
            WindowManager.shared.registerTabFontSize(windowId: windowId, fontSize: fontSize)
            WindowManager.shared.registerTabAlwaysOnTop(windowId: windowId, isAlwaysOnTop: isAlwaysOnTop)

            // Ensure date structure exists for current week
            if let doc = WindowManager.shared.document {
                DateStructureManager.shared.ensureDateNodes(in: doc)

                // Collapse ALL nodes with children for fast launch
                var initialCollapsed = Set<UUID>()
                for node in doc.root.flattened() {
                    if node.hasChildren {
                        initialCollapsed.insert(node.id)
                    }
                }
                collapsedNodeIds = initialCollapsed
                WindowManager.shared.registerTabCollapseState(windowId: windowId, collapsedNodeIds: initialCollapsed)
                print("[Launch] Collapsed all \(initialCollapsed.count) nodes with children")

                // Focus today's date node on launch (cursor lands on the current day)
                if doc.focusedNodeId == nil,
                   zoomedNodeId == nil,
                   let todayNode = DateStructureManager.shared.todayDateNode(in: doc) {
                    #if os(iOS)
                    // On iOS, suppress keyboard on launch — user must tap a bullet to start typing
                    doc.suppressKeyboard = true
                    #endif
                    doc.focusedNodeId = todayNode.id
                    doc.focusVersion += 1
                }
            }

            // Set up CloudKit per-node sync engine (iOS 17+/macOS 14+)
            if #available(macOS 14.0, iOS 17.0, *) {
                await CloudKitSyncEngine.shared.setup()

                // Run one-time migration from markdown to CloudKit
                if let doc = WindowManager.shared.document {
                    await MigrationManager.migrateIfNeeded(document: doc)
                }
            }

            // Set up Apple Reminders bidirectional sync
            let remindersGranted = await ReminderSyncEngine.shared.requestAccess()
            if remindersGranted {
                ReminderSyncEngine.shared.startObserving()
                await ReminderSyncEngine.shared.syncExternalChanges()
            }
        }
        .onDisappear {
            // Unregister the tab to clean up state
            WindowManager.shared.unregisterTab(windowId: windowId)
        }
        .onChange(of: zoomedNodeIdString) { _, newValue in
            // Track zoom changes for session save
            WindowManager.shared.registerTabZoom(windowId: windowId, zoomedNodeId: UUID(uuidString: newValue))

            // Sync navigation history with zoom changes
            navigationHistory.syncWithZoom(UUID(uuidString: newValue))
        }
        .onChange(of: fontSize) { _, newValue in
            // Track font size changes for session save
            WindowManager.shared.registerTabFontSize(windowId: windowId, fontSize: newValue)
        }
        .onChange(of: isAlwaysOnTop) { _, newValue in
            // Track always-on-top changes for session save
            WindowManager.shared.registerTabAlwaysOnTop(windowId: windowId, isAlwaysOnTop: newValue)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onAppear {
            // Register this tab with WindowManager
            WindowManager.shared.registerTab(windowId: windowId)

            #if os(macOS)
            // Store openWindow action for use when no windows exist
            WindowOpener.shared.openWindowAction = {
                openWindow(id: "main")
            }
            #else
            // Set minimum window size for iPad Stage Manager / multitasking
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene.sizeRestrictions?.minimumSize = CGSize(width: 320, height: 480)
                }
            }
            #endif
        }
        #if os(macOS)
        .background(WindowAccessor(windowId: windowId, title: tabTitle, isAlwaysOnTop: isAlwaysOnTop))
        #endif
    }

    // MARK: - Scene Phase Handling

    /// Handle app going to background or coming to foreground
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Save immediately before going to background
            if let document = WindowManager.shared.document {
                print("[Sync] App going to background - forcing save + CloudKit flush")
                Task {
                    await iCloudManager.shared.forceSave(document)

                    // Flush any pending CloudKit changes
                    if #available(macOS 14.0, iOS 17.0, *) {
                        await CloudKitSyncEngine.shared.flushPendingChanges()
                    }
                }
            }

        case .active:
            // Explicitly fetch CloudKit changes to catch missed push notifications
            if #available(macOS 14.0, iOS 17.0, *) {
                Task {
                    await CloudKitSyncEngine.shared.fetchChanges()
                }
            }

            // Re-sync Reminders in case user made changes while backgrounded
            if ReminderSyncEngine.shared.isAuthorized {
                Task {
                    await ReminderSyncEngine.shared.syncExternalChanges()
                }
            }

        case .inactive:
            break

        @unknown default:
            break
        }
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
        Group {
            #if os(iOS)
            OutlineView(
                document: document,
                zoomedNodeId: zoomBinding,
                windowId: windowId,
                fontSize: $fontSize,
                isFocusMode: $isFocusMode,
                isSearching: $isSearching,
                collapsedNodeIds: $collapsedNodeIds,
                navigationHistory: navigationHistory
            )
            #else
            OutlineView(
                document: document,
                zoomedNodeId: zoomBinding,
                windowId: windowId,
                fontSize: $fontSize,
                isFocusMode: $isFocusMode,
                isSearching: $isSearching,
                collapsedNodeIds: $collapsedNodeIds,
                navigationHistory: navigationHistory
            )
            #endif
        }
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
                // Minimum window size (similar to Apple Notes)
                window.minSize = NSSize(width: 480, height: 400)
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
