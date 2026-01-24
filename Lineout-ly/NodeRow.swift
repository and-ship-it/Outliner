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

    private let indentWidth: CGFloat = 20
    private let lineColor = Color.gray.opacity(0.3)

    var isNodeFocused: Bool {
        document.focusedNodeId == node.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left padding
            Spacer()
                .frame(width: 12)

            // Indentation with tree lines
            if effectiveDepth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<effectiveDepth, id: \.self) { level in
                        ZStack {
                            // Vertical line if there are more siblings at this level
                            if level < treeLines.count && treeLines[level] {
                                Rectangle()
                                    .fill(lineColor)
                                    .frame(width: 1)
                                    .offset(x: -indentWidth / 2 + 3)
                            }
                        }
                        .frame(width: indentWidth)
                    }
                }
            }

            // Horizontal connector line for children
            if effectiveDepth > 0 {
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 8, height: 1)
                    .offset(y: 10)
            }

            // Bullet
            BulletView(node: node, isFocused: isNodeFocused) {
                withAnimation(.easeOut(duration: 0.15)) {
                    document.toggleNode(node)
                }
            }
            .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                titleView
                    .fixedSize(horizontal: false, vertical: true)

                if !node.isCollapsed && node.hasBody {
                    bodyView
                }
            }
            .padding(.leading, 6)

            Spacer(minLength: 12)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
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
                set: { node.title = $0 }
            ),
            isFocused: isNodeFocused,
            onFocusChange: { focused in
                if focused && !isNodeFocused {
                    document.setFocus(node)
                }
            },
            onAction: handleAction,
            onSplitLine: { textAfter in
                document.createSiblingBelow(withTitle: textAfter)
            },
            fontWeight: effectiveDepth == 0 ? .medium : .regular
        )
        #else
        OutlineTextField(
            text: Binding(
                get: { node.title },
                set: { node.title = $0 }
            ),
            isFocused: isNodeFocused,
            onFocusChange: { focused in
                if focused && !isNodeFocused {
                    document.setFocus(node)
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
            withAnimation(.easeOut(duration: 0.2)) {
                document.zoomIn()
            }
        case .zoomOut:
            withAnimation(.easeOut(duration: 0.2)) {
                document.zoomOut()
            }
        case .zoomToRoot:
            withAnimation(.easeOut(duration: 0.2)) {
                document.zoomToRoot()
            }
        case .progressiveSelectDown:
            break
        case .deleteWithChildren:
            withAnimation(.easeOut(duration: 0.15)) {
                document.deleteFocusedWithChildren()
            }
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

    ScrollView {
        VStack(spacing: 0) {
            ForEach(document.visibleNodes) { node in
                NodeRow(
                    document: document,
                    node: node,
                    effectiveDepth: node.depth,
                    treeLines: []
                )
            }
        }
    }
    .frame(width: 400, height: 600)
}
