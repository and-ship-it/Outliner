//
//  MarkdownCodec.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation

/// Parses and serializes outlines to/from Markdown format
///
/// Format:
/// ```markdown
/// - Title here
///
///   Body paragraph here.
///   Can be multiple lines.
///
///     - Child 1
///     - Child 2
/// ```
///
/// Rules:
/// - Nodes start with `- ` after indentation
/// - Indentation is 4 spaces per level
/// - Body is indented text after title, before children
/// - Blank lines separate body from children
struct MarkdownCodec {

    private static let indentSize = 4
    private static let bulletPrefix = "- "

    // MARK: - Parse

    /// Parse markdown string into an OutlineNode tree
    /// Returns the root node (invisible, children are top-level items)
    static func parse(_ markdown: String) -> OutlineNode {
        let root = OutlineNode(title: "__root__")
        let lines = markdown.components(separatedBy: .newlines)

        var index = 0
        parseChildren(from: lines, index: &index, parent: root, parentIndent: -1)

        return root
    }

    private static func parseChildren(
        from lines: [String],
        index: inout Int,
        parent: OutlineNode,
        parentIndent: Int
    ) {
        while index < lines.count {
            let line = lines[index]

            // Skip empty lines at this level
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            let (indent, content) = parseLine(line)

            // If indent is less than or equal to parent, we're done with this level
            if indent <= parentIndent {
                return
            }

            // Check if this is a bullet line
            if content.hasPrefix(bulletPrefix) {
                var title = String(content.dropFirst(bulletPrefix.count))
                var isTask = false
                var isTaskCompleted = false

                // Check for task checkbox: [ ] or [x]
                if title.hasPrefix("[ ] ") {
                    isTask = true
                    isTaskCompleted = false
                    title = String(title.dropFirst(4))
                } else if title.hasPrefix("[x] ") || title.hasPrefix("[X] ") {
                    isTask = true
                    isTaskCompleted = true
                    title = String(title.dropFirst(4))
                }

                let node = OutlineNode(title: title, isTask: isTask, isTaskCompleted: isTaskCompleted)
                parent.addChild(node)
                index += 1

                // Check for metadata comments on subsequent lines
                while index < lines.count {
                    let metaLine = lines[index].trimmingCharacters(in: .whitespaces)
                    if metaLine.hasPrefix("<!--") && metaLine.hasSuffix("-->") {
                        parseNodeMetadata(metaLine, into: node)
                        index += 1
                    } else {
                        break
                    }
                }

                // Parse body (non-bullet lines at deeper indent)
                var bodyLines: [String] = []
                while index < lines.count {
                    let nextLine = lines[index]

                    // Empty line might be part of body or separator
                    if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Look ahead to see if there's more body or children
                        let lookahead = lookAhead(lines: lines, from: index + 1)
                        if lookahead.isContinuation && lookahead.indent > indent && !lookahead.isBullet {
                            bodyLines.append("")
                            index += 1
                            continue
                        } else {
                            index += 1
                            break
                        }
                    }

                    let (nextIndent, nextContent) = parseLine(nextLine)

                    // If it's a bullet at any indent, stop collecting body
                    if nextContent.hasPrefix(bulletPrefix) {
                        break
                    }

                    // If it's indented text (body), collect it
                    if nextIndent > indent {
                        bodyLines.append(nextContent)
                        index += 1
                    } else {
                        break
                    }
                }

                // Set body
                if !bodyLines.isEmpty {
                    node.body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Parse children (bullets at deeper indent)
                parseChildren(from: lines, index: &index, parent: node, parentIndent: indent)

            } else {
                // Non-bullet line at this level - could be orphaned body text, skip
                index += 1
            }
        }
    }

    private static func parseLine(_ line: String) -> (indent: Int, content: String) {
        var spaceCount = 0
        for char in line {
            if char == " " {
                spaceCount += 1
            } else if char == "\t" {
                spaceCount += indentSize
            } else {
                break
            }
        }
        let indent = spaceCount / indentSize
        let content = String(line.dropFirst(spaceCount))
        return (indent, content)
    }

    private static func lookAhead(lines: [String], from index: Int) -> (isContinuation: Bool, indent: Int, isBullet: Bool) {
        guard index < lines.count else {
            return (false, 0, false)
        }

        let line = lines[index]
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return (false, 0, false)
        }

