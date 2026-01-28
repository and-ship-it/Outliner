//
//  LinkParser.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import Foundation

/// Handles URL detection, title fetching, and markdown link formatting
struct LinkParser {

    // MARK: - URL Detection

    /// Check if a string is a valid URL
    static func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    /// Extract URL from a string (handles URLs with or without protocol)
    static func extractURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try as-is
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return url
        }

        // Try adding https://
        if let url = URL(string: "https://" + trimmed), url.host != nil {
            return url
        }

        return nil
    }

    // MARK: - Title Fetching

    /// Fetch the page title from a URL (async)
    static func fetchTitle(for url: URL) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)

            // Check response is HTML
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let mimeType = httpResponse.mimeType,
                  mimeType.contains("html") else {
                return nil
            }

            // Parse HTML to find <title>
            guard let html = String(data: data, encoding: .utf8) else { return nil }

            return extractTitleFromHTML(html)
        } catch {
            print("[LinkParser] Failed to fetch title: \(error)")
            return nil
        }
    }

    /// Extract title from HTML content
    private static func extractTitleFromHTML(_ html: String) -> String? {
        // Simple regex to find <title>...</title>
        let pattern = "<title[^>]*>([^<]+)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        var title = String(html[titleRange])

        // Decode HTML entities
        title = decodeHTMLEntities(title)

        // Clean up whitespace
        title = title.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return title.isEmpty ? nil : title
    }

    /// Decode common HTML entities
    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            "&#x27;": "'",
            "&#x2F;": "/",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…"
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }

    // MARK: - Title Shortening

    /// Shorten a title to max 5 words, keeping it descriptive
    static func shortenTitle(_ title: String, maxWords: Int = 5) -> String {
        // Remove common prefixes like site names after " - " or " | "
        var cleaned = title
        for separator in [" - ", " | ", " — ", " – ", " :: ", " : "] {
            if let range = cleaned.range(of: separator) {
                // Keep the shorter part (usually the page title, not site name)
                let beforeSep = String(cleaned[..<range.lowerBound])
                let afterSep = String(cleaned[range.upperBound...])
                cleaned = beforeSep.count <= afterSep.count ? beforeSep : afterSep
            }
        }

        // Split into words
        let words = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Take up to maxWords
        let shortened = words.prefix(maxWords).joined(separator: " ")

        // Add ellipsis if truncated
        if words.count > maxWords {
            return shortened + "…"
        }

        return shortened
    }

    // MARK: - Markdown Link Formatting

    /// Format a URL with a short title as a markdown link
    static func formatAsMarkdownLink(title: String, url: URL) -> String {
        let shortTitle = shortenTitle(title)
        return "[\(shortTitle)](\(url.absoluteString))"
    }

    /// Parse markdown links from text and return ranges + URLs
    static func parseMarkdownLinks(_ text: String) -> [(range: Range<String.Index>, text: String, url: URL)] {
        var results: [(range: Range<String.Index>, text: String, url: URL)] = []

        // Pattern: [text](url)
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return results
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let textRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let linkText = String(text[textRange])
            let urlString = String(text[urlRange])

            if let url = URL(string: urlString) {
                results.append((range: fullRange, text: linkText, url: url))
            }
        }

        return results
    }

    /// Check if text contains markdown links
    static func containsMarkdownLinks(_ text: String) -> Bool {
        !parseMarkdownLinks(text).isEmpty
    }

    /// Get plain text version (links shown as just their text)
    static func plainText(_ text: String) -> String {
        var result = text
        let links = parseMarkdownLinks(text)
        // Process in reverse order to maintain valid ranges
        for link in links.reversed() {
            result.replaceSubrange(link.range, with: link.text)
        }
        return result
    }

    // MARK: - URL from Domain

    /// Generate a short label from just the domain if title fetch fails
    static func labelFromDomain(_ url: URL) -> String {
        guard let host = url.host else { return "Link" }
        // Remove www. prefix
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        // Take first part before first dot (e.g., "github" from "github.com")
        let parts = domain.components(separatedBy: ".")
        if let first = parts.first, !first.isEmpty {
            return first.capitalized
        }
        return domain
    }
}
