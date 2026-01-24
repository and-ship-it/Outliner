//
//  NodeRow.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

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
    var searchQuery: String = ""  // Current search query for highlighting

    // Base sizes (at default font size 13.0)
    private let baseFontSize: CGFloat = 13.0
    private let baseIndentWidth: CGFloat = 20
    private let baseBulletViewSize: CGFloat = 22  // BulletView width/height
    private let baseLockIconSize: CGFloat = 8
    private let baseCheckboxSize: CGFloat = 14
    private let baseContentLeading: CGFloat = 6

    // Fixed window-level padding (not scaled) - Apple HIG premium spacing
    private let leftPadding: CGFloat = 32
    private let minTrailing: CGFloat = 32

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
    private var contentLeading: CGFloat { baseContentLeading * scale }

    private let lineColor = Color.gray.opacity(0.3)

    private let placeholderText = "Tell me, what is it you plan to do with your one wild and precious life?"

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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left padding
            Spacer()
                .frame(width: leftPadding)

            // Indentation with tree lines
            if effectiveDepth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<effectiveDepth, id: \.self) { level in
                        ZStack {
                            // Vertical line if there are more siblings at this level
                            if level < treeLines.count && treeLines[level] {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(width: max(1, scale))
                                    .padding(.leading, treeLineLeading)
                                    .padding(.top, -6 * scale)
                                    .padding(.bottom, -4 * scale)
                            }
                        }
                        .frame(width: indentWidth)
                    }
                }
            }

            // Bullet with lock indicator
            ZStack(alignment: .topTrailing) {
                BulletView(node: node, isFocused: isNodeFocused, scale: scale) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        document.toggleNode(node)
                    }
                }

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

                if !node.isCollapsed && node.hasBody {
                    bodyView
                }
            }
            .padding(.leading, contentLeading)
            .opacity(isLockedByOtherWindow ? 0.5 : 1.0) // Dim locked nodes

            Spacer(minLength: minTrailing)
        }
        .padding(.vertical, 1 * scale)
        .contentShape(Rectangle())
        // Highlight selected nodes (Cmd+A progressive selection)
        .background(isNodeSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .onTapGesture {
            // Clear multi-selection when clicking
            document.clearSelection()
            tryFocusNode()
        }
        // Dim non-focused nodes in focus mode
        .opacity(isFocusMode && !isNodeFocused ? 0.3 : 1.0)
    }

    /// Try to focus this node, acquiring lock if needed
    private func tryFocusNode() {
        // If locked by another window, don't allow focus
        if isLockedByOtherWindow {
            return
        }

        let oldFocusId = document.focusedNodeId

        // Try to acquire lock
        if WindowManager.shared.tryLock(nodeId: node.id, for: windowId) {
            // Release old lock
            if let oldId = oldFocusId, oldId != node.id {
                WindowManager.shared.releaseLock(nodeId: oldId, for: windowId)
            }
            document.setFocus(node)
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
            onFocusChange: { focused in
                if focused && !isNodeFocused {
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
            onFocusChange: { focused in
                if focused && !isNodeFocused {
                    tryFocusNode()
                }
            },
            font: .body,
            fontWeight: effectiveDepth == 0 ? .medium : .regular
        )
        #endif
    }

    #if os(macOS)
    private func handleAction(_ action: OutlineAction) {
        switch action {
        case .collapse:
            withAnimation(.easeOut(duration: 0.15)) {
                document.collapseFocused()
            }
        case .expand:
            withAnimation(.easeOut(duration: 0.15)) {
                document.expandFocused()
            }
        case .collapseAll:
            if let node = document.focusedNode {
                document.collapseAllChildren(of: node)
            }
        case .expandAll:
            if let node = document.focusedNode {
                document.expandAllChildren(of: node)
            }
        case .moveUp:
            withAnimation(.easeOut(duration: 0.15)) {
                document.moveUp()
            }
        case .moveDown:
            withAnimation(.easeOut(duration: 0.15)) {
                document.moveDown()
            }
        case .indent:
            withAnimation(.easeOut(duration: 0.15)) {
                document.indent()
            }
        case .outdent:
            withAnimation(.easeOut(duration: 0.15)) {
                document.outdent()
            }
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
            document.moveFocusUp()
        case .navigateDown:
            document.moveFocusDown()
        case .zoomIn:
            if let focused = document.focusedNode {
                withAnimation(.easeOut(duration: 0.2)) {
                    zoomedNodeId = focused.id
                }
            }
        case .zoomOut:
            if let zoomedId = zoomedNodeId,
               let zoomed = document.root.find(id: zoomedId) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if let parent = zoomed.parent, !parent.isRoot {
                        zoomedNodeId = parent.id
                    } else {
                        zoomedNodeId = nil
                    }
                }
            }
        case .zoomToRoot:
            withAnimation(.easeOut(duration: 0.2)) {
                zoomedNodeId = nil
            }
        case .progressiveSelectDown:
            break
        case .progressiveSelectAll:
            document.expandSelectionProgressively()
        case .deleteWithChildren:
            withAnimation(.easeOut(duration: 0.15)) {
                document.deleteFocusedWithChildren()
            }
        case .toggleTask:
            node.toggleTask()
        case .toggleFocusMode:
            isFocusMode.toggle()
        case .goHomeAndCollapseAll:
            withAnimation(.easeOut(duration: 0.2)) {
                zoomedNodeId = nil
                document.collapseAll()
            }
        case .toggleSearch:
            isSearching.toggle()
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

#Preview {
    @Previewable @State var document = OutlineDocument.createSample()
    @Previewable @State var zoomedNodeId: UUID? = nil
    @Previewable @State var fontSize: Double = 13.0
    @Previewable @State var isFocusMode: Bool = false
    @Previewable @State var isSearching: Bool = false

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
                    isSearching: $isSearching
                )
            }
        }
    }
    .frame(width: 400, height: 600)
}
