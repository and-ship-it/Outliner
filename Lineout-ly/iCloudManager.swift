//
//  iCloudManager.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
import Combine

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

    // MARK: - Auto-Save

    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: Duration = .seconds(1)

    // MARK: - File Change Detection

    /// Last known modification date of the file (when we loaded/saved it)
    private(set) var lastKnownModificationDate: Date?

    /// Check if the file has been modified externally (by another device)
    func hasFileChangedExternally() -> Bool {
        guard let fileURL = mainFileURL ?? (isICloudAvailable ? nil : localMainFileURL) else {
            return false
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modDate = attributes[.modificationDate] as? Date {
                if let lastKnown = lastKnownModificationDate {
                    // File is newer than what we last loaded/saved
                    let hasChanged = modDate > lastKnown.addingTimeInterval(1) // 1 second tolerance
                    if hasChanged {
                        print("[iCloud] 🔄 File changed externally: last known \(lastKnown), current \(modDate)")
                    }
                    return hasChanged
                }
            }
        } catch {
            print("[iCloud] Error checking file modification: \(error)")
        }
        return false
    }

    /// Update the last known modification date (call after load/save)
    private func updateLastKnownModificationDate() {
        guard let fileURL = mainFileURL ?? (isICloudAvailable ? nil : localMainFileURL) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modDate = attributes[.modificationDate] as? Date {
                lastKnownModificationDate = modDate
                print("[iCloud] Updated last known mod date: \(modDate)")
            }
        } catch {
            print("[iCloud] Error getting file modification date: \(error)")
        }
    }

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

    /// Get the week start day from UserDefaults (default: Monday)
    var weekStartDay: WeekStartDay {
        let rawValue = UserDefaults.standard.integer(forKey: "weekStartDay")
        return WeekStartDay(rawValue: rawValue) ?? .monday
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

        // Trigger iCloud download if file is not local yet
        // This is important for syncing between devices
        try? FileManager.default.startDownloadingUbiquitousItem(at: mainFile)

        // Wait a moment for download to start (if needed)
        try? await Task.sleep(for: .milliseconds(500))

        // Move file coordination to background thread to avoid blocking main thread
        // Parse markdown on background, create document on main thread
        let root = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OutlineNode, Error>) in
            // Use userInitiated QoS for responsive loading
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var loadError: Error?
                var loadedRoot: OutlineNode?

                coordinator.coordinate(readingItemAt: mainFile, options: [], error: &coordinatorError) { url in
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

        // Create document on main thread (we're already on MainActor)
        // Track when we loaded the file
        updateLastKnownModificationDate()
        return OutlineDocument(root: root)
    }

    // MARK: - Document Saving

    /// Schedule an auto-save with debouncing
    func scheduleAutoSave(for document: OutlineDocument) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: saveDebounceInterval)
            guard !Task.isCancelled else { return }
            await save(document)
        }
    }

    /// Save the document immediately
    func save(_ document: OutlineDocument) async {
        guard let mainFile = mainFileURL else {
            print("[iCloud] Save failed: mainFileURL is nil, falling back to local")
            // Fall back to local save
            do {
                try saveLocal(document)
                print("[iCloud] Saved to local: \(localMainFileURL.path)")
            } catch {
                print("[iCloud] Local save failed: \(error)")
                lastError = error
            }
            return
        }

        // Serialize on main thread since document access should be main-thread
        let markdown = MarkdownCodec.serialize(document.root)
        print("[iCloud] Saving to: \(mainFile.path)")
        print("[iCloud] Content length: \(markdown.count) chars")

        // Move file coordination to background thread to avoid blocking main thread
        let saveResult: Error? = await withCheckedContinuation { continuation in
            // Use userInitiated QoS for responsive saving
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var writeError: Error?

                coordinator.coordinate(writingItemAt: mainFile, options: .forReplacing, error: &coordinatorError) { url in
                    do {
                        try markdown.write(to: url, atomically: true, encoding: .utf8)
                        print("[iCloud] Save successful")
                    } catch {
                        print("[iCloud] Save error: \(error)")
                        writeError = error
                    }
                }

                if let error = coordinatorError {
                    print("[iCloud] Coordinator error: \(error)")
                    continuation.resume(returning: error)
                } else if let error = writeError {
                    continuation.resume(returning: error)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }

        // Update error state back on main thread
        if let error = saveResult {
            lastError = error
        } else {
            lastError = nil
            // Track when we saved the file
            updateLastKnownModificationDate()
        }
    }

    /// Force save immediately (cancels any pending auto-save)
    func forceSave(_ document: OutlineDocument) async {
        saveTask?.cancel()
        await save(document)
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
            updateLastKnownModificationDate()
            return OutlineDocument(root: root)
        } else {
            // Create empty document for new week
            let emptyContent = "- \n"
            try emptyContent.write(to: localMainFileURL, atomically: true, encoding: .utf8)
            print("[iCloud] Created new local week file: \(currentWeekFileName)")
            updateLastKnownModificationDate()
            return OutlineDocument.createEmpty()
        }
    }

    /// Save to local storage
    func saveLocal(_ document: OutlineDocument) throws {
        let markdown = MarkdownCodec.serialize(document.root)
        try markdown.write(to: localMainFileURL, atomically: true, encoding: .utf8)
        updateLastKnownModificationDate()
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
