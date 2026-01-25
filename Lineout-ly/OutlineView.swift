//
//  OutlineView.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

/// The main outline view displaying the entire document
struct OutlineView: View {
    @Bindable var document: OutlineDocument
    @Binding var zoomedNodeId: UUID?
    let windowId: UUID
    @Binding var fontSize: Double
    @Binding var isFocusMode: Bool  // Whether focus mode is enabled (dims non-focused bullets)
    @Binding var isSearching: Bool  // Whether search bar is visible
    @Binding var collapsedNodeIds: Set<UUID>  // Per-tab collapse state

    @State private var hasSetInitialFocus = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [OutlineNode] = []
    @State private var selectedResultIndex: Int = 0
    @FocusState private var isSearchFieldFocused: Bool

    // Scale factor based on font size (base is 13.0)
    private var scale: CGFloat { CGFloat(fontSize) / 13.0 }

    /// The zoomed node based on zoomedNodeId
    private var zoomedNode: OutlineNode? {
        guard let id = zoomedNodeId else { return nil }
        return document.root.find(id: id)
    }

    /// Breadcrumbs path to the zoomed node
    private var breadcrumbs: [OutlineNode] {
        guard let zoomed = zoomedNode else { return [] }
        var path: [OutlineNode] = []
        var current = zoomed.parent
        while let node = current, !node.isRoot {
            path.insert(node, at: 0)
            current = node.parent
        }
        return path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar (when searching)
            if isSearching {
                searchBar
            }

            // Outline content - starts directly with bullets, no header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        let nodes = nodesWithDepth
                        let isOnlyOne = nodes.count == 1
                        ForEach(Array(nodes.enumerated()), id: \.element.node.id) { index, item in
                            NodeRow(
                                document: document,
                                node: item.node,
                                effectiveDepth: item.depth,
                                treeLines: item.treeLines,
                                hasNextNode: index < nodes.count - 1,
                                isOnlyNode: isOnlyOne,
                                windowId: windowId,
                                zoomedNodeId: $zoomedNodeId,
                                fontSize: $fontSize,
                                isFocusMode: $isFocusMode,
                                isSearching: $isSearching,
                                collapsedNodeIds: $collapsedNodeIds,
                                searchQuery: searchQuery
                            )
                            .id(item.node.id)
                        }
                    }
                    // Fixed window-level padding (Apple HIG premium spacing)
                    .padding(.top, isSearching ? 16 : 40)
                    .padding(.bottom, zoomedNodeId != nil ? 16 : 48)
                }
                .onChange(of: document.focusedNodeId) { _, newId in
                    if let id = newId {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    // Scroll to existing focused node (e.g., from session restore)
                    if let id = document.focusedNodeId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }

            // Breadcrumbs at bottom (when zoomed)
            if zoomedNodeId != nil {
                bottomBreadcrumbs
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.textBackgroundColor)
        .focusedValue(\.document, document)
        .onAppear {
            // Set focus to first visible node when view appears
            setFocusToFirstNode()
        }
        .onChange(of: zoomedNodeId) { _, _ in
            // When zoom changes, focus first visible node
            setFocusToFirstNode()
        }
    }

    /// Focus on the first visible node (or keep existing focus if already set)
    private func setFocusToFirstNode() {
        // If focus is already set (e.g., from session restore), don't override it
        if document.focusedNodeId != nil {
            hasSetInitialFocus = true
            return
        }

        let nodes = nodesWithDepth
        if let firstNode = nodes.first {
            // Use a small delay to ensure the view hierarchy is fully established
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                document.focusedNodeId = firstNode.node.id
            }
        }
        hasSetInitialFocus = true
    }

    // MARK: - Computed

    /// Visible nodes with their effective depth and tree lines (accounting for zoom)
    /// When zoomed, includes the zoomed node itself as the first item at depth 0
    /// Note: We reference structureVersion to ensure SwiftUI observes structural changes
    /// Uses per-tab collapsedNodeIds for visibility calculation
    private var nodesWithDepth: [(node: OutlineNode, depth: Int, treeLines: [Bool])] {
        _ = document.structureVersion // Force observation of structural changes

        var result: [(node: OutlineNode, depth: Int, treeLines: [Bool])] = []

        // If zoomed, include the zoomed node itself as the first item
        if let zoomed = zoomedNode {
            result.append((node: zoomed, depth: 0, treeLines: []))

            // Only show children if the zoomed node is not collapsed
            if !collapsedNodeIds.contains(zoomed.id) {
                // Then add its visible children with depth starting at 1
                let children = flattenedVisible(from: zoomed)
                for child in children {
                    let effectiveDepth = child.depth - zoomed.depth
                    let treeLines = calculateTreeLines(for: child, zoomDepth: zoomed.depth)
                    result.append((node: child, depth: effectiveDepth, treeLines: treeLines))
                }
            }
        } else {
            // Not zoomed - show all visible nodes from root
            let zoomDepth = 0
            let visibleNodes = flattenedVisible(from: document.root)
            for node in visibleNodes {
                let effectiveDepth = max(0, node.depth - zoomDepth)
                let treeLines = calculateTreeLines(for: node, zoomDepth: zoomDepth)
                result.append((node: node, depth: effectiveDepth, treeLines: treeLines))
            }
        }

        return result
    }

    /// Get flattened visible nodes using per-tab collapse state
    private func flattenedVisible(from node: OutlineNode) -> [OutlineNode] {
        var result: [OutlineNode] = []
        for child in node.children {
            result.append(child)
            if !collapsedNodeIds.contains(child.id) {
                result.append(contentsOf: flattenedVisible(from: child))
            }
        }
        return result
    }

    // MARK: - Subviews

    /// Search bar shown at the top when searching
    private var searchBar: some View {
        HStack(spacing: 8 * scale) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12 * scale))
                .foregroundStyle(.secondary)

            // Search text field
            TextField("Search...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    // Navigate to next result on Enter
                    if !searchResults.isEmpty {
                        let index = selectedResultIndex % searchResults.count
                        navigateToSearchResult(searchResults[index])
                        selectedResultIndex += 1
                    }
                }
                .onChange(of: searchQuery) { _, newValue in
                    searchResults = document.search(query: newValue)
                    selectedResultIndex = 0
                    // Don't auto-navigate - wait for Enter or navigation button
                }
                .onAppear {
                    // Focus the search field when it appears
                    isSearchFieldFocused = true
                }

            // Results count
            if !searchQuery.isEmpty {
                Text("\(searchResults.count) found")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
            }

            // Navigation buttons
            if searchResults.count > 1 {
                Button(action: navigateToPreviousResult) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11 * scale))
                }
                .buttonStyle(.plain)

                Button(action: navigateToNextResult) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11 * scale))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Close button
            Button(action: closeSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 32)  // Fixed padding to match content
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color.textBackgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
    }

    private func navigateToNextResult() {
        guard !searchResults.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + 1) % searchResults.count
        navigateToSearchResult(searchResults[selectedResultIndex])
    }

    private func navigateToPreviousResult() {
        guard !searchResults.isEmpty else { return }
        selectedResultIndex = selectedResultIndex > 0 ? selectedResultIndex - 1 : searchResults.count - 1
        navigateToSearchResult(searchResults[selectedResultIndex])
    }

    /// Navigate to a search result - expands ancestors in per-tab collapse state
    private func navigateToSearchResult(_ node: OutlineNode) {
        // Expand all ancestors in per-tab collapse state to make the node visible
        var current = node.parent
        while let parent = current {
            collapsedNodeIds.remove(parent.id)
            current = parent.parent
        }
        // Focus the node
        document.focusedNodeId = node.id
    }

    private func closeSearch() {
        isSearching = false
        searchQuery = ""
        searchResults = []
        selectedResultIndex = 0
    }

    /// Breadcrumbs shown at the bottom when zoomed
    private var bottomBreadcrumbs: some View {
        HStack(spacing: 4 * scale) {
            // Home button
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    zoomedNodeId = nil
                }
            }) {
                Image(systemName: "house")
                    .font(.system(size: 11 * scale))
            }
            .buttonStyle(.plain)

            // Breadcrumb path
            ForEach(breadcrumbs) { node in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9 * scale))

                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomedNodeId = node.id
                    }
                }) {
                    Text(node.title.isEmpty ? "Untitled" : String(node.title.prefix(15)))
                        .font(.system(size: 11 * scale))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            // Current zoomed node
            if let zoomed = zoomedNode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9 * scale))
                Text(zoomed.title.isEmpty ? "Untitled" : String(zoomed.title.prefix(15)))
                    .font(.system(size: 11 * scale, weight: .medium))
                    .lineLimit(1)
            }

            Spacer()
        }
        .foregroundStyle(.secondary.opacity(0.7))
        .padding(.horizontal, 32)  // Fixed padding to match content
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.textBackgroundColor)
    }

    /// Calculate which depth levels should show vertical tree lines
    /// A line appears at a level if the ancestor at that level has more siblings below it
    private func calculateTreeLines(for node: OutlineNode, zoomDepth: Int) -> [Bool] {
        var lines: [Bool] = []
        var current = node

        // Walk up the ancestor chain (excluding the node itself)
        while let parent = current.parent {
            // Don't go above the zoom level
            if parent.id == zoomedNodeId || parent.isRoot {
                break
            }

            // Check if 'current' has siblings after it
            let hasSiblingsBelow = current.nextSibling != nil
            lines.insert(hasSiblingsBelow, at: 0)

            current = parent
        }

        return lines
    }

    // MARK: - Zoom Operations

    /// Zoom into the focused node
    func zoomIn() {
        guard let focused = document.focusedNode, focused.hasChildren else { return }
        zoomedNodeId = focused.id
    }

    /// Zoom out one level
    func zoomOut() {
        guard let zoomed = zoomedNode else { return }
        if let parent = zoomed.parent, !parent.isRoot {
            zoomedNodeId = parent.id
        } else {
            zoomedNodeId = nil
        }
    }

    /// Zoom to root (reset zoom)
    func zoomToRoot() {
        zoomedNodeId = nil
    }
}

// MARK: - macOS Background Color Extension

#if os(macOS)
extension Color {
    static let textBackgroundColor = Color(NSColor.textBackgroundColor)
}
#else
extension Color {
    static let textBackgroundColor = Color(UIColor.systemBackground)
}
#endif

#Preview {
    @Previewable @State var document = OutlineDocument.createSample()
    @Previewable @State var zoomedNodeId: UUID? = nil
    @Previewable @State var fontSize: Double = 13.0
    @Previewable @State var isFocusMode: Bool = false
    @Previewable @State var isSearching: Bool = false
    @Previewable @State var collapsedNodeIds: Set<UUID> = []

    OutlineView(document: document, zoomedNodeId: $zoomedNodeId, windowId: UUID(), fontSize: $fontSize, isFocusMode: $isFocusMode, isSearching: $isSearching, collapsedNodeIds: $collapsedNodeIds)
        .frame(width: 500, height: 700)
}
