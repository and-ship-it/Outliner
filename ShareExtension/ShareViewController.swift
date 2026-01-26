//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Andriy on 26/01/2026.
//

import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension view controller - handles content shared from other apps
class ShareViewController: UIViewController {

    // UI Elements
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let checkmarkView = UIImageView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedContent()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        // Container
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Title
        titleLabel.text = "Adding to Lineout"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Description
        descriptionLabel.text = "Processing..."
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(descriptionLabel)

        // Activity Indicator
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        containerView.addSubview(activityIndicator)

        // Checkmark (hidden initially)
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkView.tintColor = .systemGreen
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.alpha = 0
        containerView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            activityIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            checkmarkView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            checkmarkView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 40),
            checkmarkView.heightAnchor.constraint(equalToConstant: 40),

            descriptionLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            descriptionLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),
        ])

        // Tap to dismiss (after completion)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissIfComplete))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissIfComplete() {
        if !activityIndicator.isAnimating {
            completeRequest()
        }
    }

    // MARK: - Content Processing

    private func processSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            showError("No content to share")
            return
        }

        // Process each attachment
        Task {
            do {
                var sharedURL: URL?
                var sharedText: String?

                for attachment in attachments {
                    // Check for URL
                    if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let url = try await loadURL(from: attachment) {
                            sharedURL = url
                        }
                    }
                    // Check for plain text
                    else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        if let text = try await loadText(from: attachment) {
                            sharedText = text
                        }
                    }
                    // Check for text (another identifier)
                    else if attachment.hasItemConformingToTypeIdentifier("public.text") {
                        if let text = try await loadText(from: attachment, typeIdentifier: "public.text") {
                            sharedText = text
                        }
                    }
                }

                // Process the content
                if let url = sharedURL {
                    await processURL(url)
                } else if let text = sharedText {
                    await processText(text)
                } else {
                    showError("Unsupported content type")
                }
            } catch {
                showError("Failed to process: \(error.localizedDescription)")
            }
        }
    }

    private func loadURL(from attachment: NSItemProvider) async throws -> URL? {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = data as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from attachment: NSItemProvider, typeIdentifier: String = "public.plain-text") async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let text = data as? String {
                    continuation.resume(returning: text)
                } else if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - URL Processing

    private func processURL(_ url: URL) async {
        await MainActor.run {
            descriptionLabel.text = "Fetching page title..."
        }

        // Fetch page title
        let title = await fetchPageTitle(for: url) ?? url.host ?? "Link"
        let shortTitle = shortenTitle(title)
        let description = shortTitle

        // Create the link markdown
        let linkMarkdown = "[\(shortTitle)](\(url.absoluteString))"

        // Save to document
        await saveToDocument(description: description, content: linkMarkdown, isLink: true)
    }

    // MARK: - Text Processing

    private func processText(_ text: String) async {
        await MainActor.run {
            descriptionLabel.text = "Processing text..."
        }

        // Generate a short description from the text
        let description = generateDescription(from: text)

        // Check if it's a list or single text
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if lines.count > 1 {
            // Multiple lines - save as nested bullets
            await saveToDocument(description: description, content: text, isLink: false)
        } else {
            // Single line - save directly
            await saveToDocument(description: description, content: text.trimmingCharacters(in: .whitespacesAndNewlines), isLink: false)
        }
    }

    // MARK: - Document Saving

    private func saveToDocument(description: String, content: String, isLink: Bool) async {
        await MainActor.run {
            descriptionLabel.text = "Saving to Lineout..."
        }

        do {
            // Load or create document
            let helper = ShareDocumentHelper()
            try await helper.addSharedContent(description: description, content: content, isLink: isLink)

            await MainActor.run {
                showSuccess(description: description)
            }
        } catch {
            await MainActor.run {
                showError("Failed to save: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UI Updates

    private func showSuccess(description: String) {
        activityIndicator.stopAnimating()
        activityIndicator.alpha = 0

        UIView.animate(withDuration: 0.3) {
            self.checkmarkView.alpha = 1
            self.descriptionLabel.text = "Added: \(description)"
        }

        // Auto-dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.completeRequest()
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.descriptionLabel.text = message
            self.checkmarkView.image = UIImage(systemName: "xmark.circle.fill")
            self.checkmarkView.tintColor = .systemRed
            self.checkmarkView.alpha = 1

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.completeRequest()
            }
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    // MARK: - Helpers

    private func fetchPageTitle(for url: URL) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let mimeType = httpResponse.mimeType,
                  mimeType.contains("html"),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Extract title from HTML
            let pattern = "<title[^>]*>([^<]+)</title>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                  let titleRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            return String(html[titleRange])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func shortenTitle(_ title: String, maxWords: Int = 5) -> String {
        // Remove common suffixes like " - Site Name" or " | Site Name"
        var cleaned = title
        for separator in [" - ", " | ", " — ", " – ", " :: ", " : "] {
            if let range = cleaned.range(of: separator) {
                let beforeSep = String(cleaned[..<range.lowerBound])
                let afterSep = String(cleaned[range.upperBound...])
                cleaned = beforeSep.count <= afterSep.count ? beforeSep : afterSep
            }
        }

        let words = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let shortened = words.prefix(maxWords).joined(separator: " ")

        if words.count > maxWords {
            return shortened + "..."
        }
        return shortened
    }

    private func generateDescription(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }

        if lines.count > 1 {
            // Multiple lines - use "X items" or first few words
            return "\(lines.count) items"
        } else {
            // Single line - shorten it
            return shortenTitle(trimmed, maxWords: 5)
        }
    }
}

// MARK: - Share Document Helper

/// Helper class to manage document loading/saving for the share extension
class ShareDocumentHelper {

    private let containerIdentifier = "iCloud.computer.daydreamlab.Lineout-ly"
    private let folderName = "Lineout-ly"
    private let sharedNodeTitle = "Shared"

    /// Add shared content to the document
    func addSharedContent(description: String, content: String, isLink: Bool) async throws {
        // Get the document file URL
        let fileURL = try await getDocumentURL()

        // Read existing content
        var markdown: String
        if FileManager.default.fileExists(atPath: fileURL.path) {
            markdown = try String(contentsOf: fileURL, encoding: .utf8)
        } else {
            markdown = ""
        }

        // Parse existing content to find or create "Shared" node
        let newMarkdown = addToSharedNode(
            existingMarkdown: markdown,
            description: description,
            content: content,
            isLink: isLink
        )

        // Write back
        try newMarkdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func getDocumentURL() async throws -> URL {
        // Try iCloud first
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let appFolder = containerURL
                .appendingPathComponent("Documents")
                .appendingPathComponent(folderName)

            // Create folder if needed
            if !FileManager.default.fileExists(atPath: appFolder.path) {
                try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }

            let fileName = currentWeekFileName()
            return appFolder.appendingPathComponent(fileName)
        }

        // Fallback to local
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent(folderName)

        if !FileManager.default.fileExists(atPath: appFolder.path) {
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        let fileName = currentWeekFileName()
        return appFolder.appendingPathComponent(fileName)
    }

    private func currentWeekFileName() -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let weekOfYear = calendar.component(.weekOfYear, from: Date())

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        // Get first day of week to determine month
        let weekday = calendar.component(.weekday, from: Date())
        let weekStart = UserDefaults.standard.integer(forKey: "weekStartDay")
        let startDay = weekStart > 0 ? weekStart : 2 // Default Monday
        let daysToSubtract = (weekday - startDay + 7) % 7
        let firstDayOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: Date()) ?? Date()
        let monthName = monthFormatter.string(from: firstDayOfWeek)

        return String(format: "%d-%@-W%02d.md", year, monthName, weekOfYear)
    }

    private func addToSharedNode(existingMarkdown: String, description: String, content: String, isLink: Bool) -> String {
        var lines = existingMarkdown.components(separatedBy: "\n")

        // Find "Shared" node at root level (starts with "- Shared")
        var sharedNodeIndex: Int? = nil

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- Shared") || trimmed.hasPrefix("- shared") || trimmed == "- Shared" {
                // Check it's at root level (no leading spaces except for bullet)
                let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                if leadingSpaces == 0 {
                    sharedNodeIndex = index
                    break
                }
            }
        }

        // If "Shared" node doesn't exist, create it at the top
        if sharedNodeIndex == nil {
            lines.insert("- Shared", at: 0)
            sharedNodeIndex = 0
        }

        // Build the content to insert
        var insertLines: [String] = []

        // Description line (child of Shared, indented by 2 spaces)
        insertLines.append("  - \(description)")

        // Content line(s) (grandchild of Shared, indented by 4 spaces)
        if isLink {
            // Link content - just the markdown link
            insertLines.append("    - \(content)")
        } else {
            // Text content - parse for lists or just add as text
            let contentLines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            if contentLines.count == 1 {
                // Single line
                insertLines.append("    - \(contentLines[0].trimmingCharacters(in: .whitespaces))")
            } else {
                // Multiple lines - each becomes a sub-bullet
                for contentLine in contentLines {
                    let cleaned = cleanBulletPrefix(contentLine.trimmingCharacters(in: .whitespaces))
                    insertLines.append("    - \(cleaned)")
                }
            }
        }

        // Insert after the "Shared" node line
        let insertIndex = sharedNodeIndex! + 1
        lines.insert(contentsOf: insertLines, at: insertIndex)

        return lines.joined(separator: "\n")
    }

    /// Remove bullet prefixes from pasted content
    private func cleanBulletPrefix(_ line: String) -> String {
        var cleaned = line

        // Remove markdown bullets: "- ", "* ", "+ "
        if cleaned.hasPrefix("- ") {
            cleaned = String(cleaned.dropFirst(2))
        } else if cleaned.hasPrefix("* ") {
            cleaned = String(cleaned.dropFirst(2))
        } else if cleaned.hasPrefix("+ ") {
            cleaned = String(cleaned.dropFirst(2))
        }
        // Remove numbered lists: "1. ", "2. "
        else if let match = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            cleaned = String(cleaned[match.upperBound...])
        }
        // Remove unicode bullets: "•", "◦", etc.
        else if let first = cleaned.first {
            let bulletChars: Set<Character> = ["•", "◦", "▪", "▸", "●", "○", "■", "□", "▶", "►"]
            if bulletChars.contains(first) {
                cleaned = String(cleaned.dropFirst())
                if cleaned.hasPrefix(" ") {
                    cleaned = String(cleaned.dropFirst())
                }
            }
        }

        return cleaned
    }
}
