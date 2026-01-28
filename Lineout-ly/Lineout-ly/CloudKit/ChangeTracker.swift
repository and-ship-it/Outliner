//
//  ChangeTracker.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation

/// Tracks dirty (modified) and deleted node UUIDs pending CloudKit sync.
/// Persists pending changes to disk so they survive app termination.
@Observable
@MainActor
final class ChangeTracker {
    static let shared = ChangeTracker()

    /// Node UUIDs that have been modified locally and need to be pushed to CloudKit
    private(set) var dirtyNodeIds: Set<UUID> = []

    /// Node UUIDs that have been deleted locally and need deletion pushed to CloudKit
    private(set) var pendingDeletions: Set<UUID> = []

    /// Whether there are any pending changes
    var hasPendingChanges: Bool {
        !dirtyNodeIds.isEmpty || !pendingDeletions.isEmpty
    }

    /// Total pending change count
    var pendingChangeCount: Int {
        dirtyNodeIds.count + pendingDeletions.count
    }

    private let fileManager = FileManager.default

    private init() {
        loadFromDisk()
    }

    // MARK: - Mark Changes

    /// Mark a single node as dirty (modified)
    func markDirty(_ nodeId: UUID) {
        dirtyNodeIds.insert(nodeId)
        // If a node is re-created after deletion, remove from deletions
        pendingDeletions.remove(nodeId)
        schedulePersist()
    }

    /// Mark multiple nodes as dirty
    func markDirty(_ nodeIds: Set<UUID>) {
        dirtyNodeIds.formUnion(nodeIds)
        pendingDeletions.subtract(nodeIds)
        schedulePersist()
    }

    /// Mark multiple nodes as dirty (from array)
    func markDirty(_ nodeIds: [UUID]) {
        markDirty(Set(nodeIds))
    }

    /// Enqueue a node deletion (and all its descendants)
    func markDeleted(_ nodeId: UUID) {
        pendingDeletions.insert(nodeId)
        // No need to sync a deleted node's content
        dirtyNodeIds.remove(nodeId)
        schedulePersist()
    }

    /// Enqueue multiple node deletions
    func markDeleted(_ nodeIds: Set<UUID>) {
        pendingDeletions.formUnion(nodeIds)
        dirtyNodeIds.subtract(nodeIds)
        schedulePersist()
    }

    /// Mark a node and all its descendants as deleted
    func markDeletedWithDescendants(_ node: OutlineNode) {
        var ids = Set<UUID>()
        ids.insert(node.id)
        for descendant in node.flattened() {
            ids.insert(descendant.id)
        }
        markDeleted(ids)
    }

    // MARK: - Consume Changes (called by sync engine)

    /// Remove node IDs from dirty set after successful sync
    func clearDirty(_ nodeIds: Set<UUID>) {
        dirtyNodeIds.subtract(nodeIds)
        schedulePersist()
    }

    /// Remove node IDs from deletion set after successful sync
    func clearDeletions(_ nodeIds: Set<UUID>) {
        pendingDeletions.subtract(nodeIds)
        schedulePersist()
    }

    /// Clear all pending changes (e.g., after full sync)
    func clearAll() {
        dirtyNodeIds.removeAll()
        pendingDeletions.removeAll()
        schedulePersist()
    }

    // MARK: - Persistence

    private var persistURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Lineout-ly-cache").appendingPathComponent("pending_changes.json")
    }

    private var persistTask: Task<Void, Never>?

    /// Debounced persist to disk
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveToDisk()
        }
    }

    /// Save pending changes to disk immediately
    func saveToDisk() {
        let state = PendingChangesState(
            dirtyNodeIds: Array(dirtyNodeIds),
            pendingDeletions: Array(pendingDeletions)
        )

        do {
            let data = try JSONEncoder().encode(state)
            let dir = persistURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try data.write(to: persistURL, options: .atomic)
            print("[ChangeTracker] Persisted \(dirtyNodeIds.count) dirty, \(pendingDeletions.count) deletions")
        } catch {
            print("[ChangeTracker] Failed to persist: \(error)")
        }
    }

    /// Load pending changes from disk
    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: persistURL.path) else { return }

        do {
            let data = try Data(contentsOf: persistURL)
            let state = try JSONDecoder().decode(PendingChangesState.self, from: data)
            dirtyNodeIds = Set(state.dirtyNodeIds)
            pendingDeletions = Set(state.pendingDeletions)
            print("[ChangeTracker] Loaded \(dirtyNodeIds.count) dirty, \(pendingDeletions.count) deletions from disk")
        } catch {
            print("[ChangeTracker] Failed to load from disk: \(error)")
        }
    }
}

// MARK: - Persistence Model

private struct PendingChangesState: Codable {
    let dirtyNodeIds: [UUID]
    let pendingDeletions: [UUID]
}
