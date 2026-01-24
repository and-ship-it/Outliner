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

    /// Zoomed node ID for this window (persisted per scene/window)
    @SceneStorage("zoomedNodeId") private var zoomedNodeIdString: String = ""

    /// Font size for this window (persisted per scene/window)
    @SceneStorage("fontSize") private var fontSize: Double = 13.0

    /// Focus mode - dims everything except the focused bullet
    @State private var isFocusMode: Bool = false

    /// Search mode - shows search bar
    @State private var isSearching: Bool = false

    /// Computed zoom ID
    private var zoomedNodeId: UUID? {
        get { UUID(uuidString: zoomedNodeIdString) }
    }

    private func setZoomedNodeId(_ id: UUID?) {
        zoomedNodeIdString = id?.uuidString ?? ""
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

            // Check for pending zoom (from Cmd+T)
            if let pending = WindowManager.shared.pendingZoom {
                setZoomedNodeId(pending)
                WindowManager.shared.pendingZoom = nil
            }
        }
        .onDisappear {
            // Release all locks when window closes
            WindowManager.shared.releaseAllLocks(for: windowId)
        }
        .onChange(of: zoomedNodeIdString) { _, newValue in
            // Track zoom changes for session save
            WindowManager.shared.registerTabZoom(windowId: windowId, zoomedNodeId: UUID(uuidString: newValue))
        }
        .onAppear {
            // Register this tab with WindowManager
            WindowManager.shared.registerTab(windowId: windowId)
        }
        #if os(macOS)
        .background(WindowAccessor(windowId: windowId))
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
            isSearching: $isSearching
        )
        .focusedSceneValue(\.document, document)
        .focusedSceneValue(\.fontSize, $fontSize)
        .focusedSceneValue(\.isFocusMode, $isFocusMode)
        .focusedSceneValue(\.isSearching, $isSearching)
    }
}

// MARK: - Window Accessor (for native tab support)

#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    let windowId: UUID

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // Enable automatic tabbing
                window.tabbingMode = .automatic
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#Preview {
    ContentView()
}
