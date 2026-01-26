//
//  Theme.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import SwiftUI

/// App color theme using Apple HIG standard semantic colors
/// Colors adapt automatically to light/dark mode and system accent
enum AppTheme {

    // MARK: - Primary Colors (System Standard)

    /// System accent color - used for active/focused elements
    /// Maps to user's system accent color preference
    static let amber = Color.accentColor

    /// Secondary color for structural elements
    /// Used for: headers, links, tags, chevrons
    static let teal = Color.secondary

    /// Red for destructive actions (kept for compatibility)
    static let coral = Color.red

    // MARK: - Semantic Colors

    /// Focused bullet color - uses system accent
    static var focusedBullet: Color { Color.accentColor }

    /// Unfocused bullet color - subtle secondary
    static var bullet: Color { Color.secondary.opacity(0.6) }

    /// Chevron (expand/collapse) color
    static var chevron: Color { Color.secondary }

    /// Focused chevron color - uses system accent
    static var focusedChevron: Color { Color.accentColor }

    /// Focus ring/highlight background
    static var focusHighlight: Color { Color.accentColor.opacity(0.15) }

    /// Completed task - faded gray
    static var completed: Color { Color.gray.opacity(0.5) }

    /// Selection highlight
    static var selection: Color { Color.accentColor.opacity(0.15) }

    // MARK: - Text Colors

    /// Primary text
    static var textPrimary: Color {
        Color.primary
    }

    /// Secondary text (body, notes)
    static var textSecondary: Color {
        Color.secondary
    }

    /// Placeholder text
    static var textPlaceholder: Color {
        Color.secondary.opacity(0.5)
    }

    // MARK: - Adaptive Background

    /// Main background color (uses system background)
    static func background(for colorScheme: ColorScheme) -> Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    // MARK: - Selection & Highlight

    /// Selection indicator for multi-select
    static var liquidGlassSelection: Color {
        Color.accentColor.opacity(0.25)
    }

    /// Drop target highlight
    static var dropTargetHighlight: Color {
        Color.accentColor.opacity(0.4)
    }
}

// MARK: - Liquid Glass View Modifier (iOS)

#if os(iOS)
/// A view modifier that applies liquid glass styling
struct LiquidGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Glass background with blur
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Subtle inner glow
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(LiquidGlassStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

/// Floating pill button style for liquid glass UI
struct LiquidGlassPillStyle: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func liquidGlassPill(isSelected: Bool = false) -> some View {
        modifier(LiquidGlassPillStyle(isSelected: isSelected))
    }
}
#endif

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
