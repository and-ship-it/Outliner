//
//  CardCarouselView.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import SwiftUI

#if os(iOS)
import UIKit

/// iOS App Switcher-style card view for navigation history
/// Cards are arranged horizontally like the iOS App Switcher
/// Swipe left/right to navigate, swipe up to dismiss
struct CardCarouselView: View {
    @Binding var isVisible: Bool
    let navigationHistory: NavigationHistoryManager
    let document: OutlineDocument
    let collapsedNodeIds: Set<UUID>  // Current collapse state to show real preview
    let onSelectCard: (Int) -> Void
    var onRemoveCard: ((Int) -> Void)? = nil
    var onCreateCard: (() -> Void)? = nil  // Callback to create new card/tab
    @Binding var fontSize: Double
    @Binding var isFocusMode: Bool

    // Carousel state
    @State private var selectedCardIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    // Card dismiss state (for swipe-up-to-remove)
    @State private var dismissingCardIndex: Int? = nil
    @State private var dismissOffset: CGFloat = 0

    // Settings sheet
    @State private var showingSettings: Bool = false

    // Toast message state
    @State private var showDismissedToast: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    // Screen dimensions
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var screenHeight: CGFloat { UIScreen.main.bounds.height }

    // Card dimensions - iOS App Switcher style (smaller cards)
    private var cardWidth: CGFloat { screenWidth * 0.72 }
    private var cardHeight: CGFloat { screenHeight * 0.55 }

    // Horizontal spacing between cards
    private let cardSpacing: CGFloat = 20
    private let scaleReduction: CGFloat = 0.08  // Scale reduction per card distance
    private let maxVisibleCards: Int = 5

    // Dismiss threshold
    private let dismissThreshold: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background - tap to close
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeCarousel()
                    }

                // Top bar with plus and settings buttons
                VStack {
                    HStack {
                        Spacer()

                        // Plus button to create new card
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            dismissKeyboard()
                            onCreateCard?()
                            closeCarousel()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        .padding(.trailing, 12)

                        // Settings button (three dots)
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            showingSettings = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 16)
                    Spacer()
                }
                .zIndex(2000)

                // Dismissed toast message
                if showDismissedToast {
                    VStack {
                        Spacer()
                        Text("Dismissed")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                            )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 100)
                    }
                    .zIndex(3000)
                }

                // Cards arranged horizontally
                ZStack {
                    ForEach(Array(navigationHistory.history.enumerated()), id: \.offset) { index, zoomId in
                        let relativeIndex = index - selectedCardIndex
                        let isBeingDismissed = dismissingCardIndex == index

                        CardPreviewView(
                            zoomId: zoomId,
                            document: document,
                            collapsedNodeIds: collapsedNodeIds,
                            isSelected: index == selectedCardIndex,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight
                        )
                        .offset(
                            x: cardXOffset(for: relativeIndex) + (isDragging && !isBeingDismissed ? dragOffset : 0),
                            y: isBeingDismissed ? dismissOffset : 0
                        )
                        .scaleEffect(cardScale(for: relativeIndex))
                        .opacity(isBeingDismissed ? max(0, 1.0 - abs(dismissOffset) / (dismissThreshold * 2)) : cardOpacity(for: relativeIndex))
                        .zIndex(cardZIndex(for: index))
                        .rotation3DEffect(
                            .degrees(card3DRotation(for: relativeIndex)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    // Determine if swiping up (dismiss) or horizontal (navigate)
                                    if index == selectedCardIndex && value.translation.height < -30 && abs(value.translation.height) > abs(value.translation.width) {
                                        // Swiping up - dismiss mode
                                        dismissingCardIndex = index
                                        dismissOffset = value.translation.height
                                    } else if dismissingCardIndex == nil {
                                        // Horizontal navigation drag
                                        isDragging = true
                                        dragOffset = value.translation.width
                                    } else if dismissingCardIndex == index {
                                        dismissOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if dismissingCardIndex == index {
                                        handleDismissEnd(value: value, index: index)
                                    } else {
                                        handleDragEnd(value: value)
                                    }
                                    isDragging = false
                                }
                        )
                        .onTapGesture {
                            if index == selectedCardIndex {
                                selectCard(at: index)
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedCardIndex = index
                                }
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                            }
                        }
                        .allowsHitTesting(abs(relativeIndex) <= 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedCardIndex = navigationHistory.currentIndex
            // Dismiss keyboard when carousel appears
            dismissKeyboard()
        }
        .onTapGesture {
            // Dismiss keyboard on any tap in the carousel area
            dismissKeyboard()
        }
        // Prevent keyboard from appearing
        .defersSystemGestures(on: .all)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(fontSize: $fontSize, isFocusMode: $isFocusMode)
        }
    }

    // MARK: - Card Positioning (iOS App Switcher style - horizontal)

    /// Horizontal offset for cards (left = previous, right = next)
    private func cardXOffset(for relativeIndex: Int) -> CGFloat {
        let baseOffset = CGFloat(relativeIndex) * (cardWidth * 0.85 + cardSpacing)
        return baseOffset
    }

    /// 3D rotation for depth effect
    private func card3DRotation(for relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            return 0
        }
        // Cards to left rotate slightly right, cards to right rotate slightly left
        let maxRotation: Double = 15
        let rotation = Double(relativeIndex) * -5
        return max(-maxRotation, min(maxRotation, rotation))
    }

    /// Scale for stacked cards
    private func cardScale(for relativeIndex: Int) -> CGFloat {
        let distance = abs(relativeIndex)
        return max(0.75, 1.0 - CGFloat(distance) * scaleReduction)
    }

    /// Opacity for stacked cards
    private func cardOpacity(for relativeIndex: Int) -> Double {
        let distance = abs(relativeIndex)
        if distance > maxVisibleCards {
            return 0
        }
        return max(0.4, 1.0 - Double(distance) * 0.12)
    }

    /// Z-index for proper layering (selected card on top)
    private func cardZIndex(for index: Int) -> Double {
        let distance = abs(index - selectedCardIndex)
        return Double(1000 - distance)
    }

    // MARK: - Gestures

    private func handleDragEnd(value: DragGesture.Value) {
        let threshold: CGFloat = 60
        let velocity = value.predictedEndTranslation.width - value.translation.width

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = 0

            // Swipe left = next card, swipe right = previous card
            if value.translation.width < -threshold || velocity < -300 {
                selectedCardIndex = min(navigationHistory.cardCount - 1, selectedCardIndex + 1)
            } else if value.translation.width > threshold || velocity > 300 {
                selectedCardIndex = max(0, selectedCardIndex - 1)
            }
        }

        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    private func handleDismissEnd(value: DragGesture.Value, index: Int) {
        let velocity = value.predictedEndTranslation.height - value.translation.height

        if value.translation.height < -dismissThreshold || velocity < -500 {
            // Dismiss keyboard immediately to prevent it from showing
            dismissKeyboard()

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                dismissOffset = -screenHeight
            }

            // Show dismissed toast
            withAnimation(.easeInOut(duration: 0.2)) {
                showDismissedToast = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if navigationHistory.remove(at: index) {
                    if selectedCardIndex >= navigationHistory.cardCount {
                        selectedCardIndex = max(0, navigationHistory.cardCount - 1)
                    }
                    onRemoveCard?(index)
                }

                dismissingCardIndex = nil
                dismissOffset = 0

                // Close carousel if only home card remains (or no cards)
                if navigationHistory.cardCount <= 1 {
                    closeCarousel()
                }
            }

            // Hide toast after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDismissedToast = false
                }
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dismissOffset = 0
                dismissingCardIndex = nil
            }
        }
    }

    /// Dismiss the keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func selectCard(at index: Int) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isVisible = false
        }
        onSelectCard(index)
    }

    private func closeCarousel() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isVisible = false
        }
    }
}

