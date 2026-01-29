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

    // MARK: - Ensure Section Nodes

    /// Ensure "calendar" and "reminders" section headers exist under each date node.
    /// Calendar section at index 0, reminders at index 1 (initial position only — user can reorder).
    func ensureSectionNodes(in document: OutlineDocument) {
        var created = false

        for dateNode in document.root.children where dateNode.isDateNode {
            guard let date = dateNode.dateNodeDate else { continue }

            let calendarSectionId = Self.deterministicSectionUUID(for: date, sectionType: "calendar")
            let remindersSectionId = Self.deterministicSectionUUID(for: date, sectionType: "reminders")

            // Create calendar section if not present
            if !dateNode.children.contains(where: { $0.id == calendarSectionId }) {
                let calSection = OutlineNode(
                    id: calendarSectionId,
                    title: "calendar",
                    sectionType: "calendar"
                )
                dateNode.addChild(calSection, at: 0)
                created = true
            }

            // Create reminders section if not present
            if !dateNode.children.contains(where: { $0.id == remindersSectionId }) {
                let remSection = OutlineNode(
                    id: remindersSectionId,
                    title: "reminders",
                    sectionType: "reminders"
                )
                // Insert after calendar section (index 1) or at 0 if calendar isn't at 0
                let insertIdx = dateNode.children.firstIndex(where: { $0.id == calendarSectionId })
                    .map { $0 + 1 } ?? 1
                dateNode.addChild(remSection, at: min(insertIdx, dateNode.children.count))
                created = true
            }
        }

        if created {
            // Ensure placeholders for empty sections
            ensureAllPlaceholders(in: document)
            document.structureVersion += 1
            print("[DateStructure] Created section nodes under date nodes")
        }
    }

    // MARK: - Placeholder Management

    /// Ensure all section nodes have correct placeholder state.
    func ensureAllPlaceholders(in document: OutlineDocument) {
        for dateNode in document.root.children where dateNode.isDateNode {
            guard let date = dateNode.dateNodeDate else { continue }
            for section in dateNode.children where section.isSectionHeader {
                let sectionType = section.sectionType ?? "calendar"
                ensurePlaceholder(in: section, date: date, sectionType: sectionType)
            }
        }
    }

    /// Manage placeholder for a section:
    /// - If section has non-placeholder children → remove placeholder
    /// - If section has no non-placeholder children → add placeholder
    func ensurePlaceholder(in section: OutlineNode, date: Date, sectionType: String) {
        let placeholderId = Self.deterministicPlaceholderUUID(for: date, sectionType: sectionType)
        let hasRealChildren = section.children.contains(where: { !$0.isPlaceholder })
        let existingPlaceholder = section.children.first(where: { $0.id == placeholderId })

        if hasRealChildren {
            // Remove placeholder if it exists
            existingPlaceholder?.removeFromParent()
        } else if existingPlaceholder == nil {
            // Add placeholder
            let placeholderText = sectionType == "calendar"
                ? "no calendar events on this day"
                : "no reminders on this day"
            let placeholder = OutlineNode(
                id: placeholderId,
                title: placeholderText,
                isPlaceholder: true
            )
            section.addChild(placeholder)
        }
    }

    // MARK: - Migration

    /// One-time migration: move reminder nodes from directly under date nodes into "reminders" sections.
    func migrateRemindersIntoSections(in document: OutlineDocument) {
        var migrated = 0

        for dateNode in document.root.children where dateNode.isDateNode {
            guard let date = dateNode.dateNodeDate else { continue }
            let remindersSectionId = Self.deterministicSectionUUID(for: date, sectionType: "reminders")
            guard let remindersSection = dateNode.children.first(where: { $0.id == remindersSectionId }) else { continue }

            // Find reminder nodes directly under the date node (not under a section)
            let remindersToMove = dateNode.children.filter { node in
                node.reminderIdentifier != nil && node.sectionType == nil
            }

            for reminder in remindersToMove {
                reminder.removeFromParent()
                remindersSection.addChild(reminder)
                migrated += 1
            }
        }

        if migrated > 0 {
            ensureAllPlaceholders(in: document)
            document.structureVersion += 1
            print("[DateStructure] Migrated \(migrated) reminders into section containers")
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
