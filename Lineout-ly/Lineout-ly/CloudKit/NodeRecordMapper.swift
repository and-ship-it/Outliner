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

        // Reminder sync fields
        record["reminderIdentifier"] = node.reminderIdentifier as CKRecordValue?
        record["reminderListName"] = node.reminderListName as CKRecordValue?
        if let hour = node.reminderTimeHour {
            record["reminderTimeHour"] = hour as CKRecordValue
        } else {
            record["reminderTimeHour"] = nil
        }
        if let minute = node.reminderTimeMinute {
            record["reminderTimeMinute"] = minute as CKRecordValue
        } else {
            record["reminderTimeMinute"] = nil
        }
        record["reminderChildType"] = node.reminderChildType as CKRecordValue?
        record["isReminderCompleted"] = (node.isReminderCompleted ? 1 : 0) as CKRecordValue

        // Date node fields
        record["isDateNode"] = (node.isDateNode ? 1 : 0) as CKRecordValue
        if let dateNodeDate = node.dateNodeDate {
            record["dateNodeDate"] = dateNodeDate as CKRecordValue
        } else {
            record["dateNodeDate"] = nil
        }

        // Section & calendar fields
        record["sectionType"] = node.sectionType as CKRecordValue?
        record["calendarEventIdentifier"] = node.calendarEventIdentifier as CKRecordValue?
        record["calendarName"] = node.calendarName as CKRecordValue?
        record["isPlaceholder"] = (node.isPlaceholder ? 1 : 0) as CKRecordValue

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
        let reminderIdentifier: String?
        let reminderListName: String?
        let reminderTimeHour: Int?
        let reminderTimeMinute: Int?
        let reminderChildType: String?
        let isReminderCompleted: Bool
        let isDateNode: Bool
        let dateNodeDate: Date?
        let sectionType: String?
        let calendarEventIdentifier: String?
        let calendarName: String?
        let isPlaceholder: Bool
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

        // Reminder sync fields
        let reminderIdentifier = record["reminderIdentifier"] as? String
        let reminderListName = record["reminderListName"] as? String
        let reminderTimeHour: Int? = (record["reminderTimeHour"] as? Int64).map { Int($0) }
        let reminderTimeMinute: Int? = (record["reminderTimeMinute"] as? Int64).map { Int($0) }
        let reminderChildType = record["reminderChildType"] as? String
        let isReminderCompleted = (record["isReminderCompleted"] as? Int64 ?? 0) != 0
        let isDateNode = (record["isDateNode"] as? Int64 ?? 0) != 0
        let dateNodeDate = record["dateNodeDate"] as? Date
        let sectionType = record["sectionType"] as? String
        let calendarEventIdentifier = record["calendarEventIdentifier"] as? String
        let calendarName = record["calendarName"] as? String
        let isPlaceholder = (record["isPlaceholder"] as? Int64 ?? 0) != 0

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
            systemFieldsData: systemFieldsData,
            reminderIdentifier: reminderIdentifier,
            reminderListName: reminderListName,
            reminderTimeHour: reminderTimeHour,
            reminderTimeMinute: reminderTimeMinute,
            reminderChildType: reminderChildType,
            isReminderCompleted: isReminderCompleted,
            isDateNode: isDateNode,
            dateNodeDate: dateNodeDate,
            sectionType: sectionType,
            calendarEventIdentifier: calendarEventIdentifier,
            calendarName: calendarName,
            isPlaceholder: isPlaceholder
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
