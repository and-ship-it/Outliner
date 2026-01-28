//
//  CloudKitShared.swift
//  ShareExtension
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CloudKit

/// Lightweight CloudKit helper for the Share Extension.
/// Uses direct CKDatabase.save() since CKSyncEngine is too heavyweight for extensions.
/// Records use the same schema and zone naming as the main app's CloudKitSyncEngine.
enum CloudKitShared {

    private static let containerID = "iCloud.computer.daydreamlab.Lineout-ly"
    private static let recordType = "OutlineNode"
    private static let sortIndexGap: Int64 = 10_000

    // MARK: - Public API

    /// Save shared content as CKRecords to CloudKit.
    /// Creates a "Shared" parent node (if not found) and adds child nodes under it.
    /// Returns true on success, false on failure (caller should fall back to markdown).
    static func saveSharedContent(description: String, content: String, isLink: Bool) async -> Bool {
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        let zoneID = currentZoneID()

        do {
            // Ensure zone exists
            let zone = CKRecordZone(zoneID: zoneID)
            do {
                try await database.save(zone)
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // Zone already exists — fine
            }

            // Find or create "Shared" parent node
            let sharedRecord = try await findOrCreateSharedNode(in: database, zoneID: zoneID)
            let sharedRecordID = sharedRecord.recordID

            // Determine sort index for new child (after existing children)
            let nextSortIndex = try await nextChildSortIndex(
                parentRecordID: sharedRecordID,
                in: database,
                zoneID: zoneID
            )

            // Build child records
            var recordsToSave: [CKRecord] = []

            if isLink {
                // Single child: description + link content
                let childRecord = makeNodeRecord(
                    title: content,
                    parentRecordID: sharedRecordID,
                    sortIndex: nextSortIndex,
                    zoneID: zoneID
                )
                recordsToSave.append(childRecord)
            } else {
                // Text content — parse lines
                let lines = content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if lines.count <= 1 {
                    let childRecord = makeNodeRecord(
                        title: lines.first ?? content,
                        parentRecordID: sharedRecordID,
                        sortIndex: nextSortIndex,
                        zoneID: zoneID
                    )
                    recordsToSave.append(childRecord)
                } else {
                    // Description node as child of Shared
                    let descRecord = makeNodeRecord(
                        title: description,
                        parentRecordID: sharedRecordID,
                        sortIndex: nextSortIndex,
                        zoneID: zoneID
                    )
                    recordsToSave.append(descRecord)

                    // Each line as grandchild of description
                    for (i, line) in lines.enumerated() {
                        let lineRecord = makeNodeRecord(
                            title: line,
                            parentRecordID: descRecord.recordID,
                            sortIndex: Int64(i) * sortIndexGap,
                            zoneID: zoneID
                        )
                        recordsToSave.append(lineRecord)
                    }
                }
            }

            // Also save the Shared node if it was newly created
            recordsToSave.insert(sharedRecord, at: 0)

            // Batch save
            let modifyOp = CKModifyRecordsOperation(recordsToSave: recordsToSave)
            modifyOp.savePolicy = .changedKeys
            modifyOp.qualityOfService = .userInitiated

            _ = try await database.modifyRecords(saving: recordsToSave, deleting: [], savePolicy: .changedKeys)
            print("[CloudKitShared] Saved \(recordsToSave.count) records to CloudKit")
            return true

        } catch {
            print("[CloudKitShared] Failed to save: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    /// Get zone ID matching the main app's convention
    private static func currentZoneID() -> CKRecordZone.ID {
        let weekFile = currentWeekFileName()
        let zoneName = "week-" + weekFile.replacingOccurrences(of: ".md", with: "")
        return CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Week filename matching the main app's convention
    private static func currentWeekFileName() -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let weekOfYear = calendar.component(.weekOfYear, from: Date())

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        let weekday = calendar.component(.weekday, from: Date())
        // Read from iCloud KVS (synced setting), fall back to Monday (2)
        let weekStart = NSUbiquitousKeyValueStore.default.object(forKey: "weekStartDay") as? Int ?? 2
        let startDay = weekStart > 0 ? weekStart : 2
        let daysToSubtract = (weekday - startDay + 7) % 7
        let firstDayOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: Date()) ?? Date()
        let monthName = monthFormatter.string(from: firstDayOfWeek)

        return String(format: "%d-%@-W%02d.md", year, monthName, weekOfYear)
    }

    /// Find existing "Shared" node or create a new one at root level
    private static func findOrCreateSharedNode(
        in database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> CKRecord {
        // Query for a root-level node with title "Shared"
        let predicate = NSPredicate(format: "title == %@ AND parentRef == nil", "Shared")
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let (results, _) = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: ["title", "sortIndex"],
            resultsLimit: 1
        )

        // If found, return it
        for (_, result) in results {
            if case .success(let record) = result {
                return record
            }
        }

        // Not found — create new "Shared" node at root level
        // Use a high sortIndex so it appears near the top
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(
            recordName: UUID().uuidString,
            zoneID: zoneID
        ))
        record["title"] = "Shared" as CKRecordValue
        record["body"] = "" as CKRecordValue
        record["isTask"] = 0 as CKRecordValue
        record["isTaskCompleted"] = 0 as CKRecordValue
        record["sortIndex"] = 0 as CKRecordValue
        record["modifiedLocally"] = Date() as CKRecordValue
        // No parentRef — root level

        return record
    }

    /// Get the next available sortIndex for children of a parent node
    private static func nextChildSortIndex(
        parentRecordID: CKRecord.ID,
        in database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> Int64 {
        let parentRef = CKRecord.Reference(recordID: parentRecordID, action: .none)
        let predicate = NSPredicate(format: "parentRef == %@", parentRef)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: false)]

        let (results, _) = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: ["sortIndex"],
            resultsLimit: 1
        )

        for (_, result) in results {
            if case .success(let record) = result,
               let maxSort = record["sortIndex"] as? Int64 {
                return maxSort + sortIndexGap
            }
        }

        return 0 // First child
    }

    /// Create a CKRecord for a node
    private static func makeNodeRecord(
        title: String,
        parentRecordID: CKRecord.ID,
        sortIndex: Int64,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        record["title"] = title as CKRecordValue
        record["body"] = "" as CKRecordValue
        record["isTask"] = 0 as CKRecordValue
        record["isTaskCompleted"] = 0 as CKRecordValue
        record["parentRef"] = CKRecord.Reference(recordID: parentRecordID, action: .none) as CKRecordValue
        record["sortIndex"] = sortIndex as CKRecordValue
        record["modifiedLocally"] = Date() as CKRecordValue

        return record
    }
}
