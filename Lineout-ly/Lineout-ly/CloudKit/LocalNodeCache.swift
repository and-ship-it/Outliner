//
//  LocalNodeCache.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation

/// JSON-based local cache that preserves OutlineNode UUIDs across app launches.
/// Markdown parsing regenerates UUIDs each time, so this cache is the source of
/// truth for node identity. Markdown is kept as a human-readable backup.
@MainActor
final class LocalNodeCache {
    static let shared = LocalNodeCache()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - File Paths

    /// Cache directory inside the app's Documents folder
    private var cacheDirectoryURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Lineout-ly-cache")
    }

    /// Cache file URL for a given week filename (e.g., "2026-Jan-W05.md" → "2026-Jan-W05.json")
    func cacheFileURL(for weekFileName: String) -> URL {
        let jsonName = weekFileName.replacingOccurrences(of: ".md", with: ".json")
        return cacheDirectoryURL.appendingPathComponent(jsonName)
    }

    /// Cache file URL for the current week
    var currentCacheFileURL: URL {
        let weekFile = iCloudManager.shared.currentWeekFileName
        return cacheFileURL(for: weekFile)
    }

    // MARK: - Save

    /// Save the node tree to the JSON cache
    func save(_ root: OutlineNode) throws {
        // Ensure cache directory exists
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }

        let codableRoot = CodableNode(from: root)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys] // Deterministic output for debugging

        let data = try encoder.encode(codableRoot)
        try data.write(to: currentCacheFileURL, options: .atomic)
        print("[Cache] Saved \(root.flattened().count) nodes to \(currentCacheFileURL.lastPathComponent)")
    }

    // MARK: - Load

    /// Load the node tree from the JSON cache. Returns nil if cache doesn't exist.
    func load() -> OutlineNode? {
        let url = currentCacheFileURL

        guard fileManager.fileExists(atPath: url.path) else {
            print("[Cache] No cache file at \(url.lastPathComponent)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let codableRoot = try decoder.decode(CodableNode.self, from: data)
            let root = codableRoot.toOutlineNode()
            print("[Cache] Loaded \(root.flattened().count) nodes from \(url.lastPathComponent)")
            return root
        } catch {
            print("[Cache] Failed to load cache: \(error)")
            return nil
        }
    }

    /// Load a specific week's node tree from the JSON cache.
    /// Returns nil if cache doesn't exist for that week.
    func load(for weekFileName: String) -> OutlineNode? {
        let url = cacheFileURL(for: weekFileName)

        guard fileManager.fileExists(atPath: url.path) else {
            print("[Cache] No cache file for \(weekFileName)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let codableRoot = try decoder.decode(CodableNode.self, from: data)
            let root = codableRoot.toOutlineNode()
            print("[Cache] Loaded \(root.flattened().count) nodes from \(url.lastPathComponent)")
            return root
        } catch {
            print("[Cache] Failed to load cache for \(weekFileName): \(error)")
            return nil
        }
    }

    /// Check if a cache file exists for the current week
    var hasCacheForCurrentWeek: Bool {
        fileManager.fileExists(atPath: currentCacheFileURL.path)
    }
}

// MARK: - Codable Node

/// A Codable representation of OutlineNode for JSON persistence.
/// Separates serialization concerns from the observable model.
struct CodableNode: Codable {
    let id: UUID
    var title: String
    var body: String
    var isCollapsed: Bool
    var isTask: Bool
    var isTaskCompleted: Bool
    var sortIndex: Int64
    var lastModifiedLocally: Date
    var cloudKitSystemFields: Data?
    var reminderIdentifier: String?
    var reminderListName: String?
    var reminderTimeHour: Int?
    var reminderTimeMinute: Int?
    var reminderChildType: String?
    var isReminderCompleted: Bool?
    var isUnseen: Bool?
    var isDateNode: Bool?
    var dateNodeDate: Date?
    var sectionType: String?
    var calendarEventIdentifier: String?
    var calendarName: String?
    var isPlaceholder: Bool?
    var children: [CodableNode]

    /// Create from an OutlineNode
    init(from node: OutlineNode) {
        self.id = node.id
        self.title = node.title
        self.body = node.body
        self.isCollapsed = node.isCollapsed
        self.isTask = node.isTask
        self.isTaskCompleted = node.isTaskCompleted
        self.sortIndex = node.sortIndex
        self.lastModifiedLocally = node.lastModifiedLocally
        self.cloudKitSystemFields = node.cloudKitSystemFields
        self.reminderIdentifier = node.reminderIdentifier
        self.reminderListName = node.reminderListName
        self.reminderTimeHour = node.reminderTimeHour
        self.reminderTimeMinute = node.reminderTimeMinute
        self.reminderChildType = node.reminderChildType
        self.isReminderCompleted = node.isReminderCompleted
        self.isUnseen = node.isUnseen
        self.isDateNode = node.isDateNode
        self.dateNodeDate = node.dateNodeDate
        self.sectionType = node.sectionType
        self.calendarEventIdentifier = node.calendarEventIdentifier
        self.calendarName = node.calendarName
        self.isPlaceholder = node.isPlaceholder
        self.children = node.children.map { CodableNode(from: $0) }
    }

    /// Convert back to an OutlineNode (with parent references set)
    func toOutlineNode() -> OutlineNode {
        let node = OutlineNode(
            id: id,
            title: title,
            body: body,
            isCollapsed: isCollapsed,
            isTask: isTask,
            isTaskCompleted: isTaskCompleted,
            children: children.map { $0.toOutlineNode() },
            sortIndex: sortIndex,
            lastModifiedLocally: lastModifiedLocally,
            cloudKitSystemFields: cloudKitSystemFields,
            reminderIdentifier: reminderIdentifier,
            reminderListName: reminderListName,
            reminderTimeHour: reminderTimeHour,
            reminderTimeMinute: reminderTimeMinute,
            reminderChildType: reminderChildType,
            isUnseen: isUnseen ?? false,
            isDateNode: isDateNode ?? false,
            dateNodeDate: dateNodeDate,
            sectionType: sectionType,
            calendarEventIdentifier: calendarEventIdentifier,
            calendarName: calendarName,
            isPlaceholder: isPlaceholder ?? false,
            isReminderCompleted: isReminderCompleted ?? false
        )
        return node
    }
}
