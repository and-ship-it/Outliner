//
//  CloudKitSyncEngine.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CloudKit

/// Coordinates bidirectional CloudKit sync using CKSyncEngine (iOS 17+/macOS 14+).
/// Each OutlineNode is one CKRecord. One CKRecordZone per week.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
final class CloudKitSyncEngine {
    static let shared = CloudKitSyncEngine()

    private var syncEngine: CKSyncEngine?
    private let stateStore = SyncEngineStateStore()
    private let database = CKContainer(identifier: "iCloud.computer.daydreamlab.Lineout-ly").privateCloudDatabase

    /// Whether sync has been set up
    private(set) var isSetUp = false

    /// Current zone ID (based on current week)
    private var currentZoneID: CKRecordZone.ID {
        let weekFile = iCloudManager.shared.currentWeekFileName
        return NodeRecordMapper.zoneID(for: weekFile)
    }

    private init() {}

    // MARK: - Setup

    /// Initialize the sync engine. Call once after document is loaded.
    func setup() async {
        guard !isSetUp else { return }

        let savedState = stateStore.load()

        let config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: savedState,
            delegate: self
        )

        syncEngine = CKSyncEngine(config)
        isSetUp = true
        print("[CKSync] Sync engine set up")

        // Ensure zone exists before any records are sent
        await ensureZoneExists()
    }

    /// Create the zone if it doesn't exist yet
    private func ensureZoneExists() async {
        let zone = CKRecordZone(zoneID: currentZoneID)
        do {
            try await database.save(zone)
            print("[CKSync] Zone ensured: \(currentZoneID.zoneName)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Zone might already exist, that's fine
            print("[CKSync] Zone already exists: \(currentZoneID.zoneName)")
        } catch {
            print("[CKSync] Failed to create zone: \(error)")
        }
    }

    // MARK: - Outbound Sync

    /// Schedule pending changes to be sent to CloudKit.
    /// Called after mutations mark nodes dirty in ChangeTracker.
    func schedulePendingChanges() {
        guard let engine = syncEngine else { return }

        let tracker = ChangeTracker.shared
        guard tracker.hasPendingChanges else { return }

        // Enqueue record changes for dirty nodes
        var pendingChanges: [CKSyncEngine.PendingRecordZoneChange] = []

        for nodeId in tracker.dirtyNodeIds {
            let recordID = NodeRecordMapper.recordID(for: nodeId, in: currentZoneID)
            pendingChanges.append(.saveRecord(recordID))
        }

        for nodeId in tracker.pendingDeletions {
            let recordID = NodeRecordMapper.recordID(for: nodeId, in: currentZoneID)
            pendingChanges.append(.deleteRecord(recordID))
        }

        if !pendingChanges.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pendingChanges)
            print("[CKSync] Enqueued \(pendingChanges.count) pending changes")
        }
    }

    // MARK: - Fetch

    /// Explicitly fetch changes from CloudKit (e.g., on foreground return)
    func fetchChanges() async {
        guard let engine = syncEngine else { return }

        do {
            try await engine.fetchChanges()
            print("[CKSync] Fetched changes on demand")
        } catch {
            print("[CKSync] Fetch changes failed: \(error)")
        }
    }

    // MARK: - Flush

    /// Flush all pending changes synchronously (for background transition)
    func flushPendingChanges() async {
        guard let engine = syncEngine else { return }
        schedulePendingChanges()

        do {
            try await engine.sendChanges()
            print("[CKSync] Flushed pending changes")
        } catch {
            print("[CKSync] Flush failed: \(error)")
        }
    }
}

// MARK: - CKSyncEngineDelegate

@available(macOS 14.0, iOS 17.0, *)
extension CloudKitSyncEngine: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        Task { @MainActor in
            switch event {
            case .stateUpdate(let stateUpdate):
                stateStore.save(stateUpdate.stateSerialization)

            case .accountChange(let accountChange):
                handleAccountChange(accountChange)

            case .fetchedDatabaseChanges(let fetchedChanges):
                handleFetchedDatabaseChanges(fetchedChanges)

            case .fetchedRecordZoneChanges(let fetchedChanges):
                handleFetchedRecordZoneChanges(fetchedChanges)

            case .sentRecordZoneChanges(let sentChanges):
                handleSentRecordZoneChanges(sentChanges)

            case .sentDatabaseChanges:
                break

            case .willFetchChanges:
                print("[CKSync] Will fetch changes")

            case .didFetchChanges:
                print("[CKSync] Did fetch changes")

            case .willSendChanges:
                print("[CKSync] Will send changes")

            case .didSendChanges:
                print("[CKSync] Did send changes")

            case .willFetchRecordZoneChanges:
                break

            case .didFetchRecordZoneChanges:
                break

            @unknown default:
                print("[CKSync] Unknown event: \(event)")
            }
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges
        guard !pendingChanges.isEmpty else { return nil }

