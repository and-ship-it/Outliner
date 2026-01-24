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

    init(from node: OutlineNode, depth: Int = 0) {
        self.id = UUID()
        self.title = node.title
        self.body = node.body
        self.children = node.children.map { TrashedItem(from: $0, depth: depth + 1) }
        self.deletedAt = Date()
        self.originalDepth = depth
    }
}

/// Manages the trash bin - stores deleted items and persists to markdown
@Observable
final class TrashBin {
    static let shared = TrashBin()

    private(set) var items: [TrashedItem] = []

    private let trashFileURL: URL
    private let dateFormatter: DateFormatter

    private init() {
        // Get the app's document directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        trashFileURL = documentsPath.appendingPathComponent("Lineout-Trash.md")

        // Set up date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Load existing trash
        loadFromFile()
    }

    // MARK: - Public Methods

    /// Add a node and all its children to the trash
    func trash(_ node: OutlineNode) {
        let trashedItem = TrashedItem(from: node)
        items.insert(trashedItem, at: 0) // Most recent first
        saveToFile()
    }

    /// Clear all items from trash (permanent delete)
    func emptyTrash() {
        items.removeAll()
        saveToFile()
    }

    /// Remove a specific item from trash
    func remove(_ item: TrashedItem) {
        items.removeAll { $0.id == item.id }
        saveToFile()
    }

    // MARK: - Persistence

    private func saveToFile() {
        let markdown = generateMarkdown()
        do {
            try markdown.write(to: trashFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save trash: \(error)")
        }
    }

    private func loadFromFile() {
        guard FileManager.default.fileExists(atPath: trashFileURL.path) else { return }

        do {
            let markdown = try String(contentsOf: trashFileURL, encoding: .utf8)
            items = parseMarkdown(markdown)
        } catch {
            print("Failed to load trash: \(error)")
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
            // Top-level deleted item with timestamp
            lines.append("\(bullet) \(item.title)")
            lines.append("*Deleted: \(timestamp)*")
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
                        childrenLines: currentChildren
                    )
                    parsedItems.append(item.toTrashedItem())
                }

                // Start new item
                currentTitle = String(line.dropFirst(3))
                currentBody = ""
                currentTimestamp = nil
                currentChildren = []
                inItem = true
            } else if line.hasPrefix("*Deleted: ") && line.hasSuffix("*") {
                let timestampStr = String(line.dropFirst(10).dropLast(1))
                currentTimestamp = dateFormatter.date(from: timestampStr)
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
            originalDepth: 0
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
                        originalDepth: 1
                    ))
                }
            }
        }

        return children
    }
}

// Extension to create TrashedItem directly for parsing
extension TrashedItem {
    init(id: UUID, title: String, body: String, children: [TrashedItem], deletedAt: Date, originalDepth: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.children = children
        self.deletedAt = deletedAt
        self.originalDepth = originalDepth
    }
}
