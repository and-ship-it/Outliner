//
//  OutlineView.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The main outline view displaying the entire document
struct OutlineView: View {
    @Bindable var document: OutlineDocument
    @Binding var zoomedNodeId: UUID?
    let windowId: UUID
    @Binding var fontSize: Double
    @Binding var isFocusMode: Bool  // Whether focus mode is enabled (dims non-focused bullets)
    @Binding var isSearching: Bool  // Whether search bar is visible
    @Binding var collapsedNodeIds: Set<UUID>  // Per-tab collapse state

    /// Navigation history for tab switcher (iOS and macOS)
    var navigationHistory: NavigationHistoryManager

    @State private var hasSetInitialFocus = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [OutlineNode] = []
    @State private var selectedResultIndex: Int = 0
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    // Tab switcher state (both platforms)
    @State private var isCarouselVisible: Bool = false

    // Old week overlay state
    @State private var oldWeekDocument: OutlineDocument? = nil
    @State private var oldWeekFileName: String? = nil
    @State private var isLoadingOldWeek: Bool = false
    @State private var isTrashVisible: Bool = false

    // iOS edit mode for multi-selection and drag-drop
    #if os(iOS)
    @State private var isEditMode: Bool = false
    @State private var draggedNodeId: UUID? = nil
    @State private var showingSettings: Bool = false
    @State private var nodeFrames: [UUID: CGRect] = [:]  // Track node positions for two-finger selection
    @State private var isDraggingSelection: Bool = false  // Whether user is dragging selected items
    @State private var dropTargetNodeId: UUID? = nil  // Current drop target during drag
    @State private var dragLocation: CGPoint = .zero  // Current drag position for floating preview
    @State private var showDragPreview: Bool = false  // Whether to show the floating card stack
    #endif

    // Scale factor based on font size (base is 13.0)
    private var scale: CGFloat { CGFloat(fontSize) / 13.0 }

    /// Whether we're viewing an old (previous) week document
    private var isOldWeekMode: Bool { oldWeekDocument != nil }

    /// The document to display — old week overlay or current document
    private var effectiveDocument: OutlineDocument { oldWeekDocument ?? document }

