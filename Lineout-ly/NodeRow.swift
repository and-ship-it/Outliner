//
//  NodeRow.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A single row in the outline, displaying a node with proper indentation and tree lines
struct NodeRow: View {
    @Bindable var document: OutlineDocument
    let node: OutlineNode
    let effectiveDepth: Int
    let treeLines: [Bool]  // Which depth levels should show a vertical line
    var hasNextNode: Bool = true  // Whether there's a next node below this one
    var isOnlyNode: Bool = false  // Whether this is the only node (for placeholder)
    let windowId: UUID
    @Binding var zoomedNodeId: UUID?
    @Binding var fontSize: Double
    @Binding var isFocusMode: Bool  // Whether focus mode is enabled
    @Binding var isSearching: Bool  // Whether search bar is visible
    @Binding var collapsedNodeIds: Set<UUID>  // Per-tab collapse state
    var searchQuery: String = ""  // Current search query for highlighting

    // iOS-specific parameters for edit mode and drag-drop
    #if os(iOS)
    @Binding var isEditMode: Bool
    @Binding var draggedNodeId: UUID?
    @Binding var isDraggingSelection: Bool  // Whether user is dragging selected items to move
    @Binding var dropTargetNodeId: UUID?  // Current drop target during drag

    // iOS swipe gesture state
    @State private var swipeOffset: CGFloat = 0
    @State private var hasTriggeredHaptic: Bool = false
    @State private var isDragTarget: Bool = false
    private let swipeThreshold: CGFloat = 60  // Distance to trigger indent/outdent

    // iOS text truncation state (3 lines max when collapsed)
    @State private var isTextExpanded: Bool = false
    private let maxLinesWhenCollapsed: Int = 3

    // Custom context menu state (liquid glass style)
    @State private var showContextMenu: Bool = false
    #endif

    // Base sizes (at default font size 13.0)
    private let baseFontSize: CGFloat = 13.0
    private let baseIndentWidth: CGFloat = 20
    private let baseBulletViewSize: CGFloat = 22  // BulletView width/height
    private let baseLockIconSize: CGFloat = 8
    private let baseCheckboxSize: CGFloat = 14
    private let baseContentLeading: CGFloat = 6

    // Fixed window-level padding (not scaled) - Apple HIG spacing
    #if os(iOS)
    private let leftPadding: CGFloat = 16  // Apple Notes standard
    private let minTrailing: CGFloat = 16
    #else
    private let leftPadding: CGFloat = 32
    private let minTrailing: CGFloat = 32
    #endif

    // Scale factor based on font size
    private var scale: CGFloat { CGFloat(fontSize) / baseFontSize }

    // Vertical offset to center bullet/checkbox with first line of text
    // Text line height ≈ fontSize * 1.2, center at fontSize * 0.6
    // Bullet view is 22 * scale tall, center at 11 * scale
    private var bulletVerticalOffset: CGFloat {
        let textLineCenter = CGFloat(fontSize) * 0.6
        let bulletViewCenter = 11 * scale
        return textLineCenter - bulletViewCenter
    }

    // Checkbox vertical offset (checkbox is 14 * scale, center at 7 * scale)
    private var checkboxVerticalOffset: CGFloat {
        let textLineCenter = CGFloat(fontSize) * 0.6
        let checkboxCenter = 7 * scale
        return textLineCenter - checkboxCenter
    }

    // Scaled sizes (content-level spacing)
    private var indentWidth: CGFloat { baseIndentWidth * scale }
    private var bulletViewSize: CGFloat { baseBulletViewSize * scale }
    private var treeLineLeading: CGFloat { (baseBulletViewSize / 2) * scale }  // Center of bullet = 11 * scale
    private var lockIconSize: CGFloat { baseLockIconSize * scale }
    private var checkboxSize: CGFloat { baseCheckboxSize * scale }
    /// Content leading padding - reduced when there's a checkbox to keep text alignment consistent
    private var contentLeading: CGFloat {
        // When there's a checkbox, reduce leading since checkbox already has padding
        node.isTask ? 2 * scale : baseContentLeading * scale
    }

