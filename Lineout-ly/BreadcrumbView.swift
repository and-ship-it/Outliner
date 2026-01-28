//
//  BreadcrumbView.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

/// Navigation breadcrumbs showing path to current zoom level
struct BreadcrumbView: View {
    @Bindable var document: OutlineDocument

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Root button
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        document.zoomToRoot()
                    }
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13))
                        .foregroundStyle(document.zoomedNodeId == nil ? .primary : .secondary)
                }
                .buttonStyle(.plain)

                // Breadcrumb items
                ForEach(document.breadcrumbs) { node in
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                document.zoomTo(node)
                            }
                        } label: {
                            Text(node.title)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Current zoom level (if zoomed)
                if let zoomed = document.zoomedNode {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        Text(zoomed.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

#Preview {
    @Previewable @State var document = OutlineDocument.createSample()

    VStack(spacing: 0) {
        BreadcrumbView(document: document)
    }
}