// MARK: - Card Preview View

/// Individual card showing a preview of the zoomed view
/// Shows the real collapsed/expanded state with proper indentation
struct CardPreviewView: View {
    let zoomId: UUID?
    let document: OutlineDocument
    let collapsedNodeIds: Set<UUID>
    let isSelected: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    /// Title for this card - shows first 5 words of content
    private var title: String {
        guard let id = zoomId, let node = document.root.find(id: id) else {
            // Root level: show week name (e.g., "2026-Jan-W05")
            let weekName = iCloudManager.shared.currentWeekFileName.replacingOccurrences(of: ".md", with: "")
            return weekName.isEmpty ? "This Week" : weekName
        }

        // Use node title if not empty
        var text = node.title

        // If node title is empty, try first child's title
        if text.isEmpty, let firstChild = node.children.first {
            text = firstChild.title
        }

        if text.isEmpty {
            return "Untitled"
        }

        // Get first 5 words
        let words = text.split(separator: " ").prefix(5)
        return words.joined(separator: " ")
    }

    /// Is this the home card?
    private var isHome: Bool { zoomId == nil }

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
                // Stop at zoom root or document root
                if parent.id == zoomId || parent.isRoot {
                    break
                }
                let hasSiblingsBelow = current.nextSibling != nil
                lines.insert(hasSiblingsBelow, at: 0)
                current = parent
            }
            return lines
        }

        func traverse(_ node: OutlineNode, depth: Int) {
            // Limit to prevent too many items
            guard result.count < 10 else { return }

            for child in node.children {
                let treeLines = calculateTreeLines(for: child)
                result.append((child, depth, treeLines))
                // Only traverse children if not collapsed
                if !collapsedNodeIds.contains(child.id) && !child.children.isEmpty {
                    traverse(child, depth: depth + 1)
                }
            }
        }

        traverse(rootNode, depth: 0)
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar - more compact
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            // Content preview showing real state
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(visibleNodesWithDepth.enumerated()), id: \.element.node.id) { _, item in
                    let node = item.node
                    let depth = item.depth
                    let treeLines = item.treeLines
                    let hasChildren = !node.children.isEmpty
                    let isCollapsed = collapsedNodeIds.contains(node.id)

                    // Preview row sizing constants
                    let indentWidth: CGFloat = 12
                    let bulletSize: CGFloat = 10
                    let treeLineOffset: CGFloat = bulletSize / 2  // Center line under bullet

                    HStack(alignment: .top, spacing: 0) {
                        // Tree lines with indentation
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
                                                    .padding(.top, -4)
                                                    .padding(.bottom, -4)
                                            }
                                        }
                                }
                            }
                        }

                        // Chevron or bullet
                        if hasChildren {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                                .frame(width: bulletSize, height: bulletSize)
                                .padding(.top, 3)
                        } else {
                            Circle()
                                .fill(node.isTaskCompleted ? Color.gray.opacity(0.4) : Color.secondary.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .frame(width: bulletSize, height: bulletSize)
                                .padding(.top, 3)
                        }

                        Text(node.title.isEmpty ? "Empty" : node.title)
                            .font(.system(size: 13))
                            .foregroundColor(node.title.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .strikethrough(node.isTaskCompleted)
                            .padding(.leading, 4)

                        Spacer()
                    }
                }

                if visibleNodesWithDepth.isEmpty {
                    Text("No items")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.background(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.gray.opacity(0.15),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: .black.opacity(0.35),
            radius: 15,
            x: 0,
            y: 8
        )
    }
}
#endif

