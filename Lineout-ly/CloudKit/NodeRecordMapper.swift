//
//  NodeRecordMapper.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CloudKit

/// Maps OutlineNode ↔ CKRecord for CloudKit sync.
/// Each OutlineNode becomes one CKRecord in a week-specific zone.
struct NodeRecordMapper {

    /// CKRecord type for outline nodes
    static let recordType = "OutlineNode"

    // MARK: - Zone Helpers

    /// Create a CKRecordZone.ID for a given week filename
    /// e.g., "2026-Jan-W05.md" → zone named "week-2026-Jan-W05"
    static func zoneID(for weekFileName: String) -> CKRecordZone.ID {
        let zoneName = "week-" + weekFileName.replacingOccurrences(of: ".md", with: "")
        return CKRecordZone.ID(zoneName: zoneName)
    }

    /// Record ID for a node in a given zone
    static func recordID(for nodeId: UUID, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: nodeId.uuidString, zoneID: zoneID)
    }

    // MARK: - OutlineNode → CKRecord

    /// Convert an OutlineNode to a CKRecord.
    /// If the node has saved system fields (from a previous fetch), those are used
    /// to enable partial updates.
    static func record(from node: OutlineNode, parentId: UUID?, zoneID: CKRecordZone.ID) -> CKRecord {
        let record: CKRecord

        // Try to restore from saved system fields for partial update
        if let systemFieldsData = node.cloudKitSystemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFieldsData) {
            coder.requiresSecureCoding = true
            if let restored = CKRecord(coder: coder) {
                record = restored
            } else {
                record = CKRecord(recordType: recordType, recordID: recordID(for: node.id, in: zoneID))
            }
            coder.finishDecoding()
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID(for: node.id, in: zoneID))
        }

        // Set all fields
        record["title"] = node.title as CKRecordValue
        record["body"] = node.body as CKRecordValue
        record["isTask"] = (node.isTask ? 1 : 0) as CKRecordValue
        record["isTaskCompleted"] = (node.isTaskCompleted ? 1 : 0) as CKRecordValue
        record["sortIndex"] = node.sortIndex as CKRecordValue
        record["modifiedLocally"] = node.lastModifiedLocally as CKRecordValue

        // Parent reference (nil for top-level nodes)
        if let parentId = parentId {
            let parentRecordID = recordID(for: parentId, in: zoneID)
            record["parentRef"] = CKRecord.Reference(recordID: parentRecordID, action: .none)
        } else {
            record["parentRef"] = nil
        }

        return record
    }

    // MARK: - CKRecord → OutlineNode update

    /// Value object representing a remote node change to apply to the local tree
    struct RemoteNodeChange {
        let nodeId: UUID
        let title: String
        let body: String
        let isTask: Bool
        let isTaskCompleted: Bool
        let parentId: UUID?
        let sortIndex: Int64
        let modifiedLocally: Date
        let systemFieldsData: Data
    }

    /// Extract node data from a CKRecord
    static func remoteChange(from record: CKRecord) -> RemoteNodeChange? {
        guard let nodeId = UUID(uuidString: record.recordID.recordName) else { return nil }

        let title = record["title"] as? String ?? ""
        let body = record["body"] as? String ?? ""
        let isTask = (record["isTask"] as? Int64 ?? 0) != 0
        let isTaskCompleted = (record["isTaskCompleted"] as? Int64 ?? 0) != 0
        let sortIndex = record["sortIndex"] as? Int64 ?? 0
        let modifiedLocally = record["modifiedLocally"] as? Date ?? Date.distantPast

        // Extract parent UUID from reference
        var parentId: UUID? = nil
        if let parentRef = record["parentRef"] as? CKRecord.Reference {
            parentId = UUID(uuidString: parentRef.recordID.recordName)
        }

        // Encode system fields for future partial updates
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        let systemFieldsData = coder.encodedData

        return RemoteNodeChange(
            nodeId: nodeId,
            title: title,
            body: body,
            isTask: isTask,
            isTaskCompleted: isTaskCompleted,
            parentId: parentId,
            sortIndex: sortIndex,
            modifiedLocally: modifiedLocally,
            systemFieldsData: systemFieldsData
        )
    }

    // MARK: - System Fields Encoding

    /// Encode CKRecord system fields to Data for local storage
    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }
}
