//
//  NavigationHistoryManager.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import SwiftUI

/// Manages navigation history for Arc-style card carousel on iOS
/// Tracks zoom levels as a stack that can be navigated back/forward
@Observable
@MainActor
final class NavigationHistoryManager {
    /// Stack of zoom node IDs (nil = home/root)
    /// Index 0 is always home (nil), subsequent indices are zoom levels
    private(set) var history: [UUID?] = [nil]

    /// Current position in history (for back/forward navigation)
    private(set) var currentIndex: Int = 0

    /// Whether carousel is currently visible
    var isCarouselVisible: Bool = false

    /// Current zoom node ID
    var currentZoomId: UUID? {
        guard currentIndex >= 0 && currentIndex < history.count else { return nil }
        return history[currentIndex]
    }

    /// Number of cards in carousel
    var cardCount: Int { history.count }

    /// Can navigate back?
    var canGoBack: Bool { currentIndex > 0 }

    /// Can navigate forward?
    var canGoForward: Bool { currentIndex < history.count - 1 }

    /// Push a new zoom level (when zooming in via double-tap)
    func push(_ zoomId: UUID?) {
        // Remove any forward history when pushing new
        if currentIndex < history.count - 1 {
            history = Array(history.prefix(currentIndex + 1))
        }

        // Don't push duplicates
        guard history.last != zoomId else { return }

        // Don't push nil if already at home
        if zoomId == nil && history.last == nil { return }

        history.append(zoomId)
        currentIndex = history.count - 1
    }

    /// Pop to previous level (when zooming out via edge swipe)
    func pop() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    /// Navigate to specific index in history
    func navigateTo(index: Int) {
        guard index >= 0 && index < history.count else { return }
        currentIndex = index
    }

    /// Go home (navigate to index 0 which is nil/root)
    func goHome() {
        currentIndex = 0
    }

    /// Remove a card at specific index (swipe to dismiss)
    /// Returns false if can't remove (e.g., only one card left)
    @discardableResult
    func remove(at index: Int) -> Bool {
        // Must have at least home card
        guard history.count > 1, index >= 0 && index < history.count else { return false }

        // Don't allow removing home (index 0) if it's the only card
        // But we can remove home if there are other cards
        history.remove(at: index)

        // Adjust currentIndex if needed
        if currentIndex >= history.count {
            currentIndex = history.count - 1
        } else if currentIndex > index {
            currentIndex -= 1
        }

        return true
    }

    /// Clear history and start fresh (on session end)
    func clear() {
        history = [nil]
        currentIndex = 0
    }

    /// Sync with external zoom state (for initial load or external changes)
    func syncWithZoom(_ zoomId: UUID?) {
        // If zoom matches current, nothing to do
        if zoomId == currentZoomId { return }

        // If zoom is in history, navigate to it
        if let index = history.firstIndex(where: { $0 == zoomId }) {
            currentIndex = index
            return
        }

        // Otherwise push as new entry
        push(zoomId)
    }

    /// Check if a zoom ID already has a tab in history
    func hasTab(for zoomId: UUID?) -> Bool {
        return history.contains(where: { $0 == zoomId })
    }

    /// Navigate to existing tab for zoom ID, or push new if not exists
    /// Returns true if navigated to existing, false if pushed new
    @discardableResult
    func navigateOrPush(_ zoomId: UUID?) -> Bool {
        // If zoom is in history, navigate to it
        if let index = history.firstIndex(where: { $0 == zoomId }) {
            currentIndex = index
            return true
        }

        // Otherwise push as new entry
        push(zoomId)
        return false
    }
}
