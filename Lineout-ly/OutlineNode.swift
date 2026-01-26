//
//  OutlineNode.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation

@Observable
final class OutlineNode: Identifiable, @unchecked Sendable {
    let id: UUID
    var title: String
    var body: String
    var isCollapsed: Bool
    var isTask: Bool
    var isTaskCompleted: Bool
    var children: [OutlineNode]
    weak var parent: OutlineNode?

    // MARK: - Computed Properties

    var hasChildren: Bool { !children.isEmpty }
    var hasBody: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isRoot: Bool { parent == nil }

    var depth: Int {
        var count = 0
        var current = parent
        while current != nil {
            count += 1
            current = current?.parent
        }
        return count
    }

    var indexInParent: Int? {
        parent?.children.firstIndex(where: { $0.id == id })
    }

    var previousSibling: OutlineNode? {
        guard let index = indexInParent, index > 0 else { return nil }
        return parent?.children[index - 1]
    }

    var nextSibling: OutlineNode? {
        guard let index = indexInParent,
              let siblings = parent?.children,
              index < siblings.count - 1 else { return nil }
        return siblings[index + 1]
    }

    var firstChild: OutlineNode? {
        children.first
    }

    var lastChild: OutlineNode? {
        children.last
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        isCollapsed: Bool = false,
        isTask: Bool = false,
        isTaskCompleted: Bool = false,
        children: [OutlineNode] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isCollapsed = isCollapsed
        self.isTask = isTask
        self.isTaskCompleted = isTaskCompleted
        self.children = children

        // Set parent references for children
        for child in children {
            child.parent = self
        }
    }

    // MARK: - Tree Operations

    func addChild(_ node: OutlineNode, at index: Int? = nil) {
        node.parent = self
        if let index = index, index < children.count {
            children.insert(node, at: index)
        } else {
            children.append(node)
        }
    }

    func removeFromParent() {
        guard let parent = parent, let index = indexInParent else { return }
        parent.children.remove(at: index)
        self.parent = nil
    }

    func insertSiblingBelow(_ node: OutlineNode) {
        guard let parent = parent, let index = indexInParent else { return }
        node.parent = parent
        parent.children.insert(node, at: index + 1)
    }

    func insertSiblingAbove(_ node: OutlineNode) {
        guard let parent = parent, let index = indexInParent else { return }
        node.parent = parent
        parent.children.insert(node, at: index)
    }

    // MARK: - Traversal

    /// Returns all visible nodes in document order (respecting collapse state)
    func flattenedVisible() -> [OutlineNode] {
        var result: [OutlineNode] = []

        for child in children {
            result.append(child)
            if !child.isCollapsed {
                result.append(contentsOf: child.flattenedVisible())
            }
        }

        return result
    }

    /// Returns all nodes in document order (ignoring collapse state)
    func flattened() -> [OutlineNode] {
        var result: [OutlineNode] = []

        for child in children {
            result.append(child)
            result.append(contentsOf: child.flattened())
        }

        return result
    }

    /// Find a node by ID in this subtree
    func find(id: UUID) -> OutlineNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.find(id: id) {
                return found
            }
        }
        return nil
    }

    /// Check if this node is an ancestor of another node
    func isAncestor(of node: OutlineNode) -> Bool {
        var current = node.parent
        while current != nil {
            if current?.id == self.id { return true }
            current = current?.parent
        }
        return false
    }

    /// Check if this node is a descendant of another node
    func isDescendant(of node: OutlineNode) -> Bool {
        return node.isAncestor(of: self)
    }

    /// Get path from root to this node
    func pathFromRoot() -> [OutlineNode] {
        var path: [OutlineNode] = []
        var current: OutlineNode? = self
        while let node = current {
            path.insert(node, at: 0)
            current = node.parent
        }
        return path
    }

    // MARK: - Toggle

    func toggle() {
        isCollapsed.toggle()
    }

    func expand() {
        isCollapsed = false
    }

    func collapse() {
        isCollapsed = true
    }

    func expandAll() {
        isCollapsed = false
        for child in children {
            child.expandAll()
        }
    }

    func collapseAll() {
        isCollapsed = true
        for child in children {
            child.collapseAll()
        }
    }

    // MARK: - Task

    /// Cycles through: normal bullet → task (uncompleted) → task (completed) → normal bullet
    func toggleTask() {
        if !isTask {
            // Normal → Task (uncompleted)
            isTask = true
            isTaskCompleted = false
        } else if !isTaskCompleted {
            // Task (uncompleted) → Task (completed)
            isTaskCompleted = true
        } else {
            // Task (completed) → Normal
            isTask = false
            isTaskCompleted = false
        }
    }

    func toggleTaskCompleted() {
        if isTask {
            isTaskCompleted.toggle()
        }
    }
}

// MARK: - Deep Copy

extension OutlineNode {
    /// Creates a deep copy of this node and all its children (preserving IDs)
    func deepCopy() -> OutlineNode {
        let copy = OutlineNode(
            id: self.id,
            title: self.title,
            body: self.body,
            isCollapsed: self.isCollapsed,
            isTask: self.isTask,
            isTaskCompleted: self.isTaskCompleted,
            children: self.children.map { $0.deepCopy() }
        )
        return copy
    }
}

// MARK: - Equatable (by identity)

extension OutlineNode: Equatable {
    static func == (lhs: OutlineNode, rhs: OutlineNode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension OutlineNode: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