// MARK: - macOS Card Carousel View

#if os(macOS)
/// macOS version of the tab switcher - displayed as a sheet
struct MacOSCardCarouselView: View {
    @Binding var isVisible: Bool
    let navigationHistory: NavigationHistoryManager
    let document: OutlineDocument
    let collapsedNodeIds: Set<UUID>
    let onSelectCard: (Int) -> Void
    var onRemoveCard: ((Int) -> Void)? = nil
    var onCreateCard: (() -> Void)? = nil

    @State private var selectedCardIndex: Int = 0
    @State private var hoveredCardIndex: Int? = nil

    @Environment(\.colorScheme) private var colorScheme

    private let cardWidth: CGFloat = 160
    private let cardHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tabs")
                    .font(.headline)

                Spacer()

                // Plus button to create new tab
                Button {
                    onCreateCard?()
                    isVisible = false
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())

                // Close button
                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Cards grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth + 20), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(navigationHistory.history.enumerated()), id: \.offset) { index, zoomId in
                        MacOSCardPreviewView(
                            zoomId: zoomId,
                            document: document,
                            collapsedNodeIds: collapsedNodeIds,
                            isSelected: index == selectedCardIndex,
                            isHovered: index == hoveredCardIndex,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight
                        )
                        .onTapGesture {
                            selectedCardIndex = index
                            onSelectCard(index)
                            isVisible = false
                        }
                        .onHover { hovering in
                            hoveredCardIndex = hovering ? index : nil
                        }
                        .contextMenu {
                            if navigationHistory.cardCount > 1 {
                                Button(role: .destructive) {
                                    if navigationHistory.remove(at: index) {
                                        if selectedCardIndex >= navigationHistory.cardCount {
                                            selectedCardIndex = max(0, navigationHistory.cardCount - 1)
                                        }
                                        onRemoveCard?(index)
                                    }
                                } label: {
                                    Label("Close Tab", systemImage: "xmark")
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedCardIndex = navigationHistory.currentIndex
        }
    }
}

/// macOS card preview (smaller, grid-friendly)
struct MacOSCardPreviewView: View {
    let zoomId: UUID?
    let document: OutlineDocument
    let collapsedNodeIds: Set<UUID>
    let isSelected: Bool
    let isHovered: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var title: String {
        guard let id = zoomId, let node = document.root.find(id: id) else {
            let weekName = iCloudManager.shared.currentWeekFileName.replacingOccurrences(of: ".md", with: "")
            return weekName.isEmpty ? "This Week" : weekName
        }
        return node.title.isEmpty ? "Untitled" : String(node.title.prefix(20))
    }

    private var isHome: Bool { zoomId == nil }

    /// Get visible nodes with depth and tree lines for preview
    private var previewNodesWithDepth: [(node: OutlineNode, depth: Int, treeLines: [Bool])] {
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
            guard result.count < 4 else { return }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 8)

            // Preview content with tree lines
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(previewNodesWithDepth.enumerated()), id: \.element.node.id) { _, item in
                    let node = item.node
                    let depth = item.depth
                    let treeLines = item.treeLines
                    let indentWidth: CGFloat = 8
                    let bulletSize: CGFloat = 8
                    let treeLineOffset: CGFloat = bulletSize / 2

                    HStack(spacing: 0) {
                        // Tree lines with indentation
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

                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .frame(width: bulletSize, height: bulletSize)

                        Text(node.title.isEmpty ? "Empty" : node.title)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundColor(node.title.isEmpty ? .secondary : .primary)
                            .padding(.leading, 4)
                    }
                }

                if previewNodesWithDepth.isEmpty {
                    Text("No items")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .italic()
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.background(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovered ? Color.secondary.opacity(0.3) : Color.gray.opacity(0.15),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
#endif
