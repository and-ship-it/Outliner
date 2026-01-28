//
//  iCloudManager.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
import Combine
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Day the week starts on
enum WeekStartDay: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case saturday = 7

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .saturday: return "Saturday"
        }
    }
}

/// Manages iCloud file storage for the single-document app
@Observable
@MainActor
final class iCloudManager {
    static let shared = iCloudManager()

    // MARK: - State

    private(set) var isICloudAvailable: Bool = false
    private(set) var containerURL: URL?
    private(set) var isLoading: Bool = false
    private(set) var lastError: Error?

    /// Current week's filename (e.g., "2025-Jan-W05.md")
    private(set) var currentWeekFileName: String = ""

    // MARK: - Constants

    private let containerIdentifier = "iCloud.computer.daydreamlab.Lineout-ly"
    private let folderName = "Lineout-ly"
    private let trashFolderName = ".trash"

    // MARK: - Auto-Save (Markdown Backup)

    private var saveTask: Task<Void, Never>?
    /// Markdown backup debounce (30s since CloudKit handles real-time sync)
    private let saveDebounceInterval: Duration = .seconds(30)

    /// JSON cache save task (frequent, for fast local loading)
    private var cacheSaveTask: Task<Void, Never>?
    private let cacheSaveDebounceInterval: Duration = .seconds(1)

    // MARK: - Computed URLs

    var documentsURL: URL? {
        containerURL?.appendingPathComponent("Documents")
    }

    var appFolderURL: URL? {
        documentsURL?.appendingPathComponent(folderName)
    }

    var mainFileURL: URL? {
        guard !currentWeekFileName.isEmpty else { return nil }
        return appFolderURL?.appendingPathComponent(currentWeekFileName)
    }

    // MARK: - Week Calculation

    /// Get the week start day from SettingsManager (synced via iCloud KVS)
    var weekStartDay: WeekStartDay {
        SettingsManager.shared.weekStartDayValue
    }

    /// Calculate the filename for a given date based on week start setting
    /// Format: "2025-Jan-W05.md"
    func weekFileName(for date: Date, weekStart: WeekStartDay) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStart.rawValue

