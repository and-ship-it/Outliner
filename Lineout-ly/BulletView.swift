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
                // Highlight background when focused
                if isFocused {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: size, height: size)
                }

                // The actual bullet/disclosure
                if node.hasChildren {
                    // Disclosure triangle
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: chevronSize, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)
                } else {
                    // Simple bullet
                    Circle()
                        .fill(isFocused ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: bulletSize, height: bulletSize)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .contentShape(Circle())
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
