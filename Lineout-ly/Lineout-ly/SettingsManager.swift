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
        static let selectedCalendarIds = "selectedCalendarIds"
        static let calendarIntegrationEnabled = "calendarIntegrationEnabled"
        static let reminderIntegrationEnabled = "reminderIntegrationEnabled"
        static let reminderBidirectionalSync = "reminderBidirectionalSync"
        static let selectedReminderListIds = "selectedReminderListIds"
        static let dismissedCalendarEventIds = "dismissedCalendarEventIds"
        static let dismissedReminderIds = "dismissedReminderIds"
        static let customKeyboardShortcuts = "customKeyboardShortcuts"
    }

    // MARK: - Settings Properties

    /// Day the week starts on, stored as WeekStartDay.rawValue (1=Sunday, 2=Monday, 7=Saturday)
    var weekStartDay: Int {
        didSet {
            save(weekStartDay, forKey: Keys.weekStartDay)
        }
    }

    /// Typed accessor for the week start day
    var weekStartDayValue: WeekStartDay {
        get { WeekStartDay(rawValue: weekStartDay) ?? .monday }
        set { weekStartDay = newValue.rawValue }
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

    /// Selected calendar identifiers for display (empty = all calendars)
    var selectedCalendarIds: [String] {
        didSet {
            save(selectedCalendarIds, forKey: Keys.selectedCalendarIds)
        }
    }

    // MARK: - Integration Settings

    /// Whether Apple Calendar integration is enabled
    var calendarIntegrationEnabled: Bool {
        didSet {
            save(calendarIntegrationEnabled, forKey: Keys.calendarIntegrationEnabled)
        }
    }

    /// Whether Apple Reminders integration is enabled
    var reminderIntegrationEnabled: Bool {
        didSet {
            save(reminderIntegrationEnabled, forKey: Keys.reminderIntegrationEnabled)
        }
    }

    /// Whether reminder sync is bidirectional (true) or one-way read-only (false)
    var reminderBidirectionalSync: Bool {
        didSet {
            save(reminderBidirectionalSync, forKey: Keys.reminderBidirectionalSync)
        }
    }

    /// Selected reminder list identifiers (empty = all lists)
    var selectedReminderListIds: [String] {
        didSet {
            save(selectedReminderListIds, forKey: Keys.selectedReminderListIds)
        }
    }

    /// Calendar event IDs dismissed by the user (deleted from outline but still in Calendar app)
    var dismissedCalendarEventIds: [String] {
        didSet {
            save(dismissedCalendarEventIds, forKey: Keys.dismissedCalendarEventIds)
        }
    }

    /// Reminder IDs dismissed by the user (deleted from outline but still in Reminders app)
    var dismissedReminderIds: [String] {
        didSet {
            save(dismissedReminderIds, forKey: Keys.dismissedReminderIds)
        }
    }

    /// Custom keyboard shortcut bindings (JSON-encoded Data). Empty = all defaults.
    var customKeyboardShortcutsData: Data {
        didSet {
            save(customKeyboardShortcutsData, forKey: Keys.customKeyboardShortcuts)
        }
    }

    // MARK: - Dismissed Item Helpers

    func dismissCalendarEvent(_ id: String) {
        if !dismissedCalendarEventIds.contains(id) {
            dismissedCalendarEventIds.append(id)
        }
    }

    func dismissReminder(_ id: String) {
        if !dismissedReminderIds.contains(id) {
            dismissedReminderIds.append(id)
        }
    }

    func clearDismissedItems() {
        dismissedCalendarEventIds = []
        dismissedReminderIds = []
    }

    // MARK: - iCloud Key-Value Store

    private let store = NSUbiquitousKeyValueStore.default

    private init() {
        // Load initial values from iCloud (or use defaults)
        weekStartDay = store.object(forKey: Keys.weekStartDay) as? Int ?? WeekStartDay.monday.rawValue
        autocompleteEnabled = store.object(forKey: Keys.autocompleteEnabled) as? Bool ?? true
        defaultFontSize = store.object(forKey: Keys.defaultFontSize) as? Double ?? 13.0
        focusModeEnabled = store.object(forKey: Keys.focusModeEnabled) as? Bool ?? false
        selectedCalendarIds = store.object(forKey: Keys.selectedCalendarIds) as? [String] ?? []
        calendarIntegrationEnabled = store.object(forKey: Keys.calendarIntegrationEnabled) as? Bool ?? true
        reminderIntegrationEnabled = store.object(forKey: Keys.reminderIntegrationEnabled) as? Bool ?? true
        reminderBidirectionalSync = store.object(forKey: Keys.reminderBidirectionalSync) as? Bool ?? false
        selectedReminderListIds = store.object(forKey: Keys.selectedReminderListIds) as? [String] ?? []
        dismissedCalendarEventIds = store.object(forKey: Keys.dismissedCalendarEventIds) as? [String] ?? []
        dismissedReminderIds = store.object(forKey: Keys.dismissedReminderIds) as? [String] ?? []
        customKeyboardShortcutsData = store.object(forKey: Keys.customKeyboardShortcuts) as? Data ?? Data()

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
                case Keys.selectedCalendarIds:
                    if let value = store.object(forKey: key) as? [String] {
                        selectedCalendarIds = value
                    }
                case Keys.calendarIntegrationEnabled:
                    if let value = store.object(forKey: key) as? Bool {
                        calendarIntegrationEnabled = value
                    }
                case Keys.reminderIntegrationEnabled:
                    if let value = store.object(forKey: key) as? Bool {
                        reminderIntegrationEnabled = value
                    }
                case Keys.reminderBidirectionalSync:
                    if let value = store.object(forKey: key) as? Bool {
                        reminderBidirectionalSync = value
                    }
                case Keys.selectedReminderListIds:
                    if let value = store.object(forKey: key) as? [String] {
                        selectedReminderListIds = value
                    }
                case Keys.dismissedCalendarEventIds:
                    if let value = store.object(forKey: key) as? [String] {
                        dismissedCalendarEventIds = value
                    }
                case Keys.dismissedReminderIds:
                    if let value = store.object(forKey: key) as? [String] {
                        dismissedReminderIds = value
                    }
                case Keys.customKeyboardShortcuts:
                    if let value = store.object(forKey: key) as? Data {
                        customKeyboardShortcutsData = value
                        ShortcutManager.shared.loadFromSettings()
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Week Start Day Helpers

    var weekStartDayName: String {
        weekStartDayValue.name
    }

    func setWeekStartDay(_ name: String) {
        switch name.lowercased() {
        case "sunday": weekStartDayValue = .sunday
        case "monday": weekStartDayValue = .monday
        case "saturday": weekStartDayValue = .saturday
        default: weekStartDayValue = .monday
        }
    }
}
