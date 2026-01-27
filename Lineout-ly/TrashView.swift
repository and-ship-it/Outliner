//
//  TrashView.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import SwiftUI

/// Displays trashed items, optionally filtered by week
struct TrashView: View {
    @Binding var isVisible: Bool
    var weekFilter: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var items: [TrashedItem] {
        if let week = weekFilter {
            return TrashBin.shared.items(for: week)
        }
        return TrashBin.shared.items
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Trash is Empty",
                        systemImage: "trash",
                        description: Text("Deleted bullets will appear here.")
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            trashItemRow(item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Trash")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isVisible = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func trashItemRow(_ item: TrashedItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? "Empty" : item.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(item.deletedAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if !item.weekFileName.isEmpty {
                    Text(item.weekFileName.replacingOccurrences(of: ".md", with: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if !item.children.isEmpty {
                Text("\(item.children.count) sub-items")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
