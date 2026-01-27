//
//  MigrationManager.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CloudKit

/// Handles one-time migration from markdown/local storage to CloudKit per-node sync.
///
/// **First device**: Enqueues all existing nodes for CloudKit upload.
/// **Second device**: Detects existing records in CloudKit zone, lets CKSyncEngine fetch them.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
final class MigrationManager {

    private static let migrationKey = "cloudkit_migration_complete_v1"

    /// Whether migration has already been completed on this device
    static var isMigrationComplete: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    /// Run migration if needed. Call after document is loaded and CKSyncEngine is set up.
    static func migrateIfNeeded(document: OutlineDocument) async {
        guard !isMigrationComplete else {
            print("[Migration] Already migrated — skipping")
            return
        }

        print("[Migration] Starting migration check...")

        // Check if CloudKit zone already has records (another device migrated first)
        let hasExistingRecords = await checkForExistingRecords()

        if hasExistingRecords {
            // Second device: CKSyncEngine will automatically fetch and apply remote records.
            // We just mark migration complete so we don't check again.
            print("[Migration] Found existing CloudKit records — second device path")
            print("[Migration] CKSyncEngine will fetch remote records automatically")
        } else {
            // First device: enqueue all nodes for CloudKit upload
            print("[Migration] No existing CloudKit records — first device path")
            enqueueAllNodesForUpload(document: document)
        }

        // Mark migration complete
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[Migration] Migration complete")
    }

    // MARK: - Check Existing Records

    /// Query CloudKit to see if the current week's zone already has records
    private static func checkForExistingRecords() async -> Bool {
        let container = CKContainer(identifier: "iCloud.computer.daydreamlab.Lineout-ly")
        let database = container.privateCloudDatabase

        let weekFile = iCloudManager.shared.currentWeekFileName
        let zoneID = NodeRecordMapper.zoneID(for: weekFile)

        do {
            // Fetch just one record to check if zone has data
            let query = CKQuery(recordType: "OutlineNode", predicate: NSPredicate(value: true))
            let (results, _) = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["title"],
                resultsLimit: 1
            )
            let hasRecords = !results.isEmpty
            print("[Migration] Zone \(zoneID.zoneName) has records: \(hasRecords)")
            return hasRecords
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone doesn't exist yet — no records
            print("[Migration] Zone not found — no existing records")
            return false
        } catch {
            // On error, assume no records and proceed with first-device path
            // If records exist, CKSyncEngine will still fetch them
            print("[Migration] Error checking zone: \(error) — assuming first device")
            return false
        }
    }

    // MARK: - First Device Migration

    /// Enqueue all nodes from the current document for CloudKit upload
    private static func enqueueAllNodesForUpload(document: OutlineDocument) {
        let allNodes = document.root.flattened()
        var nodeIds = Set<UUID>()
        for node in allNodes {
            nodeIds.insert(node.id)
        }

        // Mark all nodes as dirty in ChangeTracker
        ChangeTracker.shared.markDirty(nodeIds)

        // Schedule pending changes in CKSyncEngine
        CloudKitSyncEngine.shared.schedulePendingChanges()

        print("[Migration] Enqueued \(nodeIds.count) nodes for CloudKit upload")
    }
}