    /// The zoomed node based on zoomedNodeId
    private var zoomedNode: OutlineNode? {
        guard let id = zoomedNodeId else { return nil }
        return effectiveDocument.root.find(id: id)
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
            // iOS edit mode bar (when selecting items)
            #if os(iOS)
            if isEditMode {
                editModeBar
            }
            #endif

            // Search bar (when searching)
            if isSearching {
                searchBar
            }

            // Old week read-only banner
            if isOldWeekMode {
                oldWeekBanner
            }

            // Outline content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // Show children nodes (or all nodes if not zoomed)
                        // Zoomed node title shown in window title bar, not here
                        let nodes = nodesWithDepth
                        let isOnlyOne = nodes.count == 1 && zoomedNode == nil
                        ForEach(Array(nodes.enumerated()), id: \.element.node.id) { index, item in
                            #if os(iOS)
                            NodeRow(
                                document: effectiveDocument,
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
                                searchQuery: searchQuery,
                                isReadOnly: isOldWeekMode,
                                isEditMode: $isEditMode,
                                draggedNodeId: $draggedNodeId,
                                isDraggingSelection: $isDraggingSelection,
                                dropTargetNodeId: $dropTargetNodeId
                            )
                            .id(item.node.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: NodeFramePreferenceKey.self,
                                        value: [item.node.id: geo.frame(in: .global)]
                                    )
                                }
                            )
                            #else
                            NodeRow(
                                document: effectiveDocument,
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
                                searchQuery: searchQuery,
                                isReadOnly: isOldWeekMode
                            )
                            .id(item.node.id)
                            #endif
                        }
                    }
                    // Fixed window-level padding (Apple HIG premium spacing)
                    .padding(.top, isSearching ? 16 : 40)
                    #if os(iOS)
                    .padding(.bottom, 80)  // Clear the floating bottom nav bar
                    #else
                    .padding(.bottom, zoomedNodeId != nil ? 16 : 48)
                    #endif
                }
                .onChange(of: document.focusedNodeId) { _, newId in
                    if let id = newId {
                        withAnimation {
                            proxy.scrollTo(id)
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
                #if os(iOS)
                .onPreferenceChange(NodeFramePreferenceKey.self) { frames in
                    nodeFrames = frames
                }
                #endif
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme))
        .focusedValue(\.document, document)
        #if os(iOS)
        .overlay(iOSGestureOverlays)
        .overlay(iOSSettingsButton)
        .overlay(iOSBottomActionBar)
        .overlay(iOSBottomNavBar)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(fontSize: $fontSize, isFocusMode: $isFocusMode)
        }
        .fullScreenCover(isPresented: $isCarouselVisible) {
            MasonryTabOverview(
                isVisible: $isCarouselVisible,
                navigationHistory: navigationHistory,
                document: document,
                collapsedNodeIds: collapsedNodeIds,
                onSelectCard: { index in
                    navigationHistory.navigateTo(index: index)
                    zoomedNodeId = navigationHistory.currentZoomId
                },
                onRemoveCard: { index in
                    zoomedNodeId = navigationHistory.currentZoomId
                },
                onCreateCard: {
                    createNewZoomLevel()
                },
                onOpenOldWeek: { weekFileName in
                    isCarouselVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openOldWeek(weekFileName)
                    }
                },
                onOpenTrash: {
                    isCarouselVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isTrashVisible = true
                    }
                },
                fontSize: $fontSize,
                isFocusMode: $isFocusMode
            )
            .background(ClearBackgroundView())
        }
        .sheet(isPresented: $isTrashVisible) {
            TrashView(isVisible: $isTrashVisible)
        }
        #else
        // macOS tab switcher
        .overlay(macOSBottomNavBar)
        .sheet(isPresented: $isCarouselVisible) {
            MasonryTabOverview(
                isVisible: $isCarouselVisible,
                navigationHistory: navigationHistory,
                document: document,
                collapsedNodeIds: collapsedNodeIds,
                onSelectCard: { index in
                    navigationHistory.navigateTo(index: index)
                    zoomedNodeId = navigationHistory.currentZoomId
                },
                onRemoveCard: { index in
                    zoomedNodeId = navigationHistory.currentZoomId
                },
                onCreateCard: {
                    macOSCreateNewZoomLevel()
                },
                onOpenOldWeek: { weekFileName in
                    isCarouselVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openOldWeek(weekFileName)
                    }
                },
                onOpenTrash: {
                    isCarouselVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isTrashVisible = true
                    }
                },
                fontSize: $fontSize,
                isFocusMode: $isFocusMode
            )
            .frame(width: 500, height: 600)
        }
        .sheet(isPresented: $isTrashVisible) {
            TrashView(isVisible: $isTrashVisible)
        }
        #endif
        .onAppear {
            // Set focus to first visible node when view appears
            setFocusToFirstNode()
        }
        .onChange(of: zoomedNodeId) { _, newValue in
            // Auto-close old week when zooming out to root
            if isOldWeekMode && newValue == nil {
                closeOldWeek()
                return
            }
            // Sync zoom with navigation history (navigates to existing tab or creates new)
            if !isOldWeekMode {
                navigationHistory.navigateOrPush(newValue)
            }
            // When zoom changes, ensure we have a valid focus in the new view
            ensureFocusInZoomedView()
        }
    }

    /// Focus on the first visible node (or create empty child if zoomed with no children)
    private func setFocusToFirstNode() {
        // If focus is already set (e.g., from session restore), don't override it
        if document.focusedNodeId != nil {
            hasSetInitialFocus = true
            return
        }

        ensureFocusInZoomedView()
        hasSetInitialFocus = true
    }

    /// Ensure there's a valid focused node in the current zoomed view
    /// Creates an empty child if zoomed into a node with no children
    private func ensureFocusInZoomedView() {
        let doc = effectiveDocument

        // If zoomed and no children, create an empty child (only in normal mode)
        if let zoomed = zoomedNode, zoomed.children.isEmpty {
            if isOldWeekMode {
                // Read-only: just focus the zoomed node itself
                doc.focusedNodeId = zoomed.id
                doc.focusVersion += 1
                return
            }
            // Use createChild which handles structure change properly
            doc.focusedNodeId = zoomed.id
            if let emptyChild = doc.createChild() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    doc.focusedNodeId = emptyChild.id
                    doc.focusVersion += 1
                }
            }
            return
        }

        // Focus the first visible node
        let nodes = nodesWithDepth
        if let firstNode = nodes.first {
            // Use a small delay to ensure the view hierarchy is fully established
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                doc.focusedNodeId = firstNode.node.id
                doc.focusVersion += 1
            }
        }
    }

    // MARK: - Computed

    /// Visible nodes with their effective depth and tree lines (accounting for zoom)
    /// When zoomed, shows the zoomed node at depth 0, then its children at depth 1+
    /// Note: We reference structureVersion to ensure SwiftUI observes structural changes
    /// Uses per-tab collapsedNodeIds for visibility calculation
    private var nodesWithDepth: [(node: OutlineNode, depth: Int, treeLines: [Bool])] {
        _ = effectiveDocument.structureVersion // Force observation of structural changes

        var result: [(node: OutlineNode, depth: Int, treeLines: [Bool])] = []

        if let zoomed = zoomedNode {
            // Zoomed: show the zoomed node itself at depth 0 (as editable header)
            result.append((node: zoomed, depth: 0, treeLines: []))

            // Then show children at depth 1+
            // Only show children if zoomed node is not collapsed
            if !collapsedNodeIds.contains(zoomed.id) {
                let children = flattenedVisible(from: zoomed)
                for child in children {
                    // Depth is relative to zoomed node (so direct children are depth 1)
                    let effectiveDepth = child.depth - zoomed.depth
                    let treeLines = calculateTreeLines(for: child, zoomDepth: zoomed.depth)
                    result.append((node: child, depth: effectiveDepth, treeLines: treeLines))
                }
            }
        } else {
            // Not zoomed - show all visible nodes from root
            let zoomDepth = 0
            let visibleNodes = flattenedVisible(from: effectiveDocument.root)
            for node in visibleNodes {
                let effectiveDepth = max(0, node.depth - zoomDepth)
                var treeLines = calculateTreeLines(for: node, zoomDepth: zoomDepth)
                // Root is invisible (no bullet shown) - hide tree line at column 0
                if !treeLines.isEmpty {
                    treeLines[0] = false
                }
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
                    searchResults = effectiveDocument.search(query: newValue)
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
        .background(AppTheme.background(for: colorScheme))
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
        effectiveDocument.focusedNodeId = node.id
    }

    private func closeSearch() {
        isSearching = false
        searchQuery = ""
        searchResults = []
        selectedResultIndex = 0
    }

    // MARK: - iOS Edit Mode

    #if os(iOS)
    /// Edit mode toolbar shown at top when in edit mode
    private var editModeBar: some View {
        HStack {
            // Selection count
            Text("\(document.selectedNodeIds.count) selected")
                .font(.system(size: 14 * scale, weight: .medium))

            Spacer()

            // Done button
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                withAnimation(.easeOut(duration: 0.2)) {
                    document.clearSelection()
                    isEditMode = false
                }
            }) {
                Text("Done")
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundColor(AppTheme.amber)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(AppTheme.background(for: colorScheme))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
    }

    /// Bottom action toolbar shown when items are selected (iOS Reminders style)
    private var bottomSelectionBar: some View {
        VStack(spacing: 0) {
            // Selection count - clean text above toolbar
            Text("\(document.selectedNodeIds.count) Selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            // Toolbar with evenly spaced buttons (iOS Reminders style)
            HStack(spacing: 0) {
                // Done button (exit selection)
                remindersToolbarButton(
                    icon: "checkmark.circle",
                    label: "Done"
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        document.clearSelection()
                        isEditMode = false
                    }
                }

                Spacer()

                // Indent button
                remindersToolbarButton(
                    icon: "increase.indent",
                    label: "Indent"
                ) {
                    document.indentSelected()
                }

                Spacer()

                // Outdent button
                remindersToolbarButton(
                    icon: "decrease.indent",
                    label: "Outdent"
                ) {
                    document.outdentSelected()
                }

                Spacer()

                // Delete button (red)
                remindersToolbarButton(
                    icon: "trash",
                    label: "Delete",
                    isDestructive: true
                ) {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                    withAnimation(.spring(response: 0.3)) {
                        document.deleteSelected()
                        isEditMode = false
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 0.5),
                alignment: .top
            )
        }
    }

    /// iOS Reminders-style toolbar button
    private func remindersToolbarButton(
        icon: String,
        label: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.25)) {
                action()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isDestructive ? .red : .accentColor)
            .frame(minWidth: 50)
        }
        .buttonStyle(.plain)
    }

    /// Find node ID at a given point using tracked frames
    private func nodeIdAtPoint(_ point: CGPoint) -> UUID? {
        for (nodeId, frame) in nodeFrames {
            if frame.contains(point) {
                return nodeId
            }
        }
        return nil
    }

    /// Two-finger drag and edge swipe gesture overlays
    @ViewBuilder
    private var iOSGestureOverlays: some View {
        // Two-finger drag to select
        TwoFingerDragSelectView(
            isEditMode: $isEditMode,
            showDragPreview: $showDragPreview,
            dragLocation: $dragLocation,
            document: document,
            getNodeIdAtPoint: nodeIdAtPoint
        )

        // Edge swipe from left to zoom out (only when zoomed)
        if zoomedNodeId != nil {
            EdgeSwipeView {
                handleEdgeSwipeZoomOut()
            }
        }

        // Floating card stack preview while dragging (iOS Reminders style)
        if showDragPreview && !document.selectedNodeIds.isEmpty {
            FloatingCardStackView(
                selectedCount: document.selectedNodeIds.count,
                selectedTitles: getSelectedTitles(),
                position: dragLocation
            )
        }
    }

    /// Get titles of selected nodes for preview
    private func getSelectedTitles() -> [String] {
        document.selectedNodeIds.compactMap { id in
            document.root.find(id: id)?.title
        }.prefix(3).map { String($0) }
    }

    /// Handle zoom out from edge swipe
    private func handleEdgeSwipeZoomOut() {
        handleZoomOut()
    }

    /// Settings button overlay - now empty, settings moved to carousel
    private var iOSSettingsButton: some View {
        EmptyView()
    }

    /// Bottom action bar overlay
    private var iOSBottomActionBar: some View {
        VStack {
            Spacer()
            if isEditMode && !document.selectedNodeIds.isEmpty {
                bottomSelectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: document.selectedNodeIds.isEmpty)
    }

    // Consistent icon size for bottom bar
    private let bottomBarIconSize: CGFloat = 20
    private let bottomBarButtonSize: CGFloat = 44

    /// Liquid glass background for bottom bar buttons
    private func liquidGlassBackground(isCircle: Bool = false) -> some View {
        Group {
            if isCircle {
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            }
        }
    }

    /// Bottom navigation bar with carousel button (Arc-style)
    private var iOSBottomNavBar: some View {
        VStack {
            Spacer()

            // Only show when not in edit mode and no selection bar visible
            if !isEditMode || document.selectedNodeIds.isEmpty {
                HStack {
                    // Tab overview button (shows card count)
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isCarouselVisible = true
                        }
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: bottomBarIconSize, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: bottomBarButtonSize, height: bottomBarButtonSize)
                            .background(liquidGlassBackground(isCircle: true))
                    }

                    // Home and Back buttons — only when zoomed in
                    if zoomedNodeId != nil {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            goHomeAndCollapseAll()
                        } label: {
                            Image(systemName: "house")
                                .font(.system(size: bottomBarIconSize, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: bottomBarButtonSize, height: bottomBarButtonSize)
                                .background(liquidGlassBackground(isCircle: true))
                        }

                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            handleZoomOut()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: bottomBarIconSize, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: bottomBarButtonSize, height: bottomBarButtonSize)
                                .background(liquidGlassBackground(isCircle: true))
                        }
                    }

                    Spacer()

                    if !isOldWeekMode {
                        // New bullet button
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            createNewZoomLevel()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: bottomBarIconSize, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: bottomBarButtonSize, height: bottomBarButtonSize)
                                .background(liquidGlassBackground(isCircle: true))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEditMode)
    }

    /// Create a new bullet and zoom into it
    /// The session name will be determined by the first 5 words of content
    private func createNewZoomLevel() {
        if let todayNode = DateStructureManager.shared.todayDateNode(in: document) {
            // Create under today's date node and zoom into it
            let newNode = OutlineNode(title: "")
            todayNode.addChild(newNode)
            collapsedNodeIds.remove(todayNode.id)
            navigationHistory.navigateOrPush(todayNode.id)
            zoomedNodeId = todayNode.id
            document.focusedNodeId = newNode.id
            document.focusVersion += 1
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        } else {
            // Fallback: add to root level
            let newNode = OutlineNode(title: "")
            document.root.addChild(newNode)
            navigationHistory.navigateOrPush(newNode.id)
            zoomedNodeId = newNode.id
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        }
    }
    #endif

    // MARK: - Go Home

    /// Go to root and collapse all parent nodes
    private func goHomeAndCollapseAll() {
        // If viewing an old week, close it and return to current week
        if isOldWeekMode {
            closeOldWeek()
            return
        }

        // Delete empty auto-created bullet before going home
        if let zoomedId = zoomedNodeId {
            document.deleteNodeIfEmpty(zoomedId)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            zoomedNodeId = nil
            // Collapse all nodes with children
            var collapsed = Set<UUID>()
            for node in document.root.flattened() {
                if node.hasChildren {
                    collapsed.insert(node.id)
                }
            }
            collapsedNodeIds = collapsed
            // Focus first visible node
            if let firstNode = document.root.children.first {
                document.focusedNodeId = firstNode.id
                document.focusVersion += 1
            }
        }
    }

    // MARK: - Zoom Out (Back)

    /// Handle zoom out action — navigate back in history or up the tree
    private func handleZoomOut() {
        // Old week mode: zoom out to root closes the old week
        if isOldWeekMode {
            if let zoomedId = zoomedNodeId,
               let zoomed = effectiveDocument.root.find(id: zoomedId),
               let parent = zoomed.parent, !parent.isRoot {
                zoomedNodeId = parent.id
            } else {
                // At root of old week — close it
                closeOldWeek()
            }
            return
        }

        // Use navigation history to go back if possible
        if navigationHistory.canGoBack {
            navigationHistory.pop()
            zoomedNodeId = navigationHistory.currentZoomId
            return
        }

        // Fallback: navigate up the tree hierarchy
        if let zoomedId = zoomedNodeId,
           let zoomed = document.root.find(id: zoomedId) {
            if let parent = zoomed.parent, !parent.isRoot {
                zoomedNodeId = parent.id
            } else {
                document.deleteNodeIfEmpty(zoomedId)
                zoomedNodeId = nil
            }
        }
    }

    // MARK: - Old Week Overlay

    /// Open a previous week's document as read-only overlay
    private func openOldWeek(_ weekFileName: String) {
        guard !isLoadingOldWeek else { return }

        // Check if already viewing this week
        if navigationHistory.openOldWeek(weekFileName) && isOldWeekMode && oldWeekFileName == weekFileName {
            return
        }

        isLoadingOldWeek = true
        Task {
            do {
                let doc = try await iCloudManager.shared.loadOldWeekDocument(weekFileName: weekFileName)
                await MainActor.run {
                    oldWeekDocument = doc
                    oldWeekFileName = weekFileName
                    zoomedNodeId = nil
                    isLoadingOldWeek = false
                }
            } catch {
                await MainActor.run {
                    print("[OutlineView] Failed to load old week \(weekFileName): \(error)")
                    navigationHistory.closeOldWeek()
                    isLoadingOldWeek = false
                }
            }
        }
    }

    /// Close the old week overlay and return to current document
    private func closeOldWeek() {
        navigationHistory.closeOldWeek()
        withAnimation(.easeOut(duration: 0.2)) {
            oldWeekDocument = nil
            oldWeekFileName = nil
            zoomedNodeId = nil
        }
    }

    /// Banner shown when viewing a read-only old week
    private var oldWeekBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .medium))

            Text(oldWeekFileName?.replacingOccurrences(of: ".md", with: "") ?? "Previous Week")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text("Read Only")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                )

            Button {
                closeOldWeek()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
    }

    // MARK: - macOS Tab Switcher

    #if os(macOS)
    /// macOS bottom navigation bar with tab switcher button
    private var macOSBottomNavBar: some View {
        VStack {
            Spacer()
            HStack {
                // Tab switcher button (same icon as iOS)
                Button {
                    isCarouselVisible = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.bottom, 12)

                // Home and Back buttons — only when zoomed in
                if zoomedNodeId != nil {
                    Button {
                        goHomeAndCollapseAll()
                    } label: {
                        Image(systemName: "house")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)

                    Button {
                        handleZoomOut()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }

                Spacer()

                if !isOldWeekMode {
                    // Plus button — creates under today's date and zooms in
                    Button {
                        macOSCreateNewZoomLevel()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    /// Create a new bullet and zoom into it (macOS)
    private func macOSCreateNewZoomLevel() {
        if let todayNode = DateStructureManager.shared.todayDateNode(in: document) {
            // Create under today's date node and zoom into it
            let newNode = OutlineNode(title: "")
            todayNode.addChild(newNode)
            collapsedNodeIds.remove(todayNode.id)
            navigationHistory.navigateOrPush(todayNode.id)
            zoomedNodeId = todayNode.id
            document.focusedNodeId = newNode.id
            document.focusVersion += 1
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        } else {
            // Fallback: add to root level
            let newNode = OutlineNode(title: "")
            document.root.addChild(newNode)
            navigationHistory.navigateOrPush(newNode.id)
            zoomedNodeId = newNode.id
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        }
    }
    #endif

    /// Calculate which depth levels should show vertical tree lines
    /// A line appears at a level if the ancestor at that level has more siblings below it
    private func calculateTreeLines(for node: OutlineNode, zoomDepth: Int) -> [Bool] {
        var lines: [Bool] = []
        var current = node

        // Walk up the ancestor chain (excluding the node itself)
        // Always add the entry BEFORE checking if we should stop,
        // so that the array length matches effectiveDepth
        while let parent = current.parent {
            // Check if 'current' has siblings after it
            let hasSiblingsBelow = current.nextSibling != nil
            lines.insert(hasSiblingsBelow, at: 0)

            // Stop after including the root or zoomed node level
            if parent.isRoot || parent.id == zoomedNodeId {
                break
            }

            current = parent
        }

        return lines
    }

    // MARK: - Zoom Operations

    /// Zoom into the focused node (or any specific node)
    /// Creates an empty child if none exist and focuses on the first child
    func zoomIn(to node: OutlineNode? = nil) {
        let target = node ?? document.focusedNode
        guard let target else { return }

        zoomedNodeId = target.id
        // Ensure zoomed node is expanded
        collapsedNodeIds.remove(target.id)

        // Create empty child if none exist, and focus on first child
        if target.children.isEmpty {
            let emptyChild = OutlineNode(title: "")
            target.addChild(emptyChild)
            document.focusedNodeId = emptyChild.id
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        } else {
            // Focus on first child
            document.focusedNodeId = target.children.first?.id
        }
        document.focusVersion += 1
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

// MARK: - Themed Background Color

extension Color {
    /// App background - uses themed paper/midnight colors
    static func themedBackground(for colorScheme: ColorScheme) -> Color {
        AppTheme.background(for: colorScheme)
    }
}

// MARK: - Node Frame Tracking (iOS)

#if os(iOS)
/// Preference key for tracking node row frames
struct NodeFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
#endif

// MARK: - Settings Sheet (iOS)

#if os(iOS)
/// Settings sheet with iCloud-synced options
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var fontSize: Double
    @Binding var isFocusMode: Bool

    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        NavigationStack {
            List {
                // Font Size Section
                Section {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(fontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSize, in: 9...32, step: 1)
                        .tint(.accentColor)
                } header: {
                    Text("Display")
                }

                // Behavior Section
                Section {
                    Toggle("Focus Mode", isOn: $isFocusMode)
                        .tint(.accentColor)

                    Toggle("Word Autocomplete", isOn: Binding(
                        get: { settings.autocompleteEnabled },
                        set: { settings.autocompleteEnabled = $0 }
                    ))
                    .tint(.accentColor)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Focus mode dims non-focused bullets. Autocomplete suggests words as you type.")
                }

                // Week Start Section
                Section {
                    Picker("Week Starts On", selection: Binding(
                        get: { settings.weekStartDay },
                        set: { settings.weekStartDay = $0 }
                    )) {
                        ForEach(WeekStartDay.allCases) { day in
                            Text(day.name).tag(day.rawValue)
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Affects weekly document naming. Changes take effect on next app launch.")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
#endif

// MARK: - Two Finger Drag Selection Gesture (iOS)

#if os(iOS)
/// A UIView that passes through all touches except those handled by its gesture recognizers
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Return nil so touches pass through to views below
        // The gesture recognizers will still receive their specific gestures
        return nil
    }
}

/// A view that detects two-finger drag gestures for multi-selection (like iOS Reminders)
/// When you drag with two fingers, items under the touch are progressively selected
/// Shows a floating card stack preview while dragging
struct TwoFingerDragSelectView: UIViewRepresentable {
    @Binding var isEditMode: Bool
    @Binding var showDragPreview: Bool
    @Binding var dragLocation: CGPoint
    var document: OutlineDocument
    var getNodeIdAtPoint: (CGPoint) -> UUID?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update coordinator with current values
        context.coordinator.isEditMode = $isEditMode
        context.coordinator.showDragPreview = $showDragPreview
        context.coordinator.dragLocation = $dragLocation
        context.coordinator.document = document
        context.coordinator.getNodeIdAtPoint = getNodeIdAtPoint

        // Add gesture to window once available
        DispatchQueue.main.async {
            guard let window = uiView.window else { return }

            // Check if we already added our gesture recognizer
            let existingGesture = window.gestureRecognizers?.first { recognizer in
                recognizer.name == "TwoFingerDragSelectGesture"
            }

            if existingGesture == nil {
                let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
                panGesture.minimumNumberOfTouches = 2
                panGesture.maximumNumberOfTouches = 2
                panGesture.cancelsTouchesInView = false
                panGesture.delaysTouchesBegan = false
                panGesture.delaysTouchesEnded = false
                panGesture.name = "TwoFingerDragSelectGesture"
                panGesture.delegate = context.coordinator
                window.addGestureRecognizer(panGesture)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEditMode: $isEditMode,
            showDragPreview: $showDragPreview,
            dragLocation: $dragLocation,
            document: document,
            getNodeIdAtPoint: getNodeIdAtPoint
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEditMode: Binding<Bool>
        var showDragPreview: Binding<Bool>
        var dragLocation: Binding<CGPoint>
        var document: OutlineDocument
        var getNodeIdAtPoint: (CGPoint) -> UUID?
        private var hasTriggeredHaptic = false
        private var lastSelectedNodeId: UUID?

        init(isEditMode: Binding<Bool>, showDragPreview: Binding<Bool>, dragLocation: Binding<CGPoint>, document: OutlineDocument, getNodeIdAtPoint: @escaping (CGPoint) -> UUID?) {
            self.isEditMode = isEditMode
            self.showDragPreview = showDragPreview
            self.dragLocation = dragLocation
            self.document = document
            self.getNodeIdAtPoint = getNodeIdAtPoint
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }

            switch gesture.state {
            case .began:
                // Enter edit mode and trigger haptic
                if !isEditMode.wrappedValue {
                    isEditMode.wrappedValue = true
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
                hasTriggeredHaptic = false
                lastSelectedNodeId = nil

                // Select node at initial position and show preview
                let location = gesture.location(in: view)
                selectNodeAtPoint(location)
                dragLocation.wrappedValue = location
                showDragPreview.wrappedValue = true

            case .changed:
                // Select nodes as we drag over them and update preview position
                let location = gesture.location(in: view)
                selectNodeAtPoint(location)
                dragLocation.wrappedValue = location

            case .ended, .cancelled:
                hasTriggeredHaptic = false
                lastSelectedNodeId = nil
                showDragPreview.wrappedValue = false

            default:
                break
            }
        }

        private func selectNodeAtPoint(_ point: CGPoint) {
            guard let nodeId = getNodeIdAtPoint(point) else { return }

            // Only select if we moved to a different node
            guard nodeId != lastSelectedNodeId else { return }
            lastSelectedNodeId = nodeId

            // Toggle selection of this node
            if !document.selectedNodeIds.contains(nodeId) {
                document.selectedNodeIds.insert(nodeId)
                // Light haptic for each new selection
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
            }
        }

        // Allow gesture to work simultaneously with other gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Don't interfere with scroll view
            if otherGestureRecognizer is UIPanGestureRecognizer && !(otherGestureRecognizer.view is UIScrollView) {
                return false
            }
            return true
        }

        // Only recognize when there are exactly 2 touches
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            return gestureRecognizer.numberOfTouches == 2
        }
    }
}

/// Legacy: Simple two-finger tap for entering edit mode (fallback)
struct TwoFingerTapView: UIViewRepresentable {
    var onTwoFingerTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Add gesture to window once available
        DispatchQueue.main.async {
            guard let window = uiView.window else { return }

            // Check if we already added our gesture recognizer
            let existingGesture = window.gestureRecognizers?.first { recognizer in
                recognizer.name == "TwoFingerTapGesture"
            }

            if existingGesture == nil {
                let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
                tapGesture.numberOfTouchesRequired = 2
                tapGesture.numberOfTapsRequired = 1
                tapGesture.cancelsTouchesInView = false
                tapGesture.delaysTouchesBegan = false
                tapGesture.delaysTouchesEnded = false
                tapGesture.name = "TwoFingerTapGesture"
                tapGesture.delegate = context.coordinator
                window.addGestureRecognizer(tapGesture)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTwoFingerTap: onTwoFingerTap)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTwoFingerTap: () -> Void

        init(onTwoFingerTap: @escaping () -> Void) {
            self.onTwoFingerTap = onTwoFingerTap
        }

        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                onTwoFingerTap()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

/// Floating card stack preview shown while dragging (iOS Reminders style)
/// Shows stacked cards under the finger with a count badge
struct FloatingCardStackView: View {
    let selectedCount: Int
    let selectedTitles: [String]
    let position: CGPoint

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 44
    private let stackOffset: CGFloat = 4
    private let fingerOffset: CGFloat = 30 // Offset from finger position

    var body: some View {
        ZStack {
            // Stacked cards (up to 3 visible)
            ForEach(0..<min(selectedCount, 3), id: \.self) { index in
                cardView(at: index)
                    .offset(
                        x: CGFloat(index) * stackOffset,
                        y: CGFloat(index) * stackOffset
                    )
                    .zIndex(Double(3 - index))
            }

            // Count badge (top right)
            if selectedCount > 0 {
                countBadge
                    .offset(x: cardWidth / 2 - 8, y: -cardHeight / 2 + 4)
                    .zIndex(10)
            }
        }
        .position(
            x: position.x + fingerOffset,
            y: position.y - fingerOffset
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: position)
        .allowsHitTesting(false)
    }

    /// Single card in the stack
    private func cardView(at index: Int) -> some View {
        HStack(spacing: 8) {
            // Bullet indicator
            Circle()
                .fill(Color.secondary)
                .frame(width: 8, height: 8)

            // Title text (if available)
            if index < selectedTitles.count {
                Text(selectedTitles[index])
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            } else {
                Text("Bullet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .opacity(1.0 - Double(index) * 0.15)
    }

    /// Count badge showing number of selected items
    private var countBadge: some View {
        Text("\(selectedCount)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, selectedCount >= 10 ? 6 : 0)
            .background(
                Capsule()
                    .fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 4, x: 0, y: 2)
            )
    }
}

/// A view that detects edge swipe from left (like iOS back gesture) for zoom out
struct EdgeSwipeView: UIViewRepresentable {
    var onEdgeSwipe: () -> Void

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        view.backgroundColor = .clear

        let edgePan = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleEdgeSwipe(_:))
        )
        edgePan.edges = .left
        edgePan.cancelsTouchesInView = false
        edgePan.delaysTouchesBegan = false
        edgePan.delaysTouchesEnded = false
        view.addGestureRecognizer(edgePan)

        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) {
        context.coordinator.onEdgeSwipe = onEdgeSwipe
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdgeSwipe: onEdgeSwipe)
    }

    class Coordinator: NSObject {
        var onEdgeSwipe: () -> Void

        init(onEdgeSwipe: @escaping () -> Void) {
            self.onEdgeSwipe = onEdgeSwipe
        }

        @objc func handleEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
            if gesture.state == .ended {
                // Check if swipe was significant enough
                let translation = gesture.translation(in: gesture.view)
                if translation.x > 50 {
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onEdgeSwipe()
                }
            }
        }
    }
}

/// Helper view for transparent fullScreenCover background
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif

#Preview {
    @Previewable @State var document = OutlineDocument.createSample()
    @Previewable @State var zoomedNodeId: UUID? = nil
    @Previewable @State var fontSize: Double = 13.0
    @Previewable @State var isFocusMode: Bool = false
    @Previewable @State var isSearching: Bool = false
    @Previewable @State var collapsedNodeIds: Set<UUID> = []

    OutlineView(document: document, zoomedNodeId: $zoomedNodeId, windowId: UUID(), fontSize: $fontSize, isFocusMode: $isFocusMode, isSearching: $isSearching, collapsedNodeIds: $collapsedNodeIds, navigationHistory: NavigationHistoryManager())
        .frame(width: 500, height: 700)
}
