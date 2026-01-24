//
//  iCloudManager.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import Foundation
import Combine

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

    // MARK: - Constants

    private let containerIdentifier = "iCloud.computer.daydreamlab.Lineout-ly"
    private let folderName = "Lineout-ly"
    private let mainFileName = "main.md"
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
        appFolderURL?.appendingPathComponent(mainFileName)
    }

    var trashFolderURL: URL? {
        appFolderURL?.appendingPathComponent(trashFolderName)
    }

    // MARK: - Initialization

    private init() {
        checkICloudAvailability()
    }

    // MARK: - iCloud Setup

    /// Check if iCloud is available and get the container URL
    func checkICloudAvailability() {
        // Check if user is signed into iCloud
        guard FileManager.default.ubiquityIdentityToken != nil else {
            isICloudAvailable = false
            containerURL = nil
            print("[iCloud] Not signed in to iCloud")
            return
        }

        // Get the container URL synchronously
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            self.containerURL = url
            self.isICloudAvailable = true
            print("[iCloud] Container available at: \(url.path)")
        } else {
            self.isICloudAvailable = false
            self.containerURL = nil
            print("[iCloud] Container not available for: \(containerIdentifier)")
        }
    }

    /// Setup folder structure on first launch
    func setupOnFirstLaunch() async throws {
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

        // Create main file if needed
        if let mainFile = mainFileURL, !fileManager.fileExists(atPath: mainFile.path) {
            // Create empty document
            let emptyContent = "- \n"
            try emptyContent.write(to: mainFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Document Loading

    /// Load the main document from iCloud
    func loadDocument() async throws -> OutlineDocument {
        isLoading = true
        defer { isLoading = false }

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
        localFallbackURL.appendingPathComponent(mainFileName)
    }

    /// Load from local storage if iCloud is unavailable
    func loadLocalDocument() throws -> OutlineDocument {
        let fileManager = FileManager.default

        // Create local folder if needed
        if !fileManager.fileExists(atPath: localFallbackURL.path) {
            try fileManager.createDirectory(at: localFallbackURL, withIntermediateDirectories: true)
        }

        // Create or load main file
        if fileManager.fileExists(atPath: localMainFileURL.path) {
            let markdown = try String(contentsOf: localMainFileURL, encoding: .utf8)
            let root = MarkdownCodec.parse(markdown)
            return OutlineDocument(root: root)
        } else {
            // Create empty document
            let emptyContent = "- \n"
            try emptyContent.write(to: localMainFileURL, atomically: true, encoding: .utf8)
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
