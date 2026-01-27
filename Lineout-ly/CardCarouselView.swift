//
//  CardCarouselView.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Masonry Tab Overview

/// Craft.do-inspired masonry grid of variable-height snippet cards
/// Two-column layout with organic card sizing based on content length
struct MasonryTabOverview: View {
    @Binding var isVisible: Bool
    let navigationHistory: NavigationHistoryManager
    let document: OutlineDocument
    let collapsedNodeIds: Set<UUID>
    let onSelectCard: (Int) -> Void
    var onRemoveCard: ((Int) -> Void)? = nil
    var onCreateCard: (() -> Void)? = nil
    @Binding var fontSize: Double
    @Binding var isFocusMode: Bool

    @State private var searchQuery: String = ""
    @State private var showingSettings: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    // Layout constants
    private let horizontalPadding: CGFloat = 16
    private let columnSpacing: CGFloat = 12
    private let cardSpacing: CGFloat = 12

    // MARK: - Masonry Distribution

    /// Card metadata for layout
    private struct MasonryCard: Identifiable {
        let id: Int // index in navigation history
        let zoomId: UUID?
    }

    /// Distribute cards into two columns using greedy masonry algorithm
    private var masonryColumns: (left: [MasonryCard], right: [MasonryCard]) {
        let allCards = navigationHistory.history.enumerated().map {
            MasonryCard(id: $0.offset, zoomId: $0.element)
        }

        let filtered: [MasonryCard]
        if searchQuery.isEmpty {
            filtered = allCards
        } else {
            filtered = allCards.filter { card in
                cardMatchesSearch(zoomId: card.zoomId, query: searchQuery)
            }
        }

        var left: [MasonryCard] = []
        var right: [MasonryCard] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for card in filtered {
            let height = estimatedCardHeight(zoomId: card.zoomId, isHome: card.id == 0)
            if leftHeight <= rightHeight {
                left.append(card)
                leftHeight += height + cardSpacing
            } else {
                right.append(card)
                rightHeight += height + cardSpacing
            }
        }

        return (left, right)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            #if os(iOS)
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { closeOverview() }
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif

            VStack(spacing: 0) {
                topBar
                searchBar
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 12)

                // Masonry grid
                ScrollView(.vertical, showsIndicators: true) {
                    let columns = masonryColumns
                    HStack(alignment: .top, spacing: columnSpacing) {
                        // Left column
                        VStack(spacing: cardSpacing) {
                            ForEach(columns.left) { card in
                                cardView(for: card)
                            }
                        }
                        .frame(width: cardColumnWidth)

                        // Right column
                        VStack(spacing: cardSpacing) {
                            ForEach(columns.right) { card in
                                cardView(for: card)
                            }
                        }
                        .frame(width: cardColumnWidth)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 80) // Space for FAB
                }
            }

