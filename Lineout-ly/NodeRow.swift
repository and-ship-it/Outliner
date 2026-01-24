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

    private let indentWidth: CGFloat = 20
    private let lineColor = Color.gray.opacity(0.3)

    private let placeholderText = "Tell me, what is it you plan to do with your one wild and precious life?"

    var isNodeFocused: Bool {
        document.focusedNodeId == node.id
    }

    /// Check if this node is locked by another window
    var isLockedByOtherWindow: Bool {
        WindowManager.shared.isNodeLocked(node.id, for: windowId)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left padding
            Spacer()
                .frame(width: 16)

            // Indentation with tree lines
            if effectiveDepth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<effectiveDepth, id: \.self) { level in
                        ZStack {
                            // Vertical line if there are more siblings at this level
                            if level < treeLines.count && treeLines[level] {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(width: 1)
                                    .padding(.leading, indentWidth + 10)
                                    .padding(.top, -6)
                                    .padding(.bottom, -4)
                            }
                        }
                        .frame(width: indentWidth)
                    }
                }
            }

            // Bullet with lock indicator
            ZStack(alignment: .topTrailing) {
                BulletView(node: node, isFocused: isNodeFocused) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        document.toggleNode(node)
                    }
                }

                // Lock indicator when locked by another window
                if isLockedByOtherWindow {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                        .offset(x: 4, y: -2)
                }
            }
            .padding(.top, 2)

            // Task checkbox (shown when node is a task)
            if node.isTask {
                Button(action: {
                    node.toggleTaskCompleted()
                }) {
                    Image(systemName: node.isTaskCompleted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(node.isTaskCompleted ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.top, 2)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                titleView
                    .fixedSize(horizontal: false, vertical: true)

                if !node.isCollapsed && node.hasBody {
                    bodyView
                }
            }
            .padding(.leading, 6)
            .opacity(isLockedByOtherWindow ? 0.5 : 1.0) // Dim locked nodes

            Spacer(minLength: 12)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            tryFocusNode()
        }
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
                    }
                }
            ),
            isFocused: isNodeFocused && !isLockedByOtherWindow,
            isLocked: isLockedByOtherWindow,
            isTaskCompleted: node.isTask && node.isTaskCompleted,
            hasNextNode: hasNextNode,
            placeholder: isOnlyNode && node.title.isEmpty ? placeholderText : nil,
            onFocusChange: { focused in
                if focused && !isNodeFocused {
                    tryFocusNode()
                }
            },
            onAction: handleAction,
            onSplitLine: { textAfter in
                document.createSiblingBelow(withTitle: textAfter)
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
            document.createSiblingAbove()
        case .createSiblingBelow:
            document.createSiblingBelow()
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
        case .deleteWithChildren:
            withAnimation(.easeOut(duration: 0.15)) {
                document.deleteFocusedWithChildren()
            }
        case .toggleTask:
            node.toggleTask()
        }
    }
    #endif

    @ViewBuilder
    private var bodyView: some View {
        Text(node.body)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .padding(.leading, 4)
            .padding(.top, 1)
    }
}

#Preview {
    @Previewable @State var document = OutlineDocument.createSample()
    @Previewable @State var zoomedNodeId: UUID? = nil
    @Previewable @State var fontSize: Double = 13.0

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
                    fontSize: $fontSize
                )
            }
        }
    }
    .frame(width: 400, height: 600)
}