    private let lineColor = Color.gray.opacity(0.3)

    private let placeholderText = "Tell me, what is it you plan to do with your one wild and precious life?"

    #if os(iOS)
    /// Check if text is long enough to need truncation (roughly more than 3 lines worth)
    /// Uses character count as a heuristic - approximately 40-50 chars per line on mobile
    private func isTextLong(_ text: String) -> Bool {
        // Roughly 45 chars per line on average mobile width, 3 lines = ~135 chars
        // Also check for newlines
        let charThreshold = 120
        let hasMultipleLines = text.contains("\n")
        return text.count > charThreshold || hasMultipleLines
    }
    #endif

    var isNodeFocused: Bool {
        document.focusedNodeId == node.id
    }

    /// Check if this node is in multi-selection (Cmd+A progressive)
    var isNodeSelected: Bool {
        document.isNodeSelected(node.id)
    }

    /// Check if this node is locked by another window
    var isLockedByOtherWindow: Bool {
        WindowManager.shared.isNodeLocked(node.id, for: windowId)
    }

    /// Check if this node is collapsed in the current tab
    var isCollapsedInTab: Bool {
        collapsedNodeIds.contains(node.id)
    }

    #if os(iOS)
    /// Check if this node is the current drop target for moving selected items
    var isCurrentDropTarget: Bool {
        dropTargetNodeId == node.id && isDraggingSelection && !isNodeSelected
    }
    #endif

    var body: some View {
        #if os(iOS)
        iOSRowContent
        #else
        macOSRowContent
        #endif
    }

    #if os(macOS)
    private var macOSRowContent: some View {
        rowContent
            .padding(.vertical, 1 * scale)
            .contentShape(Rectangle())
            // Highlight selected nodes (Cmd+A progressive selection)
            .background(isNodeSelected ? AppTheme.selection : Color.clear)
            .onTapGesture {
                // Clear multi-selection when clicking
                document.clearSelection()
                tryFocusNode()
            }
            // Dim non-focused nodes in focus mode
            .opacity(isFocusMode && !isNodeFocused ? 0.3 : 1.0)
    }
    #endif

