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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        TrashBin.shared.remove(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        restoreItem(item)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
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
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    // MARK: - Restore

    private func restoreItem(_ item: TrashedItem) {
        guard let document = WindowManager.shared.document else { return }
        TrashBin.shared.restore(item, into: document)
    }

    // MARK: - Row

    @ViewBuilder
    private func trashItemRow(_ item: TrashedItem) -> some View {
        HStack {
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

            Spacer()

            // Restore button (always visible, especially useful on macOS where swipe is less natural)
            Button {
                restoreItem(item)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .help("Restore to outline")
        }
        .padding(.vertical, 2)
    }
}
