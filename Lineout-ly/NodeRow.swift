//
//  NodeRow.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

/// A single row in the outline, displaying a node with proper indentation
struct NodeRow: View {
    @Bindable var document: OutlineDocument
    let node: OutlineNode
    let effectiveDepth: Int

    private let indentWidth: CGFloat = 24
    private let rowMinHeight: CGFloat = 32

    var isNodeFocused: Bool {
        document.focusedNodeId == node.id
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Indentation
            if effectiveDepth > 0 {
                Spacer()
                    .frame(width: CGFloat(effectiveDepth) * indentWidth)
            }

            // Bullet
            BulletView(node: node, isFocused: isNodeFocused) {
                withAnimation(.easeOut(duration: 0.15)) {
                    document.toggleNode(node)
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in
                d[VerticalAlignment.center]
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                titleView

                // Body (if expanded and has body)
                if !node.isCollapsed && node.hasBody {
                    bodyView
                }
            }
            .padding(.leading, 8)

            Spacer(minLength: 0)
        }
        .frame(minHeight: rowMinHeight, alignment: .top)
        .padding(.vertical, 2)
        .padding(.horizontal, 16)
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
                // Create a new sibling below with the split text
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
            .padding(.top, 2)
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
                    effectiveDepth: node.depth
                )
            }
        }
    }
    .frame(width: 400, height: 600)
}
