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
    var isReadOnly: Bool = false  // Disable editing for old week browsing

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

    #endif

    // Base sizes (at default font size 13.0)
    private let baseFontSize: CGFloat = 13.0
    private let baseIndentWidth: CGFloat = 20
    private let baseBulletViewSize: CGFloat = 22  // BulletView width/height
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

    /// Check if this node is collapsed in the current tab
    var isCollapsedInTab: Bool {
        collapsedNodeIds.contains(node.id)
    }

    /// Check if this synced reminder is overdue (past due date and not completed)
    var isOverdue: Bool {
        guard node.isTask, !node.isTaskCompleted, node.reminderIdentifier != nil else { return false }
        guard let dueDate = DateStructureManager.shared.inferredDueDate(for: node) else { return false }
        return Calendar.current.startOfDay(for: Date()) > Calendar.current.startOfDay(for: dueDate)
    }

    /// Whether this node is under a past date node (should be faded).
    /// Date nodes themselves are never faded — only their children.
    var isPastDate: Bool {
        guard !node.isDateNode else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        if let dueDate = DateStructureManager.shared.inferredDueDate(for: node) {
            return Calendar.current.startOfDay(for: dueDate) < today
        }
        return false
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
            // Tree lines spanning full row height (including padding)
            .background(treeLinesBackground)
            // Highlight selected nodes (Cmd+A progressive selection)
            .background(isNodeSelected ? AppTheme.selection : Color.clear)
            .onTapGesture {
                // Clear multi-selection when clicking
                document.clearSelection()
                tryFocusNode()
            }
            // Context menu (right-click)
            .contextMenu {
                if node.reminderIdentifier != nil {
                    Button("Open in Reminders") {
                        ReminderSyncEngine.shared.openInReminders(node)
                    }
                }
            }
            // Dim non-focused nodes in focus mode
            .opacity(isPastDate ? 0.4 : (isFocusMode && !isNodeFocused ? 0.3 : 1.0))
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
        // Tree lines spanning full row height (including padding)
        .background(treeLinesBackground)
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
        // Native context menu on long-press (iOS Reminders style)
        .contextMenu { iOSContextMenuContent }
        // Dim non-focused nodes in focus mode
        .opacity(isPastDate ? 0.4 : (isFocusMode && !isNodeFocused ? 0.3 : 1.0))
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

    /// Context menu items for long-press on iOS (extracted to reduce type-checker complexity)
    @ViewBuilder
    private var iOSContextMenuContent: some View {
        // Reorder
        Section {
            Button {
                document.focusedNodeId = node.id
                document.moveUp()
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            Button {
                document.focusedNodeId = node.id
                document.moveDown()
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
        }

        // Hierarchy
        Section {
            Button {
                document.focusedNodeId = node.id
                document.indent()
            } label: {
                Label("Indent", systemImage: "increase.indent")
            }
            Button {
                document.focusedNodeId = node.id
                document.outdent(zoomBoundaryId: zoomedNodeId)
            } label: {
                Label("Outdent", systemImage: "decrease.indent")
            }
        }

        // Collapse / Expand (only for parent nodes, and not for the zoomed parent)
        if node.hasChildren && node.id != zoomedNodeId {
            Section {
                if collapsedNodeIds.contains(node.id) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            _ = collapsedNodeIds.remove(node.id)
                        }
                    } label: {
                        Label("Expand", systemImage: "chevron.down")
                    }
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            _ = collapsedNodeIds.insert(node.id)
                        }
                    } label: {
                        Label("Collapse", systemImage: "chevron.right")
                    }
                }
            }
        }

        // Zoom
        Section {
            Button {
                performZoomIn(to: node)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            if zoomedNodeId != nil {
                Button {
                    if let zoomedId = zoomedNodeId,
                       let zoomed = document.root.find(id: zoomedId) {
                        if let parent = zoomed.parent, !parent.isRoot {
                            zoomedNodeId = parent.id
                        } else {
                            zoomedNodeId = nil
                        }
                    }
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
            }
        }

        // Select
        Section {
            Button {
                if !isEditMode {
                    isEditMode = true
                }
                document.selectedNodeIds.insert(node.id)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
        }

        // Open in Reminders (conditional)
        if node.reminderIdentifier != nil {
            Section {
                Button {
                    ReminderSyncEngine.shared.openInReminders(node)
                } label: {
                    Label("Open in Reminders", systemImage: "list.bullet")
                }
            }
        }

        // Delete (destructive)
        Section {
            Button(role: .destructive) {
                document.focusedNodeId = node.id
                document.deleteFocusedWithChildren()
            } label: {
                Label("Delete", systemImage: "trash")
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

            // Indentation spacer (tree lines drawn as background on outer row)
            if effectiveDepth > 0 {
                Color.clear
                    .frame(width: CGFloat(effectiveDepth) * indentWidth)
            }

            BulletView(
                node: node,
                isFocused: isNodeFocused,
                isCollapsed: isCollapsedInTab,
                isOverdue: isOverdue,
                scale: scale,
                onTap: {
                    // Cannot collapse the zoomed parent node
                    guard node.id != zoomedNodeId else { return }
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
                    performZoomIn(to: node)
                    #endif
                }
            )
            .offset(y: bulletVerticalOffset)  // Center with first line of text

            // Task checkbox (shown when node is a task)
            if node.isTask {
                Button(action: {
                    node.toggleTaskCompleted()
                    // Sync completion status to Apple Reminders
                    if node.reminderIdentifier != nil,
                       !ReminderSyncEngine.shared.isApplyingReminderChanges {
                        let dueDate = DateStructureManager.shared.inferredDueDate(for: node)
                        ReminderSyncEngine.shared.syncNodeToReminder(node, dueDate: dueDate)
                    }
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

        // Try to outdent (respects zoom boundary)
        let canOutdent = document.canOutdent(zoomBoundaryId: zoomedNodeId)
        if canOutdent {
            // Success haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(.easeOut(duration: 0.15)) {
                document.outdent(zoomBoundaryId: zoomedNodeId)
            }
        } else {
            // Error haptic - can't outdent (at root level or zoom boundary)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    #endif

    /// Focus this node
    private func tryFocusNode() {
        print("[DEBUG] tryFocusNode: CALLED for node '\(node.title.prefix(20))' (id: \(node.id))")
        document.setFocus(node)
        // Mark node as seen when user focuses it
        if node.isUnseen {
            node.isUnseen = false
        }
        print("[DEBUG] tryFocusNode: document.focusedNodeId is now \(document.focusedNodeId?.uuidString.prefix(8) ?? "nil")")
    }

    // MARK: - Zoom Operations

    /// Zoom into a specific node, creating an empty child if needed and focusing on first child
    private func performZoomIn(to target: OutlineNode) {
        zoomedNodeId = target.id
        // Ensure zoomed node is expanded (zoomed parent cannot be collapsed)
        collapsedNodeIds.remove(target.id)

        // Create empty child if none exist
        if target.children.isEmpty {
            let emptyChild = OutlineNode(title: "")
            target.addChild(emptyChild)
            // If parent is empty, focus parent so user can name it first
            // If parent has text, focus the new child so user can start adding content
            if target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.focusedNodeId = target.id
            } else {
                document.focusedNodeId = emptyChild.id
            }
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        } else {
            // Focus on first child
            document.focusedNodeId = target.children.first?.id
        }
        document.focusVersion += 1
    }

    // MARK: - Tree Lines Background

    /// Tree lines drawn as background on the outer row (spans full row height including padding)
    @ViewBuilder
    private var treeLinesBackground: some View {
        if effectiveDepth > 0 {
            let lineWidth = max(1, scale)
            HStack(spacing: 0) {
                // Left padding
                Color.clear
                    .frame(width: leftPadding)

                // Tree line columns
                ForEach(0..<effectiveDepth, id: \.self) { level in
                    Color.clear
                        .frame(width: indentWidth)
                        .overlay(alignment: .topLeading) {
                            if level < treeLines.count && treeLines[level] {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: lineWidth)
                                    .frame(maxHeight: .infinity)
                                    .offset(x: treeLineLeading - lineWidth / 2)
                            }
                        }
                }

                Spacer()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var titleView: some View {
        #if os(macOS)
        OutlineTextField(
            text: Binding(
                get: {
                    let prefix = reminderChildPrefix(for: node)
                    return prefix + node.title
                },
                set: { newValue in
                    let prefix = reminderChildPrefix(for: node)
                    node.title = prefix.isEmpty ? newValue : String(newValue.dropFirst(prefix.count))
                    document.contentDidChange(nodeId: node.id)  // Trigger auto-save
                    // Debounced title sync to Apple Reminders
                    if !ReminderSyncEngine.shared.isApplyingReminderChanges {
                        ReminderSyncEngine.shared.scheduleTitleSync(for: node)
                    }
                }
            ),
            isFocused: isNodeFocused,
            protectedPrefixLength: protectedPrefixLength(for: node),
            isTaskCompleted: node.isTask && node.isTaskCompleted,
            isUnseen: node.isUnseen,
            isDateNode: node.isDateNode,
            hasNextNode: hasNextNode,
            placeholder: isOnlyNode && node.title.isEmpty ? placeholderText : nil,
            searchQuery: searchQuery,
            hasSelection: !document.selectedNodeIds.isEmpty,
            nodeId: node.id,
            nodeTitle: String(node.title.prefix(20)),
            cursorAtEnd: document.cursorAtEndOnNextFocus && isNodeFocused,
            cursorOffset: isNodeFocused ? document.cursorOffsetOnNextFocus : nil,
            focusVersion: document.focusVersion,
            onCursorPositioned: {
                document.cursorAtEndOnNextFocus = false
                document.cursorOffsetOnNextFocus = nil
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
            onSplitLine: isReadOnly ? nil : { [self] textAfter in
                // Parent nodes or zoomed node: split text becomes a child
                // Leaf nodes: split text becomes a sibling
                if node.id == zoomedNodeId || node.hasChildren {
                    collapsedNodeIds.remove(node.id)
                    if let newNode = document.createChild() {
                        newNode.title = textAfter
                    }
                } else {
                    document.createSiblingBelow(withTitle: textAfter)
                }
            },
            isReadOnly: isReadOnly,
            font: .systemFont(ofSize: CGFloat(fontSize)),
            fontWeight: (effectiveDepth == 0 || node.isDateNode) ? .medium : .regular
        )
        #else
        // iOS: Show truncated text when not focused and text is long
        let shouldShowTruncated = !isNodeFocused && !isTextExpanded && isTextLong(node.title)

        if shouldShowTruncated {
            // Truncated view - tap to expand or focus
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: fontSize, weight: (effectiveDepth == 0 || node.isDateNode) ? .semibold : .regular))
                    .foregroundColor(node.isTask && node.isTaskCompleted ? .secondary : (node.isUnseen ? Color.blue : .primary))
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
                    get: {
                        let prefix = reminderChildPrefix(for: node)
                        return prefix + node.title
                    },
                    set: { newValue in
                        let prefix = reminderChildPrefix(for: node)
                        node.title = prefix.isEmpty ? newValue : String(newValue.dropFirst(prefix.count))
                        document.contentDidChange(nodeId: node.id)  // Trigger auto-save
                        // Debounced title sync to Apple Reminders
                        if !ReminderSyncEngine.shared.isApplyingReminderChanges {
                            ReminderSyncEngine.shared.scheduleTitleSync(for: node)
                        }
                    }
                ),
                isFocused: isNodeFocused,
                protectedPrefixLength: protectedPrefixLength(for: node),
                isDateNode: node.isDateNode,
                nodeId: node.id,
                nodeTitle: String(node.title.prefix(20)),
                cursorAtEnd: document.cursorAtEndOnNextFocus && isNodeFocused,
                cursorOffset: isNodeFocused ? document.cursorOffsetOnNextFocus : nil,
                focusVersion: document.focusVersion,
                onCursorPositioned: {
                    document.cursorAtEndOnNextFocus = false
                    document.cursorOffsetOnNextFocus = nil
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
                onCreateSibling: isReadOnly ? nil : {
                    // Parent nodes: create child (nested bullet)
                    // Leaf nodes: create sibling on same level
                    // Zoomed node: always create child
                    if node.id == zoomedNodeId || node.hasChildren {
                        collapsedNodeIds.remove(node.id)
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
                onInsertLink: isReadOnly ? nil : { url in
                    // Insert URL as a smart link with fetched title
                    Task { @MainActor in
                        // First insert a placeholder with the domain name
                        let placeholder = LinkParser.labelFromDomain(url)
                        let markdownLink = "[\(placeholder)](\(url.absoluteString))"

                        // Append to current node's title
                        node.title += (node.title.isEmpty ? "" : " ") + markdownLink
                        document.contentDidChange(nodeId: node.id)

                        // Then fetch the real title and update
                        if let title = await LinkParser.fetchTitle(for: url) {
                            let shortTitle = LinkParser.shortenTitle(title)
                            // Replace placeholder with real title
                            let oldLink = "[\(placeholder)](\(url.absoluteString))"
                            let newLink = "[\(shortTitle)](\(url.absoluteString))"
                            node.title = node.title.replacingOccurrences(of: oldLink, with: newLink)
                            document.contentDidChange(nodeId: node.id)
                        }
                    }
                },
                onDeleteEmpty: isReadOnly ? nil : {
                    document.deleteFocused()
                },
                onAction: handleAction,
                hasMultiSelection: { !document.selectedNodeIds.isEmpty },
                isReadOnly: isReadOnly,
                isUnseen: node.isUnseen,
                fontSize: CGFloat(fontSize),
                fontWeight: (effectiveDepth == 0 || node.isDateNode) ? .semibold : .regular
            )
        }
        #endif
    }

    /// Compute the protected prefix length for date nodes (e.g. "Mon Jan 27" = 10 chars)
    private func dateNodePrefixLength(for node: OutlineNode) -> Int {
        guard node.isDateNode, let date = node.dateNodeDate else { return 0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date).count
    }

    /// Display prefix for reminder metadata children (prepended to title, protected + faded)
    private func reminderChildPrefix(for node: OutlineNode) -> String {
        guard let childType = node.reminderChildType else { return "" }
        switch childType {
        case "note": return "reminder note: "
        case "link": return "link: "
        case "recurrence": return "↻ "
        default: return ""
        }
    }

    /// Combined protected prefix length for date nodes or reminder child prefixes
    private func protectedPrefixLength(for node: OutlineNode) -> Int {
        if node.isDateNode {
            return dateNodePrefixLength(for: node)
        }
        if node.reminderChildType == "recurrence" {
            // Entire text is non-editable (prefix + title)
            let prefix = reminderChildPrefix(for: node)
            return (prefix + node.title).count
        }
        return reminderChildPrefix(for: node).count
    }

    /// Inline time picker for synced reminders (compact DatePicker or clock icon)
    @ViewBuilder
    private var inlineTimePicker: some View {
        let hasTime = node.reminderTimeHour != nil && node.reminderTimeMinute != nil

        if hasTime {
            DatePicker(
                "",
                selection: reminderTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .fixedSize()
            .scaleEffect(0.85)
        } else {
            // "Add time" button — tapping sets a default time (9:00 AM)
            Button {
                node.reminderTimeHour = 9
                node.reminderTimeMinute = 0
                document.contentDidChange(nodeId: node.id)
                syncTimeToReminder()
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: CGFloat(fontSize) * 0.75))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Binding that bridges DatePicker <-> node's hour/minute Int properties
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = node.reminderTimeHour ?? 9
                components.minute = node.reminderTimeMinute ?? 0
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                node.reminderTimeHour = Calendar.current.component(.hour, from: newDate)
                node.reminderTimeMinute = Calendar.current.component(.minute, from: newDate)
                document.contentDidChange(nodeId: node.id)
                syncTimeToReminder()
            }
        )
    }

    /// Sync time change to Apple Reminders
    private func syncTimeToReminder() {
        if node.reminderIdentifier != nil,
           !ReminderSyncEngine.shared.isApplyingReminderChanges {
            let dueDate = DateStructureManager.shared.inferredDueDate(for: node)
            ReminderSyncEngine.shared.syncNodeToReminder(node, dueDate: dueDate)
        }
    }

    private func handleAction(_ action: OutlineAction) {
        // In read-only mode, only allow navigation/view actions
        if isReadOnly {
            switch action {
            case .collapse, .expand, .collapseAll, .expandAll,
                 .navigateUp, .navigateDown, .navigateLeftToPrevious, .navigateRightToNext,
                 .zoomIn, .zoomOut, .zoomToRoot,
                 .selectRowDown, .selectRowUp, .progressiveSelectAll, .clearSelection,
                 .toggleFocusMode, .goHomeAndCollapseAll, .toggleSearch, .copySelected:
                break // Allow these
            default:
                return // Block all editing actions
            }
        }

        switch action {
        case .collapse:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let focused = document.focusedNode, focused.hasChildren {
                // Cannot collapse the zoomed parent node
                guard focused.id != zoomedNodeId else { break }
                collapsedNodeIds.insert(focused.id)
            }
        case .expand:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let focused = document.focusedNode {
                collapsedNodeIds.remove(focused.id)
            }
        case .collapseAll:
            if let focused = document.focusedNode {
                // Collapse the focused node itself (unless it's the zoomed parent)
                if focused.hasChildren && focused.id != zoomedNodeId {
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
            document.outdent(zoomBoundaryId: zoomedNodeId)
        case .createSiblingAbove:
            // If focused node is the zoomed node, create a child instead (sibling would be outside zoom)
            if node.id == zoomedNodeId {
                document.createChild()
            } else {
                document.createSiblingAbove()
            }
        case .createSiblingBelow:
            // Parent nodes: create child (nested bullet)
            // Leaf nodes: create sibling on same level
            // Zoomed node: always create child (sibling would be outside zoom)
            if node.id == zoomedNodeId || node.hasChildren {
                collapsedNodeIds.remove(node.id)  // Expand if collapsed
                document.createChild()
            } else {
                document.createSiblingBelow()
            }
        case .navigateUp:
            document.moveFocusUp(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .navigateDown:
            document.moveFocusDown(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .navigateLeftToPrevious:
            document.cursorAtEndOnNextFocus = true
            document.moveFocusUp(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .navigateRightToNext:
            document.moveFocusDown(zoomedNodeId: zoomedNodeId, collapsedNodeIds: collapsedNodeIds)
        case .zoomIn:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let focused = document.focusedNode {
                performZoomIn(to: focused)
            }
        case .zoomOut:
            // No animation - prevents focus/cursor issues during view hierarchy changes
            if let zoomedId = zoomedNodeId,
               let zoomed = document.root.find(id: zoomedId) {
                // Resolve parent before cleanup (deletion removes node from tree)
                let parentZoom: UUID? = (zoomed.parent.flatMap { $0.isRoot ? nil : $0 })?.id
                // Clean up empty node before leaving
                document.deleteNodeIfEmpty(zoomedId)
                // If node still exists, focus it after zoom out
                if document.root.find(id: zoomedId) != nil {
                    document.focusTargetAfterZoomOut = zoomedId
                }
                zoomedNodeId = parentZoom
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
            // Sync task state to Apple Reminders
            if !ReminderSyncEngine.shared.isApplyingReminderChanges {
                if node.isTask && ReminderSyncEngine.shared.isUnderDateNode(node) {
                    // Became a task (or completion changed) under date → create/update reminder
                    let dueDate = DateStructureManager.shared.inferredDueDate(for: node)
                    ReminderSyncEngine.shared.syncNodeToReminder(node, dueDate: dueDate)
                } else if !node.isTask && node.reminderIdentifier != nil {
                    // Reverted to normal bullet → remove reminder
                    ReminderSyncEngine.shared.removeReminder(for: node)
                }
            }
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
                document.contentDidChange(nodeId: node.id)

                // Then fetch the real title and update
                if let title = await LinkParser.fetchTitle(for: url) {
                    let shortTitle = LinkParser.shortenTitle(title)
                    // Replace placeholder with real title
                    let oldLink = "[\(placeholder)](\(url.absoluteString))"
                    let newLink = "[\(shortTitle)](\(url.absoluteString))"
                    node.title = node.title.replacingOccurrences(of: oldLink, with: newLink)
                    document.contentDidChange(nodeId: node.id)
                }
            }
        }
    }

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

// LiquidGlassContextMenu removed — replaced by native .contextMenu in iOSRowContent

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
