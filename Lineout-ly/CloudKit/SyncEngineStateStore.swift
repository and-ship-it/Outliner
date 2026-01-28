//
//  SyncEngineStateStore.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CloudKit

/// Persists CKSyncEngine.State.Serialization to disk so the sync engine
/// can resume from where it left off without re-fetching all records.
final class SyncEngineStateStore {

    private let fileURL: URL

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheDir = documentsPath.appendingPathComponent("Lineout-ly-cache")
        self.fileURL = cacheDir.appendingPathComponent("sync_engine_state.json")
    }

    /// Load persisted sync engine state, or return nil if none exists
    func load() -> CKSyncEngine.State.Serialization? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[SyncState] No persisted state found")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
            print("[SyncState] Loaded persisted sync engine state")
            return state
        } catch {
            print("[SyncState] Failed to load state: \(error)")
            return nil
        }
    }

    /// Save sync engine state to disk
    func save(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let data = try JSONEncoder().encode(serialization)
            try data.write(to: fileURL, options: .atomic)
            print("[SyncState] Saved sync engine state")
        } catch {
            print("[SyncState] Failed to save state: \(error)")
        }
    }
}
