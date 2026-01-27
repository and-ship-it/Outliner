//
//  TrashBin.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation

/// Represents a deleted item in the trash
struct TrashedItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let body: String
    let children: [TrashedItem]
    let deletedAt: Date
    let originalDepth: Int
    let weekFileName: String

    enum CodingKeys: String, CodingKey {
        case id, title, body, children, deletedAt, originalDepth, weekFileName
    }

    init(from node: OutlineNode, depth: Int = 0) {
        self.id = UUID()
        self.title = node.title
        self.body = node.body
        self.children = node.children.map { TrashedItem(from: $0, depth: depth + 1) }
        self.deletedAt = Date()
        self.originalDepth = depth
        self.weekFileName = iCloudManager.shared.currentWeekFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        children = try container.decode([TrashedItem].self, forKey: .children)
        deletedAt = try container.decode(Date.self, forKey: .deletedAt)
        originalDepth = try container.decode(Int.self, forKey: .originalDepth)
        weekFileName = try container.decodeIfPresent(String.self, forKey: .weekFileName) ?? ""
    }
}

/// Manages the trash bin - stores deleted items and persists to markdown
@Observable
@MainActor
final class TrashBin {
    static let shared = TrashBin()

    private(set) var items: [TrashedItem] = []

    private let dateFormatter: DateFormatter
    private let trashFileName = "trash.md"

    /// Get the trash file URL - prefers iCloud, falls back to local
    private var trashFileURL: URL {
        // Try iCloud first
        if let trashFolder = iCloudManager.shared.trashFolderURL {
            return trashFolder.appendingPathComponent(trashFileName)
        }
        // Fall back to local
        return localTrashFileURL
    }

