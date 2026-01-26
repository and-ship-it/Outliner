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

        // Get the container URL on a background thread with timeout
        // The FileManager call can block indefinitely, so we use a race
        let containerIdCopy = containerIdentifier

        do {
            let url = try await withThrowingTaskGroup(of: URL?.self) { group in
                // Task 1: Fetch the container URL (can block)
                group.addTask {
                    return FileManager.default.url(forUbiquityContainerIdentifier: containerIdCopy)
                }

                // Task 2: Timeout after 5 seconds
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }

                // Return first successful result
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                return nil
            }

            if let url {
                self.containerURL = url
                self.isICloudAvailable = true
                print("[iCloud] Container available at: \(url.path)")
            } else {
                self.isICloudAvailable = false
                self.containerURL = nil
                print("[iCloud] Container not available for: \(containerIdentifier)")
            }
        } catch {
            // Timeout or cancellation
            print("[iCloud] Container lookup timed out - falling back to local")
            self.isICloudAvailable = false
            self.containerURL = nil
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

        // Use file coordination for safe reading
        var loadError: Error?
        var loadedDocument: OutlineDocument?

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: mainFile, options: [], error: &coordinatorError) { url in
            do {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                let root = MarkdownCodec.parse(markdown)
                loadedDocument = OutlineDocument(root: root)
            } catch {
                loadError = error
            }
        }

        if let error = coordinatorError ?? loadError {
            lastError = error
            throw error
        }

        guard let document = loadedDocument else {
            throw iCloudError.loadFailed
        }

        return document
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

        let markdown = MarkdownCodec.serialize(document.root)
        print("[iCloud] Saving to: \(mainFile.path)")
        print("[iCloud] Content length: \(markdown.count) chars")

        // Use file coordination for safe writing
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(writingItemAt: mainFile, options: .forReplacing, error: &coordinatorError) { url in
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                self.lastError = nil
                print("[iCloud] Save successful")
            } catch {
                print("[iCloud] Save error: \(error)")
                self.lastError = error
            }
        }

        if let error = coordinatorError {
            print("[iCloud] Coordinator error: \(error)")
            lastError = error
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
