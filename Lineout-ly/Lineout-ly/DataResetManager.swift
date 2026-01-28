//
//  DataResetManager.swift
//  Lineout-ly
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Orchestrates a complete factory reset: wipes CloudKit, iCloud Drive, local caches, and settings.
@MainActor
enum DataResetManager {

    /// Delete all data everywhere and terminate the app.
    static func deleteAllData() async {
        print("[Reset] Starting full factory reset...")

        // 1. Delete all CloudKit zones (remote data)
        if #available(macOS 14.0, iOS 17.0, *) {
            await CloudKitSyncEngine.shared.deleteAllZones()
        }

        // 2. Delete all local files, caches, and settings
        iCloudManager.shared.deleteAllLocalData()

        // 3. Clear in-memory change tracker
        ChangeTracker.shared.clearAll()

        print("[Reset] Factory reset complete. Terminating app.")

        // 4. Terminate the app so user reopens to a fresh state
        #if os(iOS)
        exit(0)
        #else
        NSApplication.shared.terminate(nil)
        #endif
    }
}