    #if os(iOS)
    private var iOSRowContent: some View {
        HStack(spacing: 0) {
            // Selection circle (shown in edit mode)
            if isEditMode {
                Button(action: {
                    toggleSelection()
                }) {
                    ZStack {
                        Circle()
                            .stroke(isNodeSelected ? AppTheme.amber : Color.gray.opacity(0.4), lineWidth: 2)
                            .frame(width: 24 * scale, height: 24 * scale)

                        if isNodeSelected {
                            Circle()
                                .fill(AppTheme.amber)
                                .frame(width: 18 * scale, height: 18 * scale)

                            Image(systemName: "checkmark")
                                .font(.system(size: 10 * scale, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.trailing, 8)
            }

            rowContent
        }
        .padding(.vertical, 1 * scale)
        .contentShape(Rectangle())
        // Highlight selected nodes or drop target
        .background(
            Group {
                if isNodeSelected && !isDraggingSelection {
                    // Normal selection highlight
                    AppTheme.liquidGlassSelection
                } else if isNodeSelected && isDraggingSelection {
                    // Selected items being dragged - more prominent
                    AppTheme.amber.opacity(0.3)
                } else if isCurrentDropTarget {
                    // Drop target highlight - liquid glass style
                    AppTheme.dropTargetHighlight
                } else if isDragTarget {
                    AppTheme.amber.opacity(0.2)
                } else {
                    Color.clear
                }
            }
        )
        // Drop target indicator line (liquid glass style)
        .overlay(
            Group {
                if isCurrentDropTarget {
                    VStack {
                        HStack(spacing: 0) {
                            // Glowing circle
                            Circle()
                                .fill(AppTheme.amber)
                                .frame(width: 10, height: 10)
                                .shadow(color: AppTheme.amber.opacity(0.6), radius: 4)
                            // Gradient line
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.amber, AppTheme.amber.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 3)
                        }
                        .padding(.leading, leftPadding + CGFloat(effectiveDepth) * indentWidth)
                        Spacer()
                    }
                } else if isDragTarget {
                    VStack {
                        HStack {
                            Circle()
                                .fill(AppTheme.amber)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(AppTheme.amber)
                                .frame(height: 2)
                        }
                        .padding(.leading, leftPadding + CGFloat(effectiveDepth) * indentWidth)
                        Spacer()
                    }
                }
            },
            alignment: .top
        )
        // Tap gesture - different behavior based on mode
        .onTapGesture {
            if isDraggingSelection && !isNodeSelected {
                // In drag mode - set this as drop target and move items
                handleDropSelection()
            } else if isEditMode {
                toggleSelection()
            } else {
                document.clearSelection()
                tryFocusNode()
            }
        }
        // Long press to show custom liquid glass context menu
        .onLongPressGesture(minimumDuration: 0.5) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showContextMenu = true
        }
        // Custom liquid glass styled context menu sheet
        .sheet(isPresented: $showContextMenu) {
            LiquidGlassContextMenu(
                onZoomIn: {
                    showContextMenu = false
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    zoomedNodeId = node.id
                },
                onSelect: {
                    showContextMenu = false
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    if !isEditMode {
                        isEditMode = true
                    }
                    document.selectedNodeIds.insert(node.id)
                },
                onDelete: {
                    showContextMenu = false
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                    document.focusedNodeId = node.id
                    document.deleteFocusedWithChildren()
                }
            )
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
            .presentationBackground(.ultraThinMaterial)
        }
        // Dim non-focused nodes in focus mode
        .opacity(isFocusMode && !isNodeFocused ? 0.3 : 1.0)
        // Swipe gesture for indent/outdent (only when not in edit mode)
        .offset(x: isEditMode ? 0 : swipeOffset)
        .gesture(
            isEditMode ? nil : DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { value in
                    // Only allow horizontal swipes (ignore vertical scrolling)
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)

                    // Must be primarily horizontal
                    guard horizontalDistance > verticalDistance * 1.5 else {
                        return
                    }

                    // Limit the offset to give resistance feel
                    let maxOffset: CGFloat = 80
                    let translation = value.translation.width
                    swipeOffset = min(maxOffset, max(-maxOffset, translation * 0.6))

                    // Trigger haptic when crossing threshold
                    if !hasTriggeredHaptic && abs(swipeOffset) >= swipeThreshold * 0.6 {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        hasTriggeredHaptic = true
                    }
                }
                .onEnded { value in
                    let horizontalDistance = value.translation.width

                    // Check if we crossed the threshold
                    if horizontalDistance > swipeThreshold {
                        // Swipe right → indent
                        performIndent()
                    } else if horizontalDistance < -swipeThreshold {
                        // Swipe left → outdent
                        performOutdent()
                    }

                    // Reset state
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeOffset = 0
                    }
                    hasTriggeredHaptic = false
                }
        )
        // Drag support for reordering (when in edit mode and selected)
        .draggable(node.id.uuidString) {
            // Drag preview
            HStack {
                if document.selectedNodeIds.count > 1 {
                    Text("\(document.selectedNodeIds.count) items")
                        .font(.system(size: fontSize))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.amber.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                } else {
                    Text(node.title.isEmpty ? "Empty bullet" : String(node.title.prefix(30)))
                        .font(.system(size: fontSize))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.amber.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        // Drop target
        .dropDestination(for: String.self) { items, location in
            guard let droppedIdString = items.first,
                  let droppedId = UUID(uuidString: droppedIdString) else {
                return false
            }

            // Don't drop on itself
            guard droppedId != node.id else { return false }

            // Perform the move with haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Move the dragged node(s) to this location
            withAnimation(.easeOut(duration: 0.2)) {
                document.moveNodeAfter(nodeId: droppedId, targetId: node.id)
            }

            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) {
                isDragTarget = targeted
            }
            if targeted && !hasTriggeredHaptic {
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
                hasTriggeredHaptic = true
            }
            if !targeted {
                hasTriggeredHaptic = false
            }
        }
    }

    /// Toggle selection of this node with haptic feedback
    private func toggleSelection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        if document.selectedNodeIds.contains(node.id) {
            document.selectedNodeIds.remove(node.id)
            // Exit edit mode if nothing selected
            if document.selectedNodeIds.isEmpty {
                isEditMode = false
            }
        } else {
            document.selectedNodeIds.insert(node.id)
        }
    }

    /// Handle dropping selected items after this node
    private func handleDropSelection() {
        // Can't drop on a selected node or on itself
        guard !isNodeSelected else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Move all selected nodes after this node
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            document.moveSelectedNodesAfter(targetId: node.id)

            // Exit drag mode and clear selection
            isDraggingSelection = false
            dropTargetNodeId = nil
            document.clearSelection()
            isEditMode = false
        }
    }
    #endif