        // Build all CKRecords from document state on main actor
        let document = await MainActor.run { WindowManager.shared.document }
        guard let document else { return nil }

        let weekFile = await MainActor.run { iCloudManager.shared.currentWeekFileName }
        let zoneID = await MainActor.run { NodeRecordMapper.zoneID(for: weekFile) }

        var prebuiltRecords: [CKRecord.ID: CKRecord] = [:]

        for change in pendingChanges {
            switch change {
            case .saveRecord(let recordID):
                let record: CKRecord? = await MainActor.run {
                    guard let nodeId = UUID(uuidString: recordID.recordName),
                          let node = document.root.find(id: nodeId) else { return nil }
                    let parentId = node.parent?.isRoot == true ? nil : node.parent?.id
                    return NodeRecordMapper.record(from: node, parentId: parentId, zoneID: zoneID)
                }
                if let record {
                    prebuiltRecords[recordID] = record
                }
            case .deleteRecord:
                break // Deletions don't need records
            @unknown default:
                break
            }
        }

        let finalRecords = prebuiltRecords
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: Array(pendingChanges)) { recordID in
            finalRecords[recordID]
        }
    }

    // MARK: - Event Handlers

    @MainActor
    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            print("[CKSync] Account signed in")
        case .signOut:
            print("[CKSync] Account signed out")
        case .switchAccounts:
            print("[CKSync] Account switched")
        @unknown default:
            break
        }
    }

    @MainActor
    private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
        // Handle zone deletions (e.g., if another device deleted a week zone)
        for deletion in changes.deletions {
            print("[CKSync] Zone deleted: \(deletion.zoneID.zoneName)")
        }
    }

    @MainActor
    private func handleFetchedRecordZoneChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        guard let document = WindowManager.shared.document else { return }

        // Process modifications (upserts)
        var remoteChanges: [NodeRecordMapper.RemoteNodeChange] = []
        for modification in changes.modifications {
            if let change = NodeRecordMapper.remoteChange(from: modification.record) {
                remoteChanges.append(change)
            }
        }

        if !remoteChanges.isEmpty {
            document.applyRemoteChanges(remoteChanges)
        }

        // Process deletions
        let deletedIds = changes.deletions.compactMap { UUID(uuidString: $0.recordID.recordName) }
        if !deletedIds.isEmpty {
            document.applyRemoteDeletions(deletedIds)
        }

        // Save updated cache
        do {
            try LocalNodeCache.shared.save(document.root)
        } catch {
            print("[CKSync] Failed to save cache after remote changes: \(error)")
        }
    }

    @MainActor
    private func handleSentRecordZoneChanges(_ sentChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        let tracker = ChangeTracker.shared

        // Handle successful saves
        var savedIds = Set<UUID>()
        for savedRecord in sentChanges.savedRecords {
            if let nodeId = UUID(uuidString: savedRecord.recordID.recordName) {
                savedIds.insert(nodeId)

                // Update system fields on the local node for future partial updates
                if let document = WindowManager.shared.document,
                   let node = document.root.find(id: nodeId) {
                    node.cloudKitSystemFields = NodeRecordMapper.encodeSystemFields(savedRecord)
                }
            }
        }
        if !savedIds.isEmpty {
            tracker.clearDirty(savedIds)
            print("[CKSync] Successfully saved \(savedIds.count) records")
        }

        // Handle successful deletions
        var deletedIds = Set<UUID>()
        for deletedID in sentChanges.deletedRecordIDs {
            if let nodeId = UUID(uuidString: deletedID.recordName) {
                deletedIds.insert(nodeId)
            }
        }
        if !deletedIds.isEmpty {
            tracker.clearDeletions(deletedIds)
            print("[CKSync] Successfully deleted \(deletedIds.count) records")
        }

        // Handle failures
        for failedSave in sentChanges.failedRecordSaves {
            let error = failedSave.error

            if error.code == .serverRecordChanged {
                // Conflict — resolve using field-level merge
                handleConflict(failedSave)
            } else {
                print("[CKSync] Save failed for \(failedSave.record.recordID.recordName): \(error)")
            }
        }
    }

    // MARK: - Conflict Resolution

    @MainActor
    private func handleConflict(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        guard let serverRecord = failedSave.error.serverRecord else {
            print("[CKSync] Conflict but no server record available")
            return
        }

        let clientRecord = failedSave.record
        let ancestorRecord = failedSave.error.ancestorRecord

        let resolved = ConflictResolver.resolve(
            client: clientRecord,
            server: serverRecord,
            ancestor: ancestorRecord
        )

        // Re-enqueue the resolved record
        let recordID = resolved.recordID
        syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        print("[CKSync] Resolved conflict for \(recordID.recordName), re-enqueued")
    }
}
