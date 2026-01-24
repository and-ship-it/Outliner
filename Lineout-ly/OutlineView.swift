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
    @State private var hasSetInitialFocus = false

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumbs (when zoomed)
            if document.zoomedNodeId != nil {
                BreadcrumbView(document: document)
                Divider()
            }

            // Zoomed node header (when zoomed)
            if let zoomed = document.zoomedNode {
                zoomedHeader(zoomed)
                Divider()
            }

            // Outline content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(nodesWithDepth, id: \.node.id) { item in
                            NodeRow(
                                document: document,
                                node: item.node,
                                effectiveDepth: item.depth
                            )
                            .id(item.node.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: document.focusedNodeId) { _, newId in
                    if let id = newId {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.textBackgroundColor)
        .focusedValue(\.document, document)
        .onAppear {
            // Set initial focus to first visible node when document opens
            if !hasSetInitialFocus, document.focusedNodeId == nil {
                if let firstNode = document.visibleNodes.first {
                    // Use a small delay to ensure the view hierarchy is fully established
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        document.focusedNodeId = firstNode.id
                    }
                }
                hasSetInitialFocus = true
            }
        }
    }

    // MARK: - Computed

    /// Visible nodes with their effective depth (accounting for zoom)
    /// Note: We reference structureVersion to ensure SwiftUI observes structural changes
    private var nodesWithDepth: [(node: OutlineNode, depth: Int)] {
        _ = document.structureVersion // Force observation of structural changes
        let zoomDepth = document.zoomedNode?.depth ?? 0
        return document.visibleNodes.map { node in
            (node: node, depth: max(0, node.depth - zoomDepth))
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func zoomedHeader(_ node: OutlineNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(node.title)
                .font(.title2)
                .fontWeight(.semibold)

            if node.hasBody {
                Text(node.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
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

    OutlineView(document: document)
        .frame(width: 500, height: 700)
}