    /// Local fallback URL
    private var localTrashFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Lineout-ly").appendingPathComponent(trashFileName)
    }

    private init() {
        // Set up date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Load existing trash after a brief delay to allow iCloud to initialize
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            await loadFromFile()
        }
    }

    // MARK: - Public Methods

    /// Add a node and all its children to the trash
    func trash(_ node: OutlineNode) {
        let trashedItem = TrashedItem(from: node)
        items.insert(trashedItem, at: 0) // Most recent first
        Task {
            await saveToFile()
        }
    }

    /// Clear all items from trash (permanent delete)
    func emptyTrash() {
        items.removeAll()
        Task {
            await saveToFile()
        }
    }

    /// Remove a specific item from trash
    func remove(_ item: TrashedItem) {
        items.removeAll { $0.id == item.id }
        Task {
            await saveToFile()
        }
    }

    /// Items for a specific week
    func items(for weekFileName: String) -> [TrashedItem] {
        items.filter { $0.weekFileName == weekFileName }
    }

    // MARK: - Persistence

    private func saveToFile() async {
        let markdown = generateMarkdown()
        let fileURL = trashFileURL

        // Ensure parent directory exists
        let parentDir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // Use file coordination for iCloud safety
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save trash: \(error)")
            }
        }

        if let error = coordinatorError {
            print("Coordination error saving trash: \(error)")
        }
    }

    private func loadFromFile() async {
        let fileURL = trashFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { url in
            do {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                self.items = self.parseMarkdown(markdown)
            } catch {
                print("Failed to load trash: \(error)")
            }
        }

        if let error = coordinatorError {
            print("Coordination error loading trash: \(error)")
        }
    }

    // MARK: - Markdown Generation

    private func generateMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Lineout Trash Bin")
        lines.append("")
        lines.append("Items are sorted by deletion date (most recent first).")
        lines.append("")
        lines.append("---")
        lines.append("")

        for item in items {
            lines.append(contentsOf: generateItemMarkdown(item, depth: 0))
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func generateItemMarkdown(_ item: TrashedItem, depth: Int) -> [String] {
        var lines: [String] = []

        let indent = String(repeating: "  ", count: depth)
        let bullet = depth == 0 ? "##" : "-"
        let timestamp = dateFormatter.string(from: item.deletedAt)

        if depth == 0 {
            // Top-level deleted item with timestamp and week
            lines.append("\(bullet) \(item.title)")
            if !item.weekFileName.isEmpty {
                lines.append("*Deleted: \(timestamp) | Week: \(item.weekFileName)*")
            } else {
                lines.append("*Deleted: \(timestamp)*")
            }
            if !item.body.isEmpty {
                lines.append("")
                lines.append(item.body)
            }
        } else {
            // Nested child
            lines.append("\(indent)\(bullet) \(item.title)")
            if !item.body.isEmpty {
                lines.append("\(indent)  \(item.body)")
            }
        }

        // Add children
        for child in item.children {
            lines.append(contentsOf: generateItemMarkdown(child, depth: depth + 1))
        }

        return lines
    }

    // MARK: - Markdown Parsing

    private func parseMarkdown(_ markdown: String) -> [TrashedItem] {
        // Simple parsing - look for ## headers followed by *Deleted: timestamp*
        var parsedItems: [TrashedItem] = []
        let lines = markdown.components(separatedBy: "\n")

        var currentTitle: String?
        var currentBody: String = ""
        var currentTimestamp: Date?
        var currentWeekFileName: String = ""
        var currentChildren: [String] = []
        var inItem = false

        for line in lines {
            if line.hasPrefix("## ") {
                // Save previous item if exists
                if let title = currentTitle, let timestamp = currentTimestamp {
                    let item = TrashedItemParsed(
                        title: title,
                        body: currentBody.trimmingCharacters(in: .whitespacesAndNewlines),
                        deletedAt: timestamp,
                        weekFileName: currentWeekFileName,
                        childrenLines: currentChildren
                    )
                    parsedItems.append(item.toTrashedItem())
                }

                // Start new item
                currentTitle = String(line.dropFirst(3))
                currentBody = ""
                currentTimestamp = nil
                currentWeekFileName = ""
                currentChildren = []
                inItem = true
            } else if line.hasPrefix("*Deleted: ") && line.hasSuffix("*") {
                // Parse: "*Deleted: 2026-01-27 10:30:00 | Week: 2026-Jan-W05.md*"
                // or old format: "*Deleted: 2026-01-27 10:30:00*"
                let content = String(line.dropFirst(10).dropLast(1))
                if let pipeRange = content.range(of: " | Week: ") {
                    let timestampStr = String(content[content.startIndex..<pipeRange.lowerBound])
                    currentTimestamp = dateFormatter.date(from: timestampStr)
                    currentWeekFileName = String(content[pipeRange.upperBound...])
                } else {
                    currentTimestamp = dateFormatter.date(from: content)
                }
            } else if line == "---" {
                inItem = false
            } else if inItem && line.hasPrefix("- ") {
                currentChildren.append(line)
            } else if inItem && !line.hasPrefix("#") && !line.isEmpty && currentTimestamp != nil {
                if currentChildren.isEmpty {
                    currentBody += line + "\n"
                } else {
                    currentChildren.append(line)
                }
            }
        }

        // Save last item
        if let title = currentTitle, let timestamp = currentTimestamp {
            let item = TrashedItemParsed(
                title: title,
                body: currentBody.trimmingCharacters(in: .whitespacesAndNewlines),
                deletedAt: timestamp,
                weekFileName: currentWeekFileName,
                childrenLines: currentChildren
            )
            parsedItems.append(item.toTrashedItem())
        }

        return parsedItems
    }
}

// Helper struct for parsing
private struct TrashedItemParsed {
    let title: String
    let body: String
    let deletedAt: Date
    let weekFileName: String
    let childrenLines: [String]

    func toTrashedItem() -> TrashedItem {
        // Parse children from lines (simplified - just extracts titles)
        let children = parseChildren(from: childrenLines)

        return TrashedItem(
            id: UUID(),
            title: title,
            body: body,
            children: children,
            deletedAt: deletedAt,
            originalDepth: 0,
            weekFileName: weekFileName
        )
    }

    private func parseChildren(from lines: [String]) -> [TrashedItem] {
        var children: [TrashedItem] = []

        for line in lines {
            if line.hasPrefix("- ") || line.hasPrefix("  - ") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    let childTitle = String(trimmed.dropFirst(2))
                    children.append(TrashedItem(
                        id: UUID(),
                        title: childTitle,
                        body: "",
                        children: [],
                        deletedAt: deletedAt,
                        originalDepth: 1,
                        weekFileName: weekFileName
                    ))
                }
            }
        }

        return children
    }
}

// Extension to create TrashedItem directly for parsing
extension TrashedItem {
    init(id: UUID, title: String, body: String, children: [TrashedItem], deletedAt: Date, originalDepth: Int, weekFileName: String = "") {
        self.id = id
        self.title = title
        self.body = body
        self.children = children
        self.deletedAt = deletedAt
        self.originalDepth = originalDepth
        self.weekFileName = weekFileName
    }
}
