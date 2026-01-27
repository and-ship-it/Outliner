//
//  ConflictResolver.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import Foundation
import CloudKit

/// Resolves CloudKit conflicts using field-level merge.
/// When CKSyncEngine reports a conflict (serverRecordChanged), we get three records:
/// - client: what we tried to save
/// - server: what's currently on the server
/// - ancestor: the common ancestor (what we originally fetched)
///
/// Strategy per field:
/// - Field unchanged on client → use server value
/// - Field unchanged on server → use client value
/// - Both changed → last-write-wins by modifiedLocally timestamp
struct ConflictResolver {

    /// Merge a conflict between client and server records.
    /// Returns the resolved record to save.
    static func resolve(client: CKRecord, server: CKRecord, ancestor: CKRecord?) -> CKRecord {
        // Start with server record (preserves server's system fields)
        let resolved = server

        let fields = ["title", "body", "isTask", "isTaskCompleted", "parentRef", "sortIndex"]

        let clientModified = client["modifiedLocally"] as? Date ?? Date.distantPast
        let serverModified = server["modifiedLocally"] as? Date ?? Date.distantPast

        for field in fields {
            let clientValue = client[field]
            let serverValue = server[field]
            let ancestorValue = ancestor?[field]

            let clientChanged = !valuesEqual(clientValue, ancestorValue)
            let serverChanged = !valuesEqual(serverValue, ancestorValue)

            if clientChanged && !serverChanged {
                // Only client changed this field — use client value
                resolved[field] = clientValue
            } else if !clientChanged && serverChanged {
                // Only server changed — keep server value (already set)
            } else if clientChanged && serverChanged {
                // Both changed — last-write-wins
                if clientModified >= serverModified {
                    resolved[field] = clientValue
                }
                // else keep server value (already set)
            }
            // Neither changed — keep as-is
        }

        // Always use the later modifiedLocally timestamp
        if clientModified > serverModified {
            resolved["modifiedLocally"] = clientModified as CKRecordValue
        }

        return resolved
    }

    // MARK: - Value Comparison

    /// Compare two CKRecordValue instances for equality
    private static func valuesEqual(_ a: (any CKRecordValue)?, _ b: (any CKRecordValue)?) -> Bool {
        // Both nil
        if a == nil && b == nil { return true }
        // One nil
        guard let a = a, let b = b else { return false }

        // Compare by type
        if let a = a as? String, let b = b as? String {
            return a == b
        }
        if let a = a as? Int64, let b = b as? Int64 {
            return a == b
        }
        if let a = a as? NSNumber, let b = b as? NSNumber {
            return a == b
        }
        if let a = a as? Date, let b = b as? Date {
            return a == b
        }
        if let a = a as? CKRecord.Reference, let b = b as? CKRecord.Reference {
            return a.recordID == b.recordID
        }

        // Unknown type — assume different
        return false
    }
}
