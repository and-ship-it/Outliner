//
//  BulletView.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

/// The bullet/disclosure indicator for a node
struct BulletView: View {
    let node: OutlineNode
    let isFocused: Bool
    var isCollapsed: Bool  // Per-tab collapse state (passed from parent)
    var scale: CGFloat = 1.0  // Scale factor for sizing
    var onTap: () -> Void = {}
    var onDoubleTap: () -> Void = {}  // iOS: double-tap to zoom into node

    // Base sizes (at scale 1.0)
    private let baseSize: CGFloat = 22
    private let baseBulletSize: CGFloat = 6
    private let baseChevronSize: CGFloat = 10

    // Scaled sizes
    private var size: CGFloat { baseSize * scale }
    private var bulletSize: CGFloat { baseBulletSize * scale }
    private var chevronSize: CGFloat { baseChevronSize * scale }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Highlight background when focused - warm amber glow
                if isFocused {
                    Circle()
                        .fill(AppTheme.focusHighlight)
                        .frame(width: size, height: size)
                }

                // The actual bullet/disclosure
                if node.hasChildren {
                    // Disclosure triangle - teal for structure, amber when focused
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: chevronSize, weight: .semibold))
                        .foregroundStyle(isFocused ? AppTheme.focusedChevron : AppTheme.chevron)
                } else {
                    // Simple bullet - coral for unfocused, amber for focused
                    Circle()
                        .fill(isFocused ? AppTheme.focusedBullet : AppTheme.bullet)
                        .frame(width: bulletSize, height: bulletSize)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .contentShape(Circle())
        #if os(iOS)
        // Double-tap gesture for zoom (iOS only)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onDoubleTap()
                }
        )
        #endif
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        // With children, expanded
        HStack {
            BulletView(
                node: {
                    let n = OutlineNode(title: "Parent")
                    n.addChild(OutlineNode(title: "Child"))
                    return n
                }(),
                isFocused: false,
                isCollapsed: false
            )
            Text("Has children, expanded")
        }

        // With children, collapsed
        HStack {
            BulletView(
                node: {
                    let n = OutlineNode(title: "Parent")
                    n.addChild(OutlineNode(title: "Child"))
                    return n
                }(),
                isFocused: false,
                isCollapsed: true
            )
            Text("Has children, collapsed")
        }

        // No children
        HStack {
            BulletView(
                node: OutlineNode(title: "Leaf"),
                isFocused: false,
                isCollapsed: false
            )
            Text("No children")
        }

        // Focused
        HStack {
            BulletView(
                node: OutlineNode(title: "Focused"),
                isFocused: true,
                isCollapsed: false
            )
            Text("Focused")
        }
    }
    .padding()
}