        let (indent, content) = parseLine(line)
        return (true, indent, content.hasPrefix(bulletPrefix))
    }

    // MARK: - Node Metadata

    /// Parse a metadata comment like `<!-- reminder:ABC123 list:Shopping time:9:30 -->`,
    /// `<!-- section:calendar -->`, `<!-- calevent:ID cal:Name -->`, or `<!-- placeholder -->`
    private static func parseNodeMetadata(_ line: String, into node: OutlineNode) {
        // Strip <!-- and -->
        var content = line
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Parse "section:calendar" or "section:reminders"
        if content.hasPrefix("section:") {
            node.sectionType = String(content.dropFirst("section:".count))
            return
        }

        // Parse "calevent:ID cal:Name"
        if content.hasPrefix("calevent:") {
            content = String(content.dropFirst("calevent:".count))
            if let calRange = content.range(of: " cal:") {
                node.calendarEventIdentifier = String(content[content.startIndex..<calRange.lowerBound])
                node.calendarName = String(content[calRange.upperBound...])
            } else {
                node.calendarEventIdentifier = content
            }
            return
        }

        // Parse "placeholder"
        if content == "placeholder" {
            node.isPlaceholder = true
            return
        }

        // Parse "reminder:ID" and optionally "list:Name" and "time:HH:MM"
        if content.hasPrefix("reminder:") {
            content = String(content.dropFirst("reminder:".count))

            // Extract time:HH:MM if present
            if let timeRange = content.range(of: " time:") {
                let afterTime = String(content[timeRange.upperBound...])
                // Time value is everything after "time:" until end
                let timeParts = afterTime.split(separator: ":")
                if timeParts.count == 2,
                   let hour = Int(timeParts[0]),
                   let minute = Int(timeParts[1]) {
                    node.reminderTimeHour = hour
                    node.reminderTimeMinute = minute
                }
                // Remove time part from content for further parsing
                content = String(content[content.startIndex..<timeRange.lowerBound])
            }

            // Extract list:Name if present
            if let listRange = content.range(of: " list:") {
                node.reminderIdentifier = String(content[content.startIndex..<listRange.lowerBound])
                node.reminderListName = String(content[listRange.upperBound...])
            } else {
                node.reminderIdentifier = content
            }
            return
        }

        // Parse "rtype:note" or "rtype:link" for metadata children
        if content.hasPrefix("rtype:") {
            node.reminderChildType = String(content.dropFirst("rtype:".count))
            return
        }
    }

    // MARK: - Serialize

    /// Serialize an OutlineNode tree to markdown string
    static func serialize(_ root: OutlineNode) -> String {
        var lines: [String] = []

        for child in root.children {
            serializeNode(child, indent: 0, into: &lines)
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeNode(_ node: OutlineNode, indent: Int, into lines: inout [String]) {
        let indentString = String(repeating: " ", count: indent * indentSize)

        // Title line (with optional task checkbox)
        let taskPrefix = node.isTask ? (node.isTaskCompleted ? "[x] " : "[ ] ") : ""
        lines.append("\(indentString)\(bulletPrefix)\(taskPrefix)\(node.title)")

        // Section metadata comment (calendar or reminders container)
        if let sectionType = node.sectionType {
            let bodyIndent = String(repeating: " ", count: (indent + 1) * indentSize)
            lines.append("\(bodyIndent)<!-- section:\(sectionType) -->")
        }

        // Calendar event metadata comment
        if let eventId = node.calendarEventIdentifier {
            let calPart = node.calendarName.map { " cal:\($0)" } ?? ""
            let bodyIndent = String(repeating: " ", count: (indent + 1) * indentSize)
            lines.append("\(bodyIndent)<!-- calevent:\(eventId)\(calPart) -->")
        }

        // Placeholder metadata comment
        if node.isPlaceholder {
            let bodyIndent = String(repeating: " ", count: (indent + 1) * indentSize)
            lines.append("\(bodyIndent)<!-- placeholder -->")
        }

        // Reminder metadata comment (if synced with Apple Reminders)
        if let reminderId = node.reminderIdentifier {
            let listPart = node.reminderListName.map { " list:\($0)" } ?? ""
            var timePart = ""
            if let hour = node.reminderTimeHour, let minute = node.reminderTimeMinute {
                timePart = " time:\(hour):\(String(format: "%02d", minute))"
            }
            let bodyIndent = String(repeating: " ", count: (indent + 1) * indentSize)
            lines.append("\(bodyIndent)<!-- reminder:\(reminderId)\(listPart)\(timePart) -->")
        }

        // Reminder child type metadata (for note/link metadata children)
        if let childType = node.reminderChildType {
            let bodyIndent = String(repeating: " ", count: (indent + 1) * indentSize)
            lines.append("\(bodyIndent)<!-- rtype:\(childType) -->")
        }

        // Body (if present)
        if node.hasBody {
            lines.append("") // Blank line before body
            let bodyIndent = String(repeating: " ", count: (indent + 1) * indentSize)
            let bodyLines = node.body.components(separatedBy: .newlines)
            for bodyLine in bodyLines {
                if bodyLine.isEmpty {
                    lines.append("")
                } else {
                    lines.append("\(bodyIndent)\(bodyLine)")
                }
            }
        }

        // Children
        if node.hasChildren {
            if node.hasBody {
                lines.append("") // Blank line between body and children
            }
            for child in node.children {
                serializeNode(child, indent: indent + 1, into: &lines)
            }
        }

        // Add blank line after top-level items for readability
        if indent == 0 {
            lines.append("")
        }
    }
}

// MARK: - Sample Data

extension MarkdownCodec {
    /// Creates a sample outline for testing
    static func sampleOutline() -> OutlineNode {
        let markdown = """
        - Inbox

            Quick capture area for new thoughts

            - Call mom
            - Buy groceries
            - Random idea about the app

        - Today

            Focus on these items

            - Ship login feature

                We need to fix the token refresh because users
                are getting logged out after 30 minutes.

                - Fix token refresh bug
                - Add "remember me" checkbox
                - Write integration tests

            - Review pull requests
            - Team standup at 10am

        - Projects

            - App Redesign

                Complete overhaul of the mobile experience

                - User research
                - Wireframes
                - Visual design
                - Implementation

            - API Migration

                - Plan migration strategy
                - Update endpoints
                - Test backwards compatibility

        - Someday

            - Learn Rust
            - Write blog post about outlining
            - Organize photo library
        """

        return parse(markdown)
    }
}
