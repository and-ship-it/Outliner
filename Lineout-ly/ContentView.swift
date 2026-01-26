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

    /// ID of the auto-created zoom node (for cleanup on close if unused)
    @State private var autoCreatedZoomNodeId: UUID? = nil

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
                // Focus the zoomed node itself (it appears at the top when zoomed)
                if let doc = WindowManager.shared.document {
                    doc.focusedNodeId = pending
                    doc.focusVersion += 1
                }
                WindowManager.shared.pendingZoom = nil
            }
            // Default: Auto-zoom into fresh bullet (new window/tab without special context)
            else if let doc = WindowManager.shared.document {
                // Check if zoom was already set by onChange handler (optimistic UI)
                if !zoomedNodeIdString.isEmpty {
                    // autoCreatedZoomNodeId was already set by onChange handler
                    print("[Launch] Zoom already set by onChange handler, skipping auto-zoom setup")
                    collapseStateInitialized = true  // Ensure it's set
                }
                // Check if there's an auto-zoom node from initial load (first window)
                else if let existingAutoZoom = WindowManager.shared.consumeAutoZoomNodeId() {
                    setZoomedNodeId(existingAutoZoom)
                    autoCreatedZoomNodeId = existingAutoZoom  // Track for cleanup
                    collapseStateInitialized = true
                    print("[Launch] Using existing auto-zoom node (\(existingAutoZoom.uuidString.prefix(8))) for first window")
                } else {
                    // Create new bullet with date/time name at the end and zoom into it
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "EEE, d HH:mm"  // e.g., "Tue, 27 15:30"
                    let dateTitle = dateFormatter.string(from: Date())
                    let newNode = OutlineNode(title: dateTitle)
                    doc.root.addChild(newNode)  // Appends at end
                    setZoomedNodeId(newNode.id)
                    autoCreatedZoomNodeId = newNode.id  // Track for cleanup
                    // Don't set focusedNodeId to zoomed node - focus will go to first child
                    collapseStateInitialized = true  // Start fresh
                    print("[Launch] Auto-zoom: created new node '\(dateTitle)' (\(newNode.id.uuidString.prefix(8))) for new window")
                    iCloudManager.shared.scheduleAutoSave(for: doc)
                }
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
            // Clean up empty auto-created content before closing
            cleanupEmptyZoomContent()

            // Release all locks when window closes
            WindowManager.shared.releaseAllLocks(for: windowId)
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
        .onChange(of: WindowManager.shared.isLoading) { _, isLoading in
            // React immediately when placeholder becomes ready (optimistic UI)
            if !isLoading,
               zoomedNodeIdString.isEmpty,  // Don't override existing zoom
               let autoZoom = WindowManager.shared.consumeAutoZoomNodeId() {
                setZoomedNodeId(autoZoom)
                autoCreatedZoomNodeId = autoZoom
                collapseStateInitialized = true
                print("[Launch] Immediate auto-zoom to placeholder node (\(autoZoom.uuidString.prefix(8)))")
            }
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
            #endif
        }
        #if os(macOS)
        .background(WindowAccessor(windowId: windowId, title: tabTitle, isAlwaysOnTop: isAlwaysOnTop))
        #endif
    }

    // MARK: - Scene Phase Handling (iCloud Sync)

    /// Handle app going to background or coming to foreground
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Save immediately before going to background
            // This ensures our changes are in iCloud before another device might edit
            if let document = WindowManager.shared.document {
                print("[Sync] App going to background - forcing save")
                Task {
                    await iCloudManager.shared.forceSave(document)
                }
            }

        case .active:
            // Coming back to foreground - check if file changed on another device
            guard oldPhase != .active else { return }  // Only on actual foreground transition

            Task {
                // Small delay to let iCloud sync complete
                try? await Task.sleep(for: .milliseconds(500))

                if iCloudManager.shared.hasFileChangedExternally() {
                    print("[Sync] 🔄 File changed externally - reloading document")
                    await reloadDocumentFromCloud()
                } else {
                    print("[Sync] File unchanged - no reload needed")
                }
            }

        case .inactive:
            // Transitional state - no action needed
            break

        @unknown default:
            break
        }
    }

    /// Reload document from iCloud, preserving current zoom state
    private func reloadDocumentFromCloud() async {
        guard let oldDoc = WindowManager.shared.document else { return }

        // Remember current state
        let currentZoom = zoomedNodeId
        let currentFocus = oldDoc.focusedNodeId

        // Reload
        await WindowManager.shared.reloadDocument()

        // Try to restore state if the nodes still exist
        if let doc = WindowManager.shared.document {
            if let zoomId = currentZoom, doc.root.find(id: zoomId) != nil {
                setZoomedNodeId(zoomId)
            }
            if let focusId = currentFocus, doc.root.find(id: focusId) != nil {
                doc.focusedNodeId = focusId
                doc.focusVersion += 1
            }
            print("[Sync] Document reloaded, nodes: \(doc.root.children.count)")
        }
    }

    // MARK: - Cleanup

    /// Clean up empty auto-created bullets when tab closes without user adding content
    private func cleanupEmptyZoomContent() {
        guard let doc = WindowManager.shared.document else { return }
        guard let zoomId = zoomedNodeId,
              let zoomedNode = doc.root.find(id: zoomId) else { return }

        // Check if zoomed node only has empty children (no title, no children of their own)
        let hasNonEmptyContent = zoomedNode.children.contains { child in
            !child.title.isEmpty || child.hasChildren
        }

        if !hasNonEmptyContent && !zoomedNode.children.isEmpty {
            // All children are empty - delete them
            let childCount = zoomedNode.children.count
            for child in zoomedNode.children.reversed() {  // Reversed to avoid index issues
                child.removeFromParent()
            }
            print("[Cleanup] Removed \(childCount) empty auto-created children")

            // If zoom node was auto-created by this tab and is now empty, delete it too
            if autoCreatedZoomNodeId == zoomId && zoomedNode.children.isEmpty {
                zoomedNode.removeFromParent()
                print("[Cleanup] Removed auto-created zoom node '\(zoomedNode.title)'")
            }

            // Trigger save
            doc.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: doc)
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