            // Plus FAB (iOS)
            #if os(iOS)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        dismissKeyboard()
                        onCreateCard?()
                        closeOverview()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.accentColor))
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                }
            }
            #endif
        }
        .onAppear {
            #if os(iOS)
            dismissKeyboard()
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(fontSize: $fontSize, isFocusMode: $isFocusMode)
        }
        #endif
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button (X)
            Button {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
                closeOverview()
            } label: {
                Image(systemName: "xmark")
                    #if os(iOS)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                    #else
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
                    #endif
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif

            Spacer()

            #if os(macOS)
            // Plus button inline on macOS
            Button {
                onCreateCard?()
                closeOverview()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Circle())
            #endif

            // Settings button (three dots)
            Button {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                showingSettings = true
                #else
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                #endif
            } label: {
                Image(systemName: "ellipsis")
                    #if os(iOS)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                    #else
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
                    #endif
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, horizontalPadding + 4)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                #if os(iOS)
                .foregroundColor(.white.opacity(0.5))
                #else
                .foregroundColor(.secondary)
                #endif

            TextField("Search tabs...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                #if os(iOS)
                .foregroundColor(.white)
                .tint(.white)
                #endif

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        #if os(iOS)
                        .foregroundColor(.white.opacity(0.5))
                        #else
                        .foregroundColor(.secondary)
                        #endif
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                #if os(iOS)
                .fill(Color.white.opacity(0.15))
                #else
                .fill(Color.secondary.opacity(0.1))
                #endif
        )
    }

    // MARK: - Card Builder

    @ViewBuilder
    private func cardView(for card: MasonryCard) -> some View {
        let isHome = card.id == 0

        MasonryCardView(
            zoomId: card.zoomId,
            document: document,
            collapsedNodeIds: collapsedNodeIds,
            isHome: isHome,
            cardWidth: cardColumnWidth,
            onTap: {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isVisible = false
                }
                onSelectCard(card.id)
            },
            onClose: isHome ? nil : {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                #endif
                if navigationHistory.remove(at: card.id) {
                    onRemoveCard?(card.id)
                }
                if navigationHistory.cardCount <= 1 {
                    closeOverview()
                }
            }
        )
        #if os(macOS)
        .contextMenu {
            if !isHome && navigationHistory.cardCount > 1 {
                Button(role: .destructive) {
                    if navigationHistory.remove(at: card.id) {
                        onRemoveCard?(card.id)
                    }
                    if navigationHistory.cardCount <= 1 {
                        closeOverview()
                    }
                } label: {
                    Label("Close Tab", systemImage: "xmark")
                }
            }
        }
        #endif
    }

    // MARK: - Helpers

    private var cardColumnWidth: CGFloat {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - horizontalPadding * 2 - columnSpacing) / 2
        #else
        return 210
        #endif
    }

    private func closeOverview() {
        #if os(iOS)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isVisible = false
        }
        #else
        isVisible = false
        #endif
    }

    #if os(iOS)
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    /// Check if a card's content matches the search query
    private func cardMatchesSearch(zoomId: UUID?, query: String) -> Bool {
        let lowQuery = query.lowercased()
        let rootNode: OutlineNode
        if let id = zoomId, let node = document.root.find(id: id) {
            rootNode = node
            if rootNode.title.lowercased().contains(lowQuery) { return true }
        } else {
            rootNode = document.root
        }
        return searchChildrenRecursive(of: rootNode, query: lowQuery, depth: 0)
    }

    private func searchChildrenRecursive(of node: OutlineNode, query: String, depth: Int) -> Bool {
        guard depth < 5 else { return false }
        for child in node.children {
            if child.title.lowercased().contains(query) { return true }
            if searchChildrenRecursive(of: child, query: query, depth: depth + 1) { return true }
        }
        return false
    }

    /// Estimate card height for masonry distribution
    private func estimatedCardHeight(zoomId: UUID?, isHome: Bool) -> CGFloat {
        let nodeCount = previewNodeCount(zoomId: zoomId, maxNodes: isHome ? 20 : 15)
        let titleHeight: CGFloat = 44
        let dividerHeight: CGFloat = 1
        let contentPadding: CGFloat = 20
        let nodeRowHeight: CGFloat = 22
        let minHeight: CGFloat = 120
        let maxHeight: CGFloat = 500

        let estimated = titleHeight + dividerHeight + contentPadding + CGFloat(max(nodeCount, 2)) * nodeRowHeight + contentPadding
        return min(maxHeight, max(minHeight, estimated))
    }

    /// Count visible preview nodes for a zoom scope
    private func previewNodeCount(zoomId: UUID?, maxNodes: Int) -> Int {
        let rootNode: OutlineNode
        if let id = zoomId, let node = document.root.find(id: id) {
            rootNode = node
        } else {
            rootNode = document.root
        }

        var count = 0
        func traverse(_ node: OutlineNode) {
            guard count < maxNodes else { return }
            for child in node.children {
                count += 1
                guard count < maxNodes else { return }
                if !collapsedNodeIds.contains(child.id) && !child.children.isEmpty {
                    traverse(child)
                }
            }
        }
        traverse(rootNode)
        return count
    }
}

// MARK: - Masonry Card View

/// Variable-height card showing a scrollable preview of a zoomed view's content
/// Height adapts organically to the amount of content visible
struct MasonryCardView: View {
    let zoomId: UUID?
    let document: OutlineDocument
    let collapsedNodeIds: Set<UUID>
    let isHome: Bool
    let cardWidth: CGFloat
    let onTap: () -> Void
    let onClose: (() -> Void)?

