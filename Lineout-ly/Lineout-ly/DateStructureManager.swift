//
//  DateStructureManager.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CryptoKit

/// Manages the auto-generated 7-day date structure at root level of the weekly document.
/// Date nodes are pinned: can't be deleted, reordered, or have their title edited.
@Observable
@MainActor
final class DateStructureManager {
    static let shared = DateStructureManager()

    /// Fixed namespace for deterministic UUID generation.
    /// All devices use this same namespace so the same date always produces the same UUID.
    private static let uuidNamespace = "lineout-ly-date-node"

    private let calendar = Calendar.current

    private init() {}

    // MARK: - Deterministic UUID

    /// Generate a deterministic UUID for a given date.
    /// Uses SHA256 hash of a fixed namespace + ISO 8601 date string.
    /// This ensures the same date always gets the same UUID on all devices.
    static func deterministicUUID(for date: Date) -> UUID {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: startOfDay)

        let input = "\(uuidNamespace):\(dateString)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(hash)

        // Take first 16 bytes of SHA256 hash and form a UUID
        var uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        // Set version 4 (random) bits to make it a valid UUID format
        uuidBytes.6 = (uuidBytes.6 & 0x0F) | 0x40 // Version 4
        uuidBytes.8 = (uuidBytes.8 & 0x3F) | 0x80 // Variant 1
        return UUID(uuid: uuidBytes)
    }

    // MARK: - Week Date Computation

    /// Return the 7 dates for the current week based on weekStartDay setting.
    func currentWeekDates() -> [Date] {
        let today = Date()
        let weekStartDay = SettingsManager.shared.weekStartDayValue

        // Calendar.firstWeekday uses 1=Sunday, 2=Monday, etc. — matches WeekStartDay.rawValue
        let startDayOfWeek = weekStartDay.rawValue
        let currentWeekday = calendar.component(.weekday, from: today)

        // Calculate days to subtract to reach start of week
        let daysToSubtract = (currentWeekday - startDayOfWeek + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: today))!

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }

    // MARK: - Date Node Title

    /// Format a date as "Mon Jan 26" for the date node title
    private func dateNodeTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Ensure Date Nodes Exist

    /// Ensure 7 date nodes exist for the current week.
    /// Creates missing date nodes and maintains their calendar order.
    /// Non-date root nodes are preserved in their relative positions.
    func ensureDateNodes(in document: OutlineDocument) {
        let weekDates = currentWeekDates()

        // Build a set of existing date node dates (by start-of-day)
        let existingDateNodes = document.root.children.filter { $0.isDateNode }
        let existingDates = Set(existingDateNodes.compactMap { node -> Date? in
            guard let d = node.dateNodeDate else { return nil }
            return calendar.startOfDay(for: d)
        })

        // Create any missing date nodes
        var created = false
        for date in weekDates {
            let startOfDay = calendar.startOfDay(for: date)
            if !existingDates.contains(startOfDay) {
                let node = createDateNode(for: date)
                document.root.addChild(node)
                created = true
            }
        }

        // Sort date nodes into calendar order while preserving free node positions
        if created || needsReorder(document: document, weekDates: weekDates) {
            sortDateNodes(in: document, weekDates: weekDates)
        }

        if created {
            document.structureVersion += 1
        }
    }

    /// Create a date node with deterministic UUID and formatted title
    private func createDateNode(for date: Date) -> OutlineNode {
        let id = Self.deterministicUUID(for: date)
        return OutlineNode(
            id: id,
            title: dateNodeTitle(for: date),
            isDateNode: true,
            dateNodeDate: calendar.startOfDay(for: date)
        )
    }

    // MARK: - Sort Date Nodes

    /// Check if date nodes are out of calendar order
    private func needsReorder(document: OutlineDocument, weekDates: [Date]) -> Bool {
        let dateNodes = document.root.children.filter { $0.isDateNode }
        guard dateNodes.count == weekDates.count else { return true }

        // Check that date nodes are in calendar order (ignoring free nodes between them)
        var lastDate: Date?
        for node in dateNodes {
            guard let nodeDate = node.dateNodeDate else { continue }
            if let last = lastDate, nodeDate < last {
                return true
            }
            lastDate = nodeDate
        }
        return false
    }

    /// Sort date nodes into calendar order, preserving free nodes in their relative positions.
    /// Free nodes stay "attached" to the date node they precede or follow.
    private func sortDateNodes(in document: OutlineDocument, weekDates: [Date]) {
        let allChildren = document.root.children

        // Separate date nodes and free nodes
        var dateNodeMap: [Date: OutlineNode] = [:]
        var freeNodes: [(node: OutlineNode, afterDate: Date?)] = []
        var currentDateContext: Date? = nil

        for child in allChildren {
            if child.isDateNode, let date = child.dateNodeDate {
                dateNodeMap[calendar.startOfDay(for: date)] = child
                currentDateContext = calendar.startOfDay(for: date)
            } else {
                freeNodes.append((node: child, afterDate: currentDateContext))
            }
        }

        // Rebuild children: date nodes in order, with free nodes placed after their context date
        var newChildren: [OutlineNode] = []

        // First, add free nodes that have no date context (they come before all dates)
        for (node, afterDate) in freeNodes where afterDate == nil {
            newChildren.append(node)
        }

        // Then interleave date nodes and their free nodes
        for date in weekDates {
            let startOfDay = calendar.startOfDay(for: date)
            if let dateNode = dateNodeMap[startOfDay] {
                newChildren.append(dateNode)
            }
            // Add free nodes that belong after this date
            for (node, afterDate) in freeNodes where afterDate == startOfDay {
                newChildren.append(node)
            }
        }

        // Replace children (keeping parent refs correct)
        document.root.children = newChildren
        for child in newChildren {
            child.parent = document.root
        }
    }

    // MARK: - Deterministic Section/Placeholder UUIDs

    /// Generate a deterministic UUID for a section node (calendar or reminders) under a date.
    static func deterministicSectionUUID(for date: Date, sectionType: String) -> UUID {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: startOfDay)

        let input = "lineout-ly-section:\(dateString):\(sectionType)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(hash)

        var uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        uuidBytes.6 = (uuidBytes.6 & 0x0F) | 0x40
        uuidBytes.8 = (uuidBytes.8 & 0x3F) | 0x80
        return UUID(uuid: uuidBytes)
    }

    /// Generate a deterministic UUID for a placeholder node under a section.
    static func deterministicPlaceholderUUID(for date: Date, sectionType: String) -> UUID {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: startOfDay)

        let input = "lineout-ly-placeholder:\(dateString):\(sectionType)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(hash)

        var uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        uuidBytes.6 = (uuidBytes.6 & 0x0F) | 0x40
        uuidBytes.8 = (uuidBytes.8 & 0x3F) | 0x80
        return UUID(uuid: uuidBytes)
    }

    // MARK: - Migration: Flatten Sections to Direct Children

    /// Migrate from section-based structure to flat structure.
    /// Moves all children from calendar/reminders sections up to the date node,
    /// removes section headers and placeholders.
    func migrateSectionsToFlatStructure(in document: OutlineDocument) {
        var migrated = 0

        for dateNode in document.root.children where dateNode.isDateNode {
            let sectionNodes = dateNode.children.filter { $0.isSectionHeader }
            guard !sectionNodes.isEmpty else { continue }

            for section in sectionNodes {
                // Move real children (non-placeholder) up to date node
                let realChildren = section.children.filter { !$0.isPlaceholder }
                for child in realChildren {
                    child.removeFromParent()
                    dateNode.addChild(child)
                }
                // Remove the section node itself (and any placeholders inside)
                section.removeFromParent()
                migrated += 1
            }
        }

        if migrated > 0 {
            document.structureVersion += 1
            print("[DateStructure] Migrated \(migrated) sections to flat structure")
        }
    }

    // MARK: - Time-Based Sorting

    /// Sort all date node children by time (synced items first by time, user bullets last).
    func sortAllDateNodeChildrenByTime(in document: OutlineDocument) {
        for dateNode in document.root.children where dateNode.isDateNode {
            sortChildrenByTime(of: dateNode)
        }
    }

    /// Sort children of a date node by time.
    /// Order: all-day events → timed items by time → no-time reminders → user bullets.
    func sortChildrenByTime(of dateNode: OutlineNode) {
        let sorted = dateNode.children.sorted { a, b in
            timeScore(for: a) < timeScore(for: b)
        }
        dateNode.children = sorted
        for child in sorted { child.parent = dateNode }
    }

    /// Compute a sort score for ordering within a date node.
    private func timeScore(for node: OutlineNode) -> Int {
        // Calendar events: use sortIndex set by CalendarSyncEngine (already time-ordered)
        if node.isCalendarEvent {
            // All-day events have sortIndex 0, timed events > 0
            return Int(node.sortIndex)
        }
        // Reminders with time
        if node.reminderIdentifier != nil {
            if let h = node.reminderTimeHour, let m = node.reminderTimeMinute {
                // Offset by 10000 so reminders at same time as events appear after events
                return 10000 + h * 60 + m
            }
            // No-time reminders after timed items
            return 20000
        }
        // User-created bullets last
        return 30000
    }

    // MARK: - Remove Synced Items

    /// Remove all calendar event nodes from the document (called when calendar integration is disabled).
    func removeAllCalendarEvents(in document: OutlineDocument) {
        var removed = 0
        for dateNode in document.root.children where dateNode.isDateNode {
            let calendarNodes = dateNode.children.filter { $0.isCalendarEvent }
            for node in calendarNodes {
                node.removeFromParent()
                removed += 1
            }
        }
        if removed > 0 {
            document.structureVersion += 1
            print("[DateStructure] Removed \(removed) calendar events (integration disabled)")
        }
    }

    /// Remove all reminder nodes from the document (called when reminder integration is disabled).
    func removeAllReminders(in document: OutlineDocument) {
        var removed = 0
        for dateNode in document.root.children where dateNode.isDateNode {
            let reminderNodes = dateNode.children.filter { $0.reminderIdentifier != nil }
            for node in reminderNodes {
                node.removeFromParent()
                removed += 1
            }
        }
        if removed > 0 {
            document.structureVersion += 1
            print("[DateStructure] Removed \(removed) reminders (integration disabled)")
        }
    }

    // MARK: - Lookup Helpers

    /// Find the date node for a given date
    func dateNode(for date: Date, in document: OutlineDocument) -> OutlineNode? {
        let target = calendar.startOfDay(for: date)
        return document.root.children.first { node in
            node.isDateNode && node.dateNodeDate.map { calendar.startOfDay(for: $0) == target } ?? false
        }
    }

    /// Find today's date node
    func todayDateNode(in document: OutlineDocument) -> OutlineNode? {
        dateNode(for: Date(), in: document)
    }

    /// Walk up the tree to find the closest ancestor date node's date.
    /// Used to infer due dates for reminder tasks.
    func inferredDueDate(for node: OutlineNode) -> Date? {
        var current: OutlineNode? = node
        while let n = current {
            if n.isDateNode, let date = n.dateNodeDate {
                return date
            }
            current = n.parent
        }
        return nil
    }
}
