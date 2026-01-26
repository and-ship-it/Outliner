//
//  SmartPasteParser.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import Foundation

/// Detected format of a line in pasted content
enum LineFormat {
    case markdownDash       // "- "
    case markdownAsterisk   // "* "
    case markdownPlus       // "+ "
    case numberedArabic     // "1. ", "2. "
    case numberedAlpha      // "a. ", "b. "
    case numberedRoman      // "i. ", "ii. "
    case unicodeBullet      // "•", "◦", "▪", "▸"
    case plainText          // no bullet marker
}

/// Represents a parsed line before tree building
struct ParsedLine {
    let content: String
    let indentLevel: Int
    let originalFormat: LineFormat
    let isTask: Bool
    let isTaskCompleted: Bool
}

/// Result of parsing pasted content
struct SmartPasteResult {
    let nodes: [OutlineNode]
    let isSingleLine: Bool
    let originalLineCount: Int
    let detectedFormat: LineFormat?
}

/// Parser for clipboard content - converts various formats to outline nodes
struct SmartPasteParser {

    // MARK: - URL Detection

    /// Check if the pasted text is just a URL (for smart link conversion)
    static func isJustURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check if it's a single line that looks like a URL
        if trimmed.contains("\n") { return nil }
        return LinkParser.extractURL(trimmed)
    }

    // MARK: - Main Entry Point

    /// Parse pasted text into outline nodes
    static func parse(_ text: String) -> SmartPasteResult {
        let lines = text.components(separatedBy: .newlines)

        // Handle edge cases
        if lines.isEmpty || (lines.count == 1 && lines[0].trimmingCharacters(in: .whitespaces).isEmpty) {
            return SmartPasteResult(nodes: [], isSingleLine: true, originalLineCount: 0, detectedFormat: nil)
        }

        // Single line detection (also count trailing empty line as single)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let isSingleLine = nonEmptyLines.count <= 1

        // Parse all lines (skip empty ones)
        let parsedLines = lines.compactMap { parseLine($0) }

        if parsedLines.isEmpty {
            return SmartPasteResult(nodes: [], isSingleLine: true, originalLineCount: lines.count, detectedFormat: nil)
        }

        // Detect dominant format
        let detectedFormat = detectDominantFormat(parsedLines)

        // Build tree structure
        let nodes = buildTree(from: parsedLines)

        return SmartPasteResult(
            nodes: nodes,
            isSingleLine: isSingleLine,
            originalLineCount: lines.count,
            detectedFormat: detectedFormat
        )
    }

    // MARK: - Line Parsing

    private static func parseLine(_ line: String) -> ParsedLine? {
        // Skip completely empty lines
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }

        // Calculate whitespace-based indent level
        let (baseIndentLevel, content) = extractIndent(line)

        // Check for dash-based nesting: "- - content", "- - - content", "-   - content" etc.
        // Each "- " pattern (possibly separated by spaces) adds one indent level
        var dashIndentLevel = 0
        var adjustedContent = content

        // Count "- " patterns, allowing whitespace between them
        var dashCount = 0
        var remaining = content

        while true {
            // Check for "- " pattern
            if remaining.hasPrefix("- ") {
                dashCount += 1
                remaining = String(remaining.dropFirst(2))
                // Skip any whitespace after the "- " before checking for another dash
                while remaining.hasPrefix(" ") || remaining.hasPrefix("\t") {
                    remaining = String(remaining.dropFirst())
                }
            } else {
                break
            }
        }

        if dashCount > 1 {
            // Multiple dashes = nested bullet
            // First dash is the bullet marker, additional dashes indicate nesting
            dashIndentLevel = dashCount - 1
            // For format detection, present as single dash bullet with remaining content
            adjustedContent = "- " + remaining
        }

        // Detect format and extract content
        let (format, cleanContent, isTask, isCompleted) = detectFormat(adjustedContent)

        // Skip if content is empty after cleaning (but allow tasks with empty content)
        if cleanContent.trimmingCharacters(in: .whitespaces).isEmpty && !isTask {
            return nil
        }

        return ParsedLine(
            content: cleanContent,
            indentLevel: baseIndentLevel + dashIndentLevel,
            originalFormat: format,
            isTask: isTask,
            isTaskCompleted: isCompleted
        )
    }

    // MARK: - Indent Detection

    private static func extractIndent(_ line: String) -> (level: Int, content: String) {
        var spaceCount = 0
        var charIndex = line.startIndex

        for char in line {
            if char == " " {
                spaceCount += 1
            } else if char == "\t" {
                spaceCount += 4  // Tab = 4 spaces
            } else {
                break
            }
            charIndex = line.index(after: charIndex)
        }

        // Use 2 spaces per level (common in many apps)
        // This will be normalized later anyway
        let level = spaceCount / 2
        let content = String(line[charIndex...])
        return (level, content)
    }

    // MARK: - Format Detection

    private static func detectFormat(_ content: String) -> (LineFormat, String, Bool, Bool) {
        var isTask = false
        var isCompleted = false
        var cleanContent = content
        var format: LineFormat = .plainText

        // Markdown bullets: "- ", "* ", "+ "
        if content.hasPrefix("- ") {
            format = .markdownDash
            cleanContent = String(content.dropFirst(2))
        } else if content.hasPrefix("* ") {
            format = .markdownAsterisk
            cleanContent = String(content.dropFirst(2))
        } else if content.hasPrefix("+ ") {
            format = .markdownPlus
            cleanContent = String(content.dropFirst(2))
        }
        // Numbered lists - detect format but KEEP the number in content
        else if content.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            format = .numberedArabic
            // Keep the number: "1. First" stays as "1. First"
            cleanContent = content
        }
        else if content.range(of: #"^[a-zA-Z]\.\s+"#, options: .regularExpression) != nil {
            format = .numberedAlpha
            // Keep the letter: "a. First" stays as "a. First"
            cleanContent = content
        }
        else if content.range(of: #"^(i{1,3}|iv|vi{0,3}|ix|x{1,3})\.\s+"#, options: [.regularExpression, .caseInsensitive]) != nil {
            format = .numberedRoman
            // Keep the roman numeral: "i. First" stays as "i. First"
            cleanContent = content
        }
        // Unicode bullets: •, ◦, ▪, ▸, ●, ○, ■, □, ▶, ►
        else if let firstChar = content.first {
            let bulletChars: Set<Character> = ["•", "◦", "▪", "▸", "●", "○", "■", "□", "▶", "►", "◆", "◇", "→", "➤", "➜"]
            if bulletChars.contains(firstChar) {
                format = .unicodeBullet
                cleanContent = String(content.dropFirst())
                // Also drop space after bullet if present
                if cleanContent.hasPrefix(" ") {
                    cleanContent = String(cleanContent.dropFirst())
                }
            }
        }

        // Check for task checkboxes in clean content
        // Standard markdown: [ ], [x], [X] - with or without trailing space/content
        if cleanContent.hasPrefix("[ ] ") {
            isTask = true
            isCompleted = false
            cleanContent = String(cleanContent.dropFirst(4))
        } else if cleanContent == "[ ]" || cleanContent == "[]" {
            // Empty task (no content after checkbox)
            isTask = true
            isCompleted = false
            cleanContent = ""
        } else if cleanContent.hasPrefix("[x] ") || cleanContent.hasPrefix("[X] ") {
            isTask = true
            isCompleted = true
            cleanContent = String(cleanContent.dropFirst(4))
        } else if cleanContent == "[x]" || cleanContent == "[X]" {
            // Completed empty task
            isTask = true
            isCompleted = true
            cleanContent = ""
        }
        // Unicode checkboxes: ☐ (empty), ☑ (checked), ☒, ✓, ✔, ✗, ✘
        else if cleanContent.hasPrefix("☐ ") || cleanContent.hasPrefix("☐") {
            isTask = true
            isCompleted = false
            cleanContent = cleanContent.hasPrefix("☐ ") ? String(cleanContent.dropFirst(2)) : String(cleanContent.dropFirst(1))
        }
        else if cleanContent.hasPrefix("☑ ") || cleanContent.hasPrefix("☑") ||
                cleanContent.hasPrefix("☒ ") || cleanContent.hasPrefix("☒") ||
                cleanContent.hasPrefix("✓ ") || cleanContent.hasPrefix("✓") ||
                cleanContent.hasPrefix("✔ ") || cleanContent.hasPrefix("✔") {
            isTask = true
            isCompleted = true
            let firstChar = cleanContent.first!
            cleanContent = cleanContent.hasPrefix("\(firstChar) ") ? String(cleanContent.dropFirst(2)) : String(cleanContent.dropFirst(1))
        }

        return (format, cleanContent.trimmingCharacters(in: .whitespaces), isTask, isCompleted)
    }

    // MARK: - Tree Building

    private static func buildTree(from parsedLines: [ParsedLine]) -> [OutlineNode] {
        guard !parsedLines.isEmpty else { return [] }

        // Normalize indent levels
        let normalizedLines = normalizeIndentLevels(parsedLines)

        // Build tree using stack-based approach
        var roots: [OutlineNode] = []
        var stack: [(node: OutlineNode, level: Int)] = []

        for line in normalizedLines {
            let newNode = OutlineNode(
                title: line.content,
                isTask: line.isTask,
                isTaskCompleted: line.isTaskCompleted
            )

            // Pop stack until we find a suitable parent (one with lower indent level)
            while !stack.isEmpty && stack.last!.level >= line.indentLevel {
                stack.removeLast()
            }

            if stack.isEmpty {
                // Top-level node
                roots.append(newNode)
            } else {
                // Child of the last node on stack
                stack.last!.node.addChild(newNode)
            }

            // Push this node onto stack (it might be a parent later)
            stack.append((node: newNode, level: line.indentLevel))
        }

        return roots
    }

    /// Normalize indent levels to be 0-indexed and consecutive
    private static func normalizeIndentLevels(_ lines: [ParsedLine]) -> [ParsedLine] {
        // Collect all unique indent levels
        let indentLevels = Set(lines.map { $0.indentLevel })

        // Build mapping from raw levels to normalized 0-based levels
        let sortedLevels = indentLevels.sorted()
        var levelMap: [Int: Int] = [:]
        for (index, level) in sortedLevels.enumerated() {
            levelMap[level] = index
        }

        // Apply normalization
        return lines.map { line in
            ParsedLine(
                content: line.content,
                indentLevel: levelMap[line.indentLevel] ?? line.indentLevel,
                originalFormat: line.originalFormat,
                isTask: line.isTask,
                isTaskCompleted: line.isTaskCompleted
            )
        }
    }

    // MARK: - Format Detection (dominant)

    private static func detectDominantFormat(_ lines: [ParsedLine]) -> LineFormat? {
        var formatCounts: [LineFormat: Int] = [:]
        for line in lines {
            formatCounts[line.originalFormat, default: 0] += 1
        }

        // Return most common format (excluding plain text if others exist)
        let nonPlain = formatCounts.filter { $0.key != .plainText }
        if let dominant = nonPlain.max(by: { $0.value < $1.value }) {
            return dominant.key
        }
        return formatCounts.keys.first
    }
}