    #if os(macOS)
    @State private var isHovered: Bool = false
    #endif

    @Environment(\.colorScheme) private var colorScheme

    /// Maximum preview nodes — home card gets more for organic sizing
    private var maxPreviewNodes: Int { isHome ? 20 : 15 }

    /// Title for this card
    private var title: String {
        guard let id = zoomId, let node = document.root.find(id: id) else {
            let weekName = iCloudManager.shared.currentWeekFileName.replacingOccurrences(of: ".md", with: "")
            return weekName.isEmpty ? "This Week" : weekName
        }

        var text = node.title
        if text.isEmpty, let firstChild = node.children.first {
            text = firstChild.title
        }
        if text.isEmpty { return "Untitled" }

        let words = text.split(separator: " ").prefix(5)
        return words.joined(separator: " ")
    }

    /// Get visible nodes with depth and tree lines, respecting collapsed state
    private var visibleNodesWithDepth: [(node: OutlineNode, depth: Int, treeLines: [Bool])] {
        var result: [(OutlineNode, Int, [Bool])] = []
        let rootNode: OutlineNode
        if let id = zoomId, let node = document.root.find(id: id) {
            rootNode = node
        } else {
            rootNode = document.root
        }

        func calculateTreeLines(for node: OutlineNode) -> [Bool] {
            var lines: [Bool] = []
            var current = node
            while let parent = current.parent {
                if parent.id == zoomId || parent.isRoot { break }
                let hasSiblingsBelow = current.nextSibling != nil
                lines.insert(hasSiblingsBelow, at: 0)
                current = parent
            }
            return lines
        }

        func traverse(_ node: OutlineNode, depth: Int) {
            guard result.count < maxPreviewNodes else { return }
            for child in node.children {
                let treeLines = calculateTreeLines(for: child)
                result.append((child, depth, treeLines))
                if !collapsedNodeIds.contains(child.id) && !child.children.isEmpty {
                    traverse(child, depth: depth + 1)
                }
            }
        }

        traverse(rootNode, depth: 0)
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar with optional close button
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let onClose = onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle().fill(Color.secondary.opacity(0.15))
                            )
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 10)

            // Content preview — variable height based on content
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(visibleNodesWithDepth.enumerated()), id: \.element.node.id) { _, item in
                    previewRow(node: item.node, depth: item.depth, treeLines: item.treeLines)
                }

                if visibleNodesWithDepth.isEmpty {
                    Text("No items")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.background(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        #if os(macOS)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        #endif
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap() }
    }

    // MARK: - Preview Row

    @ViewBuilder
    private func previewRow(node: OutlineNode, depth: Int, treeLines: [Bool]) -> some View {
        let hasChildren = !node.children.isEmpty
        let isCollapsed = collapsedNodeIds.contains(node.id)
        let indentWidth: CGFloat = 10
        let bulletSize: CGFloat = 8
        let treeLineOffset: CGFloat = bulletSize / 2

        HStack(alignment: .top, spacing: 0) {
            // Tree line indentation
            if depth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<depth, id: \.self) { level in
                        Color.clear
                            .frame(width: indentWidth)
                            .overlay(alignment: .topLeading) {
                                if level < treeLines.count && treeLines[level] {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 1, height: nil)
                                        .frame(maxHeight: .infinity)
                                        .offset(x: treeLineOffset - 0.5)
                                        .padding(.top, -3)
                                        .padding(.bottom, -3)
                                }
                            }
                    }
                }
            }

            // Chevron or bullet
            if hasChildren {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: bulletSize, height: bulletSize)
                    .padding(.top, 2)
            } else {
                Circle()
                    .fill(node.isTaskCompleted ? Color.gray.opacity(0.4) : Color.secondary.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .frame(width: bulletSize, height: bulletSize)
                    .padding(.top, 2)
            }

            // Title text
            Text(node.title.isEmpty ? "Empty" : node.title)
                .font(.system(size: 11))
                .foregroundColor(node.title.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .strikethrough(node.isTaskCompleted)
                .padding(.leading, 3)

            Spacer(minLength: 0)
        }
    }
}
