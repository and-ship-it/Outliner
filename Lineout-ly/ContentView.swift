//
//  ContentView.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

/// Root view that manages document loading and tab state
struct ContentView: View {
    @State private var document: OutlineDocument?
    @State private var tabs: [TabState] = []
    @State private var selectedTabId: UUID?
    @State private var isLoading = true
    @State private var loadError: Error?

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if let document = document {
                documentView(document)
            }
        }
        .task {
            await loadDocument()
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
                    await loadDocument()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func documentView(_ document: OutlineDocument) -> some View {
        if tabs.count <= 1 {
            // Single tab - no tab bar needed
            OutlineView(document: document)
                .focusedValue(\.document, document)
        } else {
            // Multiple tabs
            TabView(selection: $selectedTabId) {
                ForEach(tabs) { tab in
                    tabContent(for: tab, document: document)
                        .tabItem {
                            Label(tab.title, systemImage: tab.zoomedNodeId == nil ? "list.bullet" : "arrow.right.circle")
                        }
                        .tag(tab.id)
                }
            }
            .focusedValue(\.document, document)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TabState, document: OutlineDocument) -> some View {
        // If tab has a zoom override, create a view that overrides the document's zoom
        if let zoomedId = tab.zoomedNodeId {
            OutlineView(document: document)
                .onAppear {
                    // Set zoom when tab becomes active
                    if selectedTabId == tab.id {
                        document.zoomedNodeId = zoomedId
                    }
                }
                .onChange(of: selectedTabId) { _, newId in
                    if newId == tab.id {
                        document.zoomedNodeId = zoomedId
                    }
                }
        } else {
            OutlineView(document: document)
                .onAppear {
                    if selectedTabId == tab.id {
                        document.zoomedNodeId = nil
                    }
                }
                .onChange(of: selectedTabId) { _, newId in
                    if newId == tab.id {
                        document.zoomedNodeId = nil
                    }
                }
        }
    }

    // MARK: - Document Loading

    private func loadDocument() async {
        isLoading = true
        loadError = nil

        do {
            let icloud = iCloudManager.shared

            // Wait briefly for iCloud to initialize
            try await Task.sleep(for: .milliseconds(500))

            if icloud.isICloudAvailable {
                // Load from iCloud
                let doc = try await icloud.loadDocument()
                doc.autoSaveEnabled = true
                self.document = doc
            } else {
                // Fallback to local storage
                let doc = try icloud.loadLocalDocument()
                doc.autoSaveEnabled = true
                self.document = doc
            }

            // Initialize with main tab
            let mainTab = TabState(title: "Main", zoomedNodeId: nil)
            tabs = [mainTab]
            selectedTabId = mainTab.id

        } catch {
            loadError = error
        }

        isLoading = false
    }

    // MARK: - Tab Management

    func createNewTab(withZoom zoomedNodeId: UUID? = nil, title: String = "New Tab") {
        let newTab = TabState(title: title, zoomedNodeId: zoomedNodeId)
        tabs.append(newTab)
        selectedTabId = newTab.id
    }

    func closeCurrentTab() {
        guard tabs.count > 1, let currentId = selectedTabId else { return }

        if let index = tabs.firstIndex(where: { $0.id == currentId }) {
            tabs.remove(at: index)
            // Select adjacent tab
            if index < tabs.count {
                selectedTabId = tabs[index].id
            } else if index > 0 {
                selectedTabId = tabs[index - 1].id
            }
        }
    }
}

// MARK: - Tab State

struct TabState: Identifiable {
    let id = UUID()
    var title: String
    var zoomedNodeId: UUID?
}

// MARK: - Environment Key for Tab Management

struct TabManagerKey: EnvironmentKey {
    static let defaultValue: ContentView? = nil
}

extension EnvironmentValues {
    var tabManager: ContentView? {
        get { self[TabManagerKey.self] }
        set { self[TabManagerKey.self] = newValue }
    }
}

#Preview {
    ContentView()
}