    /// The main row content (shared between platforms)
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left padding
            Spacer()
                .frame(width: leftPadding)

            // Indentation with tree lines
            if effectiveDepth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<effectiveDepth, id: \.self) { level in
                        // Each column is indentWidth (20*scale) wide
                        // Tree line should be at treeLineLeading (11*scale) from left edge
                        // This aligns with the center of the parent bullet at that depth level
                        let lineWidth = max(1, scale)

                        Color.clear
                            .frame(width: indentWidth)
                            .overlay(alignment: .topLeading) {
                                if level < treeLines.count && treeLines[level] {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: lineWidth, height: nil)
                                        .frame(maxHeight: .infinity)
                                        .offset(x: treeLineLeading - lineWidth / 2)
                                        .padding(.top, -6 * scale)
                                        .padding(.bottom, -4 * scale)
                                }
                            }
                    }
                }
            }

            // Bullet with lock indicator
            ZStack(alignment: .topTrailing) {
                BulletView(
                    node: node,
                    isFocused: isNodeFocused,
                    isCollapsed: isCollapsedInTab,
                    scale: scale,
                    onTap: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            // Toggle per-tab collapse state
                            if collapsedNodeIds.contains(node.id) {
                                collapsedNodeIds.remove(node.id)
                            } else {
                                collapsedNodeIds.insert(node.id)
                            }
                        }
                    },
                    onDoubleTap: {
                        #if os(iOS)
                        // Double-tap on bullet zooms into this node
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        zoomedNodeId = node.id
                        #endif
                    }
                )

                // Lock indicator when locked by another window
                if isLockedByOtherWindow {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockIconSize))
                        .foregroundStyle(.gray)
                        .offset(x: 4 * scale, y: -2 * scale)
                }
            }
            .offset(y: bulletVerticalOffset)  // Center with first line of text

            // Task checkbox (shown when node is a task)
            if node.isTask {
                Button(action: {
                    node.toggleTaskCompleted()
                }) {
                    Image(systemName: node.isTaskCompleted ? "checkmark.square.fill" : "square")
                        .font(.system(size: checkboxSize))
                        .foregroundStyle(node.isTaskCompleted ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4 * scale)
                .offset(y: checkboxVerticalOffset)  // Center with first line of text
            }

            // Content
            VStack(alignment: .leading, spacing: 2 * scale) {
                titleView
                    .fixedSize(horizontal: false, vertical: true)

                if !isCollapsedInTab && node.hasBody {
                    bodyView
                }
            }
            .padding(.leading, contentLeading)
            .opacity(isLockedByOtherWindow ? 0.5 : 1.0) // Dim locked nodes

            Spacer(minLength: minTrailing)
        }
    }

    // MARK: - iOS Swipe Actions

    #if os(iOS)
    /// Perform indent with haptic feedback
    private func performIndent() {
        // Focus this node first
        document.focusedNodeId = node.id

        // Try to indent
        let canIndent = document.canIndent()
        if canIndent {
            // Success haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(.easeOut(duration: 0.15)) {
                document.indent()
            }
        } else {
            // Error haptic - can't indent (no sibling above or already at root level)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    /// Perform outdent with haptic feedback
    private func performOutdent() {
        // Focus this node first
        document.focusedNodeId = node.id

        // Try to outdent
        let canOutdent = document.canOutdent()
        if canOutdent {
            // Success haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(.easeOut(duration: 0.15)) {
                document.outdent()
            }
        } else {
            // Error haptic - can't outdent (already at root level)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    #endif

    /// Try to focus this node, acquiring lock if needed
    private func tryFocusNode() {
        print("[DEBUG] tryFocusNode: CALLED for node '\(node.title.prefix(20))' (id: \(node.id))")
        // If locked by another window, don't allow focus
        if isLockedByOtherWindow {
            print("[DEBUG] tryFocusNode: BLOCKED - locked by other window")
            return
        }

        let oldFocusId = document.focusedNodeId
        print("[DEBUG] tryFocusNode: oldFocusId=\(oldFocusId?.uuidString.prefix(8) ?? "nil")")

        // Try to acquire lock
        if WindowManager.shared.tryLock(nodeId: node.id, for: windowId) {
            print("[DEBUG] tryFocusNode: lock acquired, calling document.setFocus")
            // Release old lock
            if let oldId = oldFocusId, oldId != node.id {
                WindowManager.shared.releaseLock(nodeId: oldId, for: windowId)
            }
            document.setFocus(node)
            print("[DEBUG] tryFocusNode: document.focusedNodeId is now \(document.focusedNodeId?.uuidString.prefix(8) ?? "nil")")
        } else {
            print("[DEBUG] tryFocusNode: FAILED to acquire lock")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var titleView: some View {
        #if os(macOS)
        OutlineTextField(
            text: Binding(
                get: { node.title },
                set: { newValue in
                    // Only allow editing if not locked
                    if !isLockedByOtherWindow {
                        node.title = newValue
                        document.contentDidChange()  // Trigger auto-save
                    }
                }
            ),
            isFocused: isNodeFocused && !isLockedByOtherWindow,
            isLocked: isLockedByOtherWindow,
            isTaskCompleted: node.isTask && node.isTaskCompleted,
            hasNextNode: hasNextNode,
            placeholder: isOnlyNode && node.title.isEmpty ? placeholderText : nil,
            searchQuery: searchQuery,
            hasSelection: !document.selectedNodeIds.isEmpty,
            nodeId: node.id,
            nodeTitle: String(node.title.prefix(20)),
            cursorAtEnd: document.cursorAtEndOnNextFocus && isNodeFocused,
            focusVersion: document.focusVersion,
            onCursorPositioned: {
                document.cursorAtEndOnNextFocus = false
            },
            onFocusChange: { [self] focused in
                print("[DEBUG] onFocusChange(macOS): focused=\(focused), node='\(node.title.prefix(20))' (id: \(node.id.uuidString.prefix(8)))")
                if focused {
                    // Always sync document.focusedNodeId when any text field gains focus
                    // This ensures mouse clicks update the focused node properly
                    print("[DEBUG] onFocusChange(macOS): calling tryFocusNode()")
                    tryFocusNode()
                }
            },
            onAction: handleAction,
            onSplitLine: { [self] textAfter in
                // If focused node is the zoomed node, create a child instead (sibling would be outside zoom)
                if node.id == zoomedNodeId {
                    if let newNode = document.createChild() {
                        newNode.title = textAfter
                    }
                } else {
                    document.createSiblingBelow(withTitle: textAfter)
                }
            },
            font: .systemFont(ofSize: CGFloat(fontSize)),
            fontWeight: effectiveDepth == 0 ? .medium : .regular
        )
        #else
        // iOS: Show truncated text when not focused and text is long
        let shouldShowTruncated = !isNodeFocused && !isTextExpanded && isTextLong(node.title)

        if shouldShowTruncated {
            // Truncated view - tap to expand or focus
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: fontSize, weight: effectiveDepth == 0 ? .semibold : .regular))
                    .foregroundColor(node.isTask && node.isTaskCompleted ? .secondary : .primary)
                    .strikethrough(node.isTask && node.isTaskCompleted)
                    .lineLimit(maxLinesWhenCollapsed)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // "more..." indicator
                Text("more...")
                    .font(.system(size: fontSize * 0.85))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Expand text and focus
                isTextExpanded = true
                tryFocusNode()
                document.focusVersion += 1
            }
        } else {
            // Full text field for editing
            OutlineTextField(
                text: Binding(
                    get: { node.title },
                    set: { newValue in
                        if !isLockedByOtherWindow {
                            node.title = newValue
                            document.contentDidChange()  // Trigger auto-save
                        }
                    }
                ),
                isFocused: isNodeFocused && !isLockedByOtherWindow,
                nodeId: node.id,
                nodeTitle: String(node.title.prefix(20)),
                cursorAtEnd: document.cursorAtEndOnNextFocus && isNodeFocused,
                focusVersion: document.focusVersion,
                onCursorPositioned: {
                    document.cursorAtEndOnNextFocus = false
                },
                onFocusChange: { [self] focused in
                    print("[DEBUG] onFocusChange(iOS): focused=\(focused), node='\(node.title.prefix(20))' (id: \(node.id.uuidString.prefix(8)))")
                    if focused {
                        // Always sync document.focusedNodeId when any text field gains focus
                        // This ensures mouse clicks update the focused node properly
                        print("[DEBUG] onFocusChange(iOS): calling tryFocusNode()")
                        tryFocusNode()
                    } else {
                        // When losing focus, collapse the text
                        isTextExpanded = false
                    }
                },
                onCreateSibling: {
                    // Enter key pressed - create sibling bullet (or child if at zoomed node)
                    if node.id == zoomedNodeId {
                        document.createChild()
                    } else {
                        document.createSiblingBelow()
                    }
                    // Force focus update for iOS
                    document.focusVersion += 1
                },
                onNavigateUp: {
                    // Spacebar trackpad navigation - move to previous node with cursor at end
                    document.cursorAtEndOnNextFocus = true
                    document.moveFocusUp(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
                },
                onNavigateDown: {
                    // Spacebar trackpad navigation - move to next node with cursor at start
                    document.cursorAtEndOnNextFocus = false
                    document.moveFocusDown(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
                },
                onInsertLink: { url in
                    // Insert URL as a smart link with fetched title
                    Task { @MainActor in
                        // First insert a placeholder with the domain name
                        let placeholder = LinkParser.labelFromDomain(url)
                        let markdownLink = "[\(placeholder)](\(url.absoluteString))"

                        // Append to current node's title
                        node.title += (node.title.isEmpty ? "" : " ") + markdownLink
                        document.contentDidChange()

                        // Then fetch the real title and update
                        if let title = await LinkParser.fetchTitle(for: url) {
                            let shortTitle = LinkParser.shortenTitle(title)
                            // Replace placeholder with real title
                            let oldLink = "[\(placeholder)](\(url.absoluteString))"
                            let newLink = "[\(shortTitle)](\(url.absoluteString))"
                            node.title = node.title.replacingOccurrences(of: oldLink, with: newLink)
                            document.contentDidChange()
                        }
                    }
                },
                fontSize: CGFloat(fontSize),
                fontWeight: effectiveDepth == 0 ? .semibold : .regular
            )
        }
        #endif
    }

    #if os(macOS)
    private func handleAction(_ action: OutlineAction) {
        switch action {
        case .collapse:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            print("[DEBUG] collapse: focusedNode='\(document.focusedNode?.title.prefix(20) ?? "nil")', hasChildren=\(document.focusedNode?.hasChildren ?? false), zoomedNodeId=\(zoomedNodeId?.uuidString.prefix(8) ?? "nil")")
            if let focused = document.focusedNode, focused.hasChildren {
                print("[DEBUG] collapse: inserting into collapsedNodeIds")
                collapsedNodeIds.insert(focused.id)
            } else {
                print("[DEBUG] collapse: NOT collapsing - either no focus or no children")
            }
        case .expand:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let focused = document.focusedNode {
                collapsedNodeIds.remove(focused.id)
            }
        case .collapseAll:
            if let focused = document.focusedNode {
                // Collapse the focused node itself
                if focused.hasChildren {
                    collapsedNodeIds.insert(focused.id)
                }
                // Collapse all descendants that have children
                for descendant in focused.flattened() {
                    if descendant.hasChildren {
                        collapsedNodeIds.insert(descendant.id)
                    }
                }
            }
        case .expandAll:
            if let focused = document.focusedNode {
                // Expand the focused node and all descendants
                collapsedNodeIds.remove(focused.id)
                for descendant in focused.flattened() {
                    collapsedNodeIds.remove(descendant.id)
                }
            }
        case .moveUp:
            document.moveUp()
        case .moveDown:
            document.moveDown()
        case .indent:
            document.indent()
        case .outdent:
            document.outdent()
        case .createSiblingAbove:
            // If focused node is the zoomed node, create a child instead (sibling would be outside zoom)
            if node.id == zoomedNodeId {
                document.createChild()
            } else {
                document.createSiblingAbove()
            }
        case .createSiblingBelow:
            // If focused node is the zoomed node, create a child instead (sibling would be outside zoom)
            if node.id == zoomedNodeId {
                document.createChild()
            } else {
                document.createSiblingBelow()
            }
        case .navigateUp:
            document.moveFocusUp(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .navigateDown:
            document.moveFocusDown(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .zoomIn:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let focused = document.focusedNode {
                zoomedNodeId = focused.id
            }
        case .zoomOut:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let zoomedId = zoomedNodeId,
               let zoomed = document.root.find(id: zoomedId) {
                if let parent = zoomed.parent, !parent.isRoot {
                    zoomedNodeId = parent.id
                } else {
                    zoomedNodeId = nil
                }
            }
        case .zoomToRoot:
            // Delete empty auto-created bullet before going home
            if let currentZoomId = zoomedNodeId {
                document.deleteNodeIfEmpty(currentZoomId)
            }
            // No animation - prevents focus/cursor issues
            zoomedNodeId = nil
        case .selectRowDown:
            document.selectRowDown()
        case .selectRowUp:
            document.selectRowUp()
        case .progressiveSelectAll:
            document.expandSelectionProgressively()
        case .clearSelection:
            document.clearSelection()
        case .copySelected:
            document.copySelected()
        case .cutSelected:
            document.cutSelected()
        case .deleteWithChildren:
            document.deleteFocusedWithChildren()
        case .deleteSelected:
            document.deleteSelected()
        case .deleteEmpty:
            document.deleteFocused()
        case .mergeWithPrevious(let textToMerge):
            // Merge current bullet's text with previous bullet
            document.mergeWithPrevious(textToMerge: textToMerge, zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .toggleTask:
            node.toggleTask()
        case .toggleFocusMode:
            isFocusMode.toggle()
        case .goHomeAndCollapseAll:
            // Delete empty auto-created bullet before going home
            if let currentZoomId = zoomedNodeId {
                document.deleteNodeIfEmpty(currentZoomId)
            }
            // No animation - prevents focus/cursor issues
            zoomedNodeId = nil
            // Collapse all nodes with children in per-tab state
            for node in document.root.flattened() {
                if node.hasChildren {
                    collapsedNodeIds.insert(node.id)
                }
            }
            // Focus the first visible node (top-level since all collapsed)
            if let firstNode = document.root.children.first {
                document.focusedNodeId = firstNode.id
                document.focusVersion += 1
            }
        case .toggleSearch:
            isSearching.toggle()
        case .smartPaste(let nodes, let cursorAtEnd, let cursorAtStart):
            // Handle structured paste - when zoomed, paste creates children of zoomed node
            if let firstInserted = document.smartPasteNodes(nodes, cursorAtEnd: cursorAtEnd, cursorAtStart: cursorAtStart, zoomedNodeId: zoomedNodeId) {
                // Focus the first inserted node
                DispatchQueue.main.async {
                    document.focusedNodeId = firstInserted.id
                    document.focusVersion += 1
                }
            }
        case .insertLink(let url):
            // Insert URL as a smart link with fetched title
            Task { @MainActor in
                // First insert a placeholder with the domain name
                let placeholder = LinkParser.labelFromDomain(url)
                let markdownLink = "[\(placeholder)](\(url.absoluteString))"

                // Append to current node's title
                node.title += (node.title.isEmpty ? "" : " ") + markdownLink
                document.contentDidChange()

                // Then fetch the real title and update
                if let title = await LinkParser.fetchTitle(for: url) {
                    let shortTitle = LinkParser.shortenTitle(title)
                    // Replace placeholder with real title
                    let oldLink = "[\(placeholder)](\(url.absoluteString))"
                    let newLink = "[\(shortTitle)](\(url.absoluteString))"
                    node.title = node.title.replacingOccurrences(of: oldLink, with: newLink)
                    document.contentDidChange()
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private var bodyView: some View {
        Text(node.body)
            .font(.system(size: CGFloat(fontSize) * 0.85))  // Body text slightly smaller
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .padding(.leading, 4 * scale)
            .padding(.top, 1 * scale)
    }
}

// MARK: - Liquid Glass Context Menu (iOS)

#if os(iOS)
/// Custom context menu with liquid glass (frosted) styling
/// Replaces the standard system context menu for a more modern appearance
struct LiquidGlassContextMenu: View {
    let onZoomIn: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Zoom In button
            Button(action: onZoomIn) {
                HStack {
                    Label("Zoom In", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 17))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .foregroundColor(.primary)

            Divider()
                .padding(.horizontal, 16)

            // Select button
            Button(action: onSelect) {
                HStack {
                    Label("Select", systemImage: "checkmark.circle")
                        .font(.system(size: 17))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .foregroundColor(.primary)

            Divider()
                .padding(.horizontal, 16)

            // Delete button (destructive)
            Button(action: onDelete) {
                HStack {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 17))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .foregroundColor(.red)
        }
        .background(.clear)
    }
}
#endif

#if os(macOS)
#Preview {
    @Previewable @State var document = OutlineDocument.createSample()
    @Previewable @State var zoomedNodeId: UUID? = nil
    @Previewable @State var fontSize: Double = 13.0
    @Previewable @State var isFocusMode: Bool = false
    @Previewable @State var isSearching: Bool = false
    @Previewable @State var collapsedNodeIds: Set<UUID> = []

    ScrollView {
        VStack(spacing: 0) {
            ForEach(document.visibleNodes) { node in
                NodeRow(
                    document: document,
                    node: node,
                    effectiveDepth: node.depth,
                    treeLines: [],
                    windowId: UUID(),
                    zoomedNodeId: $zoomedNodeId,
                    fontSize: $fontSize,
                    isFocusMode: $isFocusMode,
                    isSearching: $isSearching,
                    collapsedNodeIds: $collapsedNodeIds
                )
            }
        }
    }
    .frame(width: 400, height: 600)
}
#else
#Preview {
    @Previewable @State var document = OutlineDocument.createSample()
    @Previewable @State var zoomedNodeId: UUID? = nil
    @Previewable @State var fontSize: Double = 13.0
    @Previewable @State var isFocusMode: Bool = false
    @Previewable @State var isSearching: Bool = false
    @Previewable @State var collapsedNodeIds: Set<UUID> = []
    @Previewable @State var isEditMode: Bool = false
    @Previewable @State var draggedNodeId: UUID? = nil
    @Previewable @State var isDraggingSelection: Bool = false
    @Previewable @State var dropTargetNodeId: UUID? = nil

    ScrollView {
        VStack(spacing: 0) {
            ForEach(document.visibleNodes) { node in
                NodeRow(
                    document: document,
                    node: node,
                    effectiveDepth: node.depth,
                    treeLines: [],
                    windowId: UUID(),
                    zoomedNodeId: $zoomedNodeId,
                    fontSize: $fontSize,
                    isFocusMode: $isFocusMode,
                    isSearching: $isSearching,
                    collapsedNodeIds: $collapsedNodeIds,
                    isEditMode: $isEditMode,
                    draggedNodeId: $draggedNodeId,
                    isDraggingSelection: $isDraggingSelection,
                    dropTargetNodeId: $dropTargetNodeId
                )
            }
        }
    }
    .frame(width: 400, height: 600)
}
#endif
