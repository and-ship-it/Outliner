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
    var onTap: () -> Void = {}

    private let size: CGFloat = 22
    private let bulletSize: CGFloat = 6

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
                    Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
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
                isFocused: false
            )
            Text("Has children, expanded")
        }

        // With children, collapsed
        HStack {
            BulletView(
                node: {
                    let n = OutlineNode(title: "Parent")
                    n.addChild(OutlineNode(title: "Child"))
                    n.isCollapsed = true
                    return n
                }(),
                isFocused: false
            )
            Text("Has children, collapsed")
        }

        // No children
        HStack {
            BulletView(
                node: OutlineNode(title: "Leaf"),
                isFocused: false
            )
            Text("No children")
        }

        // Focused
        HStack {
            BulletView(
                node: OutlineNode(title: "Focused"),
                isFocused: true
            )
            Text("Focused")
        }
    }
    .padding()
}
