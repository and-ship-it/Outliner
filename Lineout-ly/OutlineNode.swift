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

    // MARK: - CloudKit Sync Properties

    /// Sibling order for CloudKit sync (gaps of 10000 for efficient insert)
    var sortIndex: Int64

    /// Timestamp of last local modification (for conflict resolution)
    var lastModifiedLocally: Date

    /// Encoded CKRecord system fields for partial CloudKit updates
    var cloudKitSystemFields: Data?

    // MARK: - Reminder Sync Properties

    /// The EKReminder calendarItemIdentifier for bidirectional sync.
    /// Non-nil means this node is synced with Apple Reminders.
    var reminderIdentifier: String?

    /// The Apple Reminders list name (e.g., "Personal", "Work").
    /// Displayed as grey suffix text in the UI.
    var reminderListName: String?

    // MARK: - Reminder Time Properties

    /// Hour component of the reminder's due time (0-23), nil if no time set.
    var reminderTimeHour: Int?

    /// Minute component of the reminder's due time (0-59), nil if no time set.
    var reminderTimeMinute: Int?

    // MARK: - Reminder Metadata Child Type

    /// Marks this node as an auto-generated metadata child of a reminder.
    /// Values: "note" (synced with reminder.notes) or "link" (synced with reminder.url).
    var reminderChildType: String?

    // MARK: - Unseen Node Tracking

    /// Whether this node was created externally (from Reminders or CloudKit sync)
    /// and hasn't been focused/seen by the user yet. Rendered in blue until seen.
    var isUnseen: Bool

    // MARK: - Date Node Properties

    /// Whether this node is a pinned date node in the weekly structure.
    /// Date nodes can't be deleted, reordered, or have their title edited.
    var isDateNode: Bool

    /// The calendar date this date node represents (nil for non-date nodes).
    /// Used to infer due dates for child reminder tasks.
    var dateNodeDate: Date?

    // MARK: - Computed Properties

    var hasChildren: Bool { !children.isEmpty }
    var hasBody: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isRoot: Bool { parent == nil }

    /// Formatted reminder time string (e.g., "9:00 AM"), nil if no time set.
    var formattedReminderTime: String? {
        guard let hour = reminderTimeHour, let minute = reminderTimeMinute else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else { return nil }
        return formatter.string(from: date)
    }

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
        children: [OutlineNode] = [],
        sortIndex: Int64 = 0,
        lastModifiedLocally: Date = Date(),
        cloudKitSystemFields: Data? = nil,
        reminderIdentifier: String? = nil,
        reminderListName: String? = nil,
        reminderTimeHour: Int? = nil,
        reminderTimeMinute: Int? = nil,
        reminderChildType: String? = nil,
        isUnseen: Bool = false,
        isDateNode: Bool = false,
        dateNodeDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isCollapsed = isCollapsed
        self.isTask = isTask
        self.isTaskCompleted = isTaskCompleted
        self.children = children
        self.sortIndex = sortIndex
        self.lastModifiedLocally = lastModifiedLocally
        self.cloudKitSystemFields = cloudKitSystemFields
        self.reminderIdentifier = reminderIdentifier
        self.reminderListName = reminderListName
        self.reminderTimeHour = reminderTimeHour
        self.reminderTimeMinute = reminderTimeMinute
        self.reminderChildType = reminderChildType
        self.isUnseen = isUnseen
        self.isDateNode = isDateNode
        self.dateNodeDate = dateNodeDate

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
            children: self.children.map { $0.deepCopy() },
            sortIndex: self.sortIndex,
            lastModifiedLocally: self.lastModifiedLocally,
            cloudKitSystemFields: self.cloudKitSystemFields,
            reminderIdentifier: self.reminderIdentifier,
            reminderListName: self.reminderListName,
            reminderTimeHour: self.reminderTimeHour,
            reminderTimeMinute: self.reminderTimeMinute,
            reminderChildType: self.reminderChildType,
            isDateNode: self.isDateNode,
            dateNodeDate: self.dateNodeDate
        )
        return copy
    }
}

// MARK: - Sort Index Assignment

extension OutlineNode {
    /// Gap between sort indices for efficient insertion
    static let sortIndexGap: Int64 = 10_000

    /// Assign sortIndex values to all children recursively using gaps
    func assignSortIndices() {
        for (i, child) in children.enumerated() {
            child.sortIndex = Int64(i) * OutlineNode.sortIndexGap
            child.assignSortIndices()
        }
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
