//
//  SettingsManager.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

import Foundation
import SwiftUI

/// Manages app settings with iCloud sync across devices
@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Settings Keys
    private enum Keys {
        static let weekStartDay = "weekStartDay"
        static let autocompleteEnabled = "autocompleteEnabled"
        static let defaultFontSize = "defaultFontSize"
        static let focusModeEnabled = "focusModeEnabled"
    }

    // MARK: - Settings Properties

    /// Day the week starts on (0 = Sunday, 1 = Monday, 6 = Saturday)
    var weekStartDay: Int {
        didSet {
            save(weekStartDay, forKey: Keys.weekStartDay)
        }
    }

    /// Whether word autocomplete is enabled
    var autocompleteEnabled: Bool {
        didSet {
            save(autocompleteEnabled, forKey: Keys.autocompleteEnabled)
        }
    }

    /// Default font size for new windows
    var defaultFontSize: Double {
        didSet {
            save(defaultFontSize, forKey: Keys.defaultFontSize)
        }
    }

    /// Whether focus mode dims non-focused bullets
    var focusModeEnabled: Bool {
        didSet {
            save(focusModeEnabled, forKey: Keys.focusModeEnabled)
        }
    }

    // MARK: - iCloud Key-Value Store

    private let store = NSUbiquitousKeyValueStore.default

    private init() {
        // Load initial values from iCloud (or use defaults)
        weekStartDay = store.object(forKey: Keys.weekStartDay) as? Int ?? 0
        autocompleteEnabled = store.object(forKey: Keys.autocompleteEnabled) as? Bool ?? true
        defaultFontSize = store.object(forKey: Keys.defaultFontSize) as? Double ?? 13.0
        focusModeEnabled = store.object(forKey: Keys.focusModeEnabled) as? Bool ?? false

        // Observe iCloud changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )

        // Synchronize to ensure we have latest values
        store.synchronize()
    }

    // MARK: - Save to iCloud

    private func save(_ value: Any, forKey key: String) {
        store.set(value, forKey: key)
        store.synchronize()
    }

    // MARK: - iCloud Change Notification

    @objc private func iCloudDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        // Only process server changes or initial sync
        guard changeReason == NSUbiquitousKeyValueStoreServerChange ||
              changeReason == NSUbiquitousKeyValueStoreInitialSyncChange else {
            return
        }

        // Get changed keys
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        // Update local values on main actor
        Task { @MainActor in
            for key in changedKeys {
                switch key {
                case Keys.weekStartDay:
                    if let value = store.object(forKey: key) as? Int {
                        weekStartDay = value
                    }
                case Keys.autocompleteEnabled:
                    if let value = store.object(forKey: key) as? Bool {
                        autocompleteEnabled = value
                    }
                case Keys.defaultFontSize:
                    if let value = store.object(forKey: key) as? Double {
                        defaultFontSize = value
                    }
                case Keys.focusModeEnabled:
                    if let value = store.object(forKey: key) as? Bool {
                        focusModeEnabled = value
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Week Start Day Helpers

    var weekStartDayName: String {
        switch weekStartDay {
        case 0: return "Sunday"
        case 1: return "Monday"
        case 6: return "Saturday"
        default: return "Sunday"
        }
    }

    func setWeekStartDay(_ name: String) {
        switch name.lowercased() {
        case "sunday": weekStartDay = 0
        case "monday": weekStartDay = 1
        case "saturday": weekStartDay = 6
        default: weekStartDay = 0
        }
    }
}