        let year = calendar.component(.year, from: date)
        let weekOfYear = calendar.component(.weekOfYear, from: date)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        // Get the first day of the week to determine the month
        let weekday = calendar.component(.weekday, from: date)
        let daysToSubtract = (weekday - weekStart.rawValue + 7) % 7
        let firstDayOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: date) ?? date
        let monthName = monthFormatter.string(from: firstDayOfWeek)

        return String(format: "%d-%@-W%02d.md", year, monthName, weekOfYear)
    }

    /// Get current week's filename
    func currentWeekFile() -> String {
        weekFileName(for: Date(), weekStart: weekStartDay)
    }

    /// Update the current week filename (call on app launch and when settings change)
    func updateCurrentWeekFileName() {
        currentWeekFileName = currentWeekFile()
        print("[iCloud] Current week file: \(currentWeekFileName)")
    }

    /// Check if a new week has started (compare against loaded file)
    func isNewWeek(comparedTo loadedFileName: String) -> Bool {
        let currentFile = currentWeekFile()
        return currentFile != loadedFileName
    }

    /// List all week files in the app folder (for archive viewing)
    func listAllWeekFiles() -> [String] {
        guard let appFolder = appFolderURL else { return [] }

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: appFolder.path)
            return files
                .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
                .sorted()
                .reversed() // Most recent first
                .map { $0 }
        } catch {
            print("[iCloud] Error listing week files: \(error)")
            return []
        }
    }

    var trashFolderURL: URL? {
        appFolderURL?.appendingPathComponent(trashFolderName)
    }

    // MARK: - Initialization

    private init() {
        // Don't block init - check iCloud availability lazily
    }

    // MARK: - iCloud Setup

    /// Check if iCloud is available and get the container URL
    /// This is async and won't block the main thread
    func checkICloudAvailability() async {
        // Check if user is signed into iCloud
        guard FileManager.default.ubiquityIdentityToken != nil else {
            isICloudAvailable = false
            containerURL = nil
            print("[iCloud] Not signed in to iCloud")
            return
        }

        // If we already have a container URL, don't check again
        if containerURL != nil {
            return
        }

        // Get the container URL on a detached background task with timeout
        // The FileManager call can block indefinitely waiting on a low-priority daemon
        // Using Task.detached to completely avoid priority inversion
        let containerIdCopy = containerIdentifier

        // Run the blocking FileManager call on a detached low-priority task
        let result: URL? = await Task.detached(priority: .utility) {
            // Race between the FileManager call and a timeout
            await withTaskGroup(of: URL?.self) { group in
                group.addTask {
                    FileManager.default.url(forUbiquityContainerIdentifier: containerIdCopy)
                }

                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil  // Timeout returns nil
                }

                // Return first non-nil result, or nil if timeout wins
                for await result in group {
                    if result != nil {
                        group.cancelAll()
                        return result
                    }
                }
                return nil
            }
        }.value

        if let url = result {
            self.containerURL = url
            self.isICloudAvailable = true
            print("[iCloud] ✅ Container available at: \(url.path)")
            // Log the full path for debugging sync issues
            if let mainFile = mainFileURL {
                print("[iCloud] 📄 Main file will be: \(mainFile.path)")
            }
        } else {
            self.isICloudAvailable = false
            self.containerURL = nil
            print("[iCloud] ❌ Container not available or timed out - using LOCAL storage")
            print("[iCloud] 📄 Local file will be: \(localMainFileURL.path)")
        }
    }

    /// Setup folder structure on first launch
    func setupOnFirstLaunch() async throws {
        // Update week filename first
        updateCurrentWeekFileName()

        guard let appFolder = appFolderURL else {
            throw iCloudError.containerNotAvailable
        }

        let fileManager = FileManager.default

        // Create app folder if needed
        if !fileManager.fileExists(atPath: appFolder.path) {
            try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        // Create trash folder if needed
        if let trashFolder = trashFolderURL, !fileManager.fileExists(atPath: trashFolder.path) {
            try fileManager.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        }

        // Create current week's file if needed
        if let mainFile = mainFileURL, !fileManager.fileExists(atPath: mainFile.path) {
            // Create empty document
            let emptyContent = "- \n"
            try emptyContent.write(to: mainFile, atomically: true, encoding: .utf8)
            print("[iCloud] Created new week file: \(currentWeekFileName)")
        }
    }

    // MARK: - Document Loading

    /// Load the main document from iCloud
    func loadDocument() async throws -> OutlineDocument {
        isLoading = true
        defer { isLoading = false }

        // Check iCloud availability (async, won't block)
        await checkICloudAvailability()

        // Ensure setup is complete
        try await setupOnFirstLaunch()

        guard let mainFile = mainFileURL else {
            throw iCloudError.containerNotAvailable
        }

        // Wait for iCloud to download the latest version of the file
        await waitForICloudDownload(fileURL: mainFile)

        // Read and parse markdown off the main thread
        let fileURL = mainFile
        let root: OutlineNode
        #if os(iOS)
        // On iOS, read directly without NSFileCoordinator.
        // File coordination + DispatchQueue + CheckedContinuation causes Swift concurrency
        // deadlocks on iOS ("unsafeForcedSync" runtime error). Since iOS is single-process,
        // file coordination isn't needed.
        root = try {
            let markdown = try String(contentsOf: fileURL, encoding: .utf8)
            return MarkdownCodec.parse(markdown)
        }()
        #else
        // On macOS, use file coordination for multi-process safety (multiple windows/tabs)
        root = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OutlineNode, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var loadError: Error?
                var loadedRoot: OutlineNode?

                coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { url in
                    do {
                        let markdown = try String(contentsOf: url, encoding: .utf8)
                        loadedRoot = MarkdownCodec.parse(markdown)
                    } catch {
                        loadError = error
                    }
                }

                if let error = coordinatorError ?? loadError {
                    continuation.resume(throwing: error)
                } else if let parsedRoot = loadedRoot {
                    continuation.resume(returning: parsedRoot)
                } else {
                    continuation.resume(throwing: iCloudError.loadFailed)
                }
            }
        }
        #endif

        // Create document on main thread (we're already on MainActor)
        print("[iCloud] Loaded document from markdown")
        return OutlineDocument(root: root)
    }

    // MARK: - Old Week Loading

    /// Load a previous week's document (read-only).
    /// Tries JSON cache first (preserves UUIDs), then falls back to markdown.
    func loadOldWeekDocument(weekFileName: String) async throws -> OutlineDocument {
        // Try JSON cache first
        if let cachedRoot = LocalNodeCache.shared.load(for: weekFileName) {
            print("[iCloud] Loaded old week from cache: \(weekFileName)")
            return OutlineDocument(root: cachedRoot)
        }

        // Fall back to markdown file
        guard let appFolder = appFolderURL else {
            // Try local fallback
            let localPath = localFallbackURL.appendingPathComponent(weekFileName)
            if FileManager.default.fileExists(atPath: localPath.path) {
                let markdown = try String(contentsOf: localPath, encoding: .utf8)
                let root = MarkdownCodec.parse(markdown)
                return OutlineDocument(root: root)
            }
            throw iCloudError.containerNotAvailable
        }

        let fileURL = appFolder.appendingPathComponent(weekFileName)

        // Trigger iCloud download if needed
        await waitForICloudDownload(fileURL: fileURL)

        let root: OutlineNode
        #if os(iOS)
        root = try {
            let markdown = try String(contentsOf: fileURL, encoding: .utf8)
            return MarkdownCodec.parse(markdown)
        }()
        #else
        root = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OutlineNode, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var loadError: Error?
                var loadedRoot: OutlineNode?

                coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { url in
                    do {
                        let markdown = try String(contentsOf: url, encoding: .utf8)
                        loadedRoot = MarkdownCodec.parse(markdown)
                    } catch {
                        loadError = error
                    }
                }

                if let error = coordinatorError ?? loadError {
                    continuation.resume(throwing: error)
                } else if let parsedRoot = loadedRoot {
                    continuation.resume(returning: parsedRoot)
                } else {
                    continuation.resume(throwing: iCloudError.loadFailed)
                }
            }
        }
        #endif

        print("[iCloud] Loaded old week from markdown: \(weekFileName)")
        return OutlineDocument(root: root)
    }

    // MARK: - iCloud Download Wait

    /// Wait for iCloud to download the latest version of a file (up to timeout)
    func waitForICloudDownload(fileURL: URL) async {
        // First, trigger download
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            print("[iCloud] 📥 Triggered download for: \(fileURL.lastPathComponent)")
        } catch {
            print("[iCloud] ⚠️ startDownloadingUbiquitousItem failed: \(error)")
            return
        }

        // Check if file is already up to date
        if isFileDownloaded(fileURL) {
            print("[iCloud] ✅ File already downloaded")
            return
        }

        // Poll until downloaded or timeout (up to 10 seconds)
        let maxAttempts = 20
        for attempt in 1...maxAttempts {
            try? await Task.sleep(for: .milliseconds(500))

            if isFileDownloaded(fileURL) {
                print("[iCloud] ✅ File downloaded after \(attempt * 500)ms")
                return
            }

            print("[iCloud] ⏳ Waiting for download... attempt \(attempt)/\(maxAttempts)")
        }

        print("[iCloud] ⚠️ Download timeout - proceeding with local copy")
    }

    /// Check if an iCloud file is fully downloaded
    private func isFileDownloaded(_ fileURL: URL) -> Bool {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ])

            let status = resourceValues.ubiquitousItemDownloadingStatus
            return status == .current
        } catch {
            // If we can't check, assume it's a local file (not in iCloud)
            return FileManager.default.fileExists(atPath: fileURL.path)
        }
    }

    // MARK: - Document Saving

    /// Schedule auto-save: JSON cache at 1s (fast local recovery), markdown backup at 30s
    func scheduleAutoSave(for document: OutlineDocument) {
        // JSON cache: save frequently for fast local loading
        cacheSaveTask?.cancel()
        cacheSaveTask = Task {
            try? await Task.sleep(for: cacheSaveDebounceInterval)
            guard !Task.isCancelled else { return }
            do {
                try LocalNodeCache.shared.save(document.root)
            } catch {
                print("[iCloud] JSON cache save failed: \(error)")
            }
        }

        // Markdown backup: save infrequently (CloudKit handles real-time sync)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: saveDebounceInterval)
            guard !Task.isCancelled else { return }
            await saveMarkdown(document)
        }
    }

    /// Save the markdown backup file
    private func saveMarkdown(_ document: OutlineDocument) async {
        guard let mainFile = mainFileURL else {
            // Fall back to local save
            do {
                try saveLocal(document)
                print("[iCloud] Saved markdown backup to local: \(localMainFileURL.path)")
            } catch {
                print("[iCloud] Local save failed: \(error)")
                lastError = error
            }
            return
        }

        let markdown = MarkdownCodec.serialize(document.root)
        print("[iCloud] Saving markdown backup to: \(mainFile.path)")

        let saveResult: Error? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var writeError: Error?

                coordinator.coordinate(writingItemAt: mainFile, options: .forReplacing, error: &coordinatorError) { url in
                    do {
                        try markdown.write(to: url, atomically: true, encoding: .utf8)
                        print("[iCloud] Markdown backup saved")
                    } catch {
                        writeError = error
                    }
                }

                let error = coordinatorError ?? writeError
                continuation.resume(returning: error)
            }
        }

        if let error = saveResult {
            lastError = error
        } else {
            lastError = nil
        }
    }

    /// Save everything immediately (for background transition)
    func forceSave(_ document: OutlineDocument) async {
        saveTask?.cancel()
        cacheSaveTask?.cancel()

        // Save JSON cache immediately
        do {
            try LocalNodeCache.shared.save(document.root)
        } catch {
            print("[iCloud] JSON cache save failed: \(error)")
        }

        // Save markdown backup immediately
        await saveMarkdown(document)
    }

    // MARK: - Fallback for Non-iCloud

    /// Get a local fallback URL if iCloud is not available
    var localFallbackURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent(folderName)
    }

    var localMainFileURL: URL {
        guard !currentWeekFileName.isEmpty else {
            return localFallbackURL.appendingPathComponent("temp.md")
        }
        return localFallbackURL.appendingPathComponent(currentWeekFileName)
    }

    /// Load from local storage if iCloud is unavailable
    func loadLocalDocument() throws -> OutlineDocument {
        // Ensure week filename is set
        if currentWeekFileName.isEmpty {
            updateCurrentWeekFileName()
        }

        let fileManager = FileManager.default

        // Create local folder if needed
        if !fileManager.fileExists(atPath: localFallbackURL.path) {
            try fileManager.createDirectory(at: localFallbackURL, withIntermediateDirectories: true)
        }

        // Create or load current week's file
        if fileManager.fileExists(atPath: localMainFileURL.path) {
            let markdown = try String(contentsOf: localMainFileURL, encoding: .utf8)
            let root = MarkdownCodec.parse(markdown)
            return OutlineDocument(root: root)
        } else {
            // Create empty document for new week
            let emptyContent = "- \n"
            try emptyContent.write(to: localMainFileURL, atomically: true, encoding: .utf8)
            print("[iCloud] Created new local week file: \(currentWeekFileName)")
            return OutlineDocument.createEmpty()
        }
    }

    /// Save to local storage
    func saveLocal(_ document: OutlineDocument) throws {
        let markdown = MarkdownCodec.serialize(document.root)
        try markdown.write(to: localMainFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Factory Reset

    /// Delete all local and iCloud data files.
    func deleteAllLocalData() {
        let fm = FileManager.default

        // Delete iCloud Drive app folder (all markdown files + .trash)
        if let folder = appFolderURL, fm.fileExists(atPath: folder.path) {
            try? fm.removeItem(at: folder)
            print("[Reset] Deleted iCloud folder: \(folder.path)")
        }

        // Delete local fallback folder
        let localFolder = localFallbackURL
        if fm.fileExists(atPath: localFolder.path) {
            try? fm.removeItem(at: localFolder)
            print("[Reset] Deleted local fallback: \(localFolder.path)")
        }

        // Delete local cache directory (sync state, node cache, pending changes)
        let documentsPath = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheDir = documentsPath.appendingPathComponent("Lineout-ly-cache")
        if fm.fileExists(atPath: cacheDir.path) {
            try? fm.removeItem(at: cacheDir)
            print("[Reset] Deleted cache dir: \(cacheDir.path)")
        }

        // Clear iCloud key-value store (settings)
        let store = NSUbiquitousKeyValueStore.default
        for key in ["weekStartDay", "autocompleteEnabled", "defaultFontSize", "focusModeEnabled"] {
            store.removeObject(forKey: key)
        }
        store.synchronize()
        print("[Reset] Cleared iCloud KV store")

        // Clear UserDefaults migration flag
        UserDefaults.standard.removeObject(forKey: "cloudkit_migration_complete_v1")
        print("[Reset] Cleared UserDefaults")
    }
}

// MARK: - Errors

enum iCloudError: LocalizedError {
    case containerNotAvailable
    case loadFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "iCloud container is not available. Please sign into iCloud."
        case .loadFailed:
            return "Failed to load document from iCloud."
        case .saveFailed:
            return "Failed to save document to iCloud."
        }
    }
}
