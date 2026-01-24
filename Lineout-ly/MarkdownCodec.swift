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
                let title = String(content.dropFirst(bulletPrefix.count))
                let node = OutlineNode(title: title)
                parent.addChild(node)
                index += 1

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

        // Title line
        lines.append("\(indentString)\(bulletPrefix)\(node.title)")

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
