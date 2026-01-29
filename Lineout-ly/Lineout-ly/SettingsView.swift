//
//  SettingsView.swift
//  Lineout-ly
//
//  Created by Andriy on 26/01/2026.
//

#if os(macOS)
import SwiftUI

/// macOS Preferences window content
struct SettingsView: View {
    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "textformat.size")
                }

            IntegrationsSettingsView()
                .tabItem {
                    Label("Integrations", systemImage: "arrow.triangle.2.circlepath")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            DataSettingsView()
                .tabItem {
                    Label("Data", systemImage: "trash")
                }
        }
        .frame(width: 500, height: 550)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        Form {
            Section {
                Picker("Week Starts On", selection: Binding(
                    get: { settings.weekStartDay },
                    set: { settings.weekStartDay = $0 }
                )) {
                    ForEach(WeekStartDay.allCases) { day in
                        Text(day.name).tag(day.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Calendar")
            } footer: {
                Text("Affects weekly document naming. Changes take effect on next app launch.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Enable Word Autocomplete", isOn: Binding(
                    get: { settings.autocompleteEnabled },
                    set: { settings.autocompleteEnabled = $0 }
                ))
            } header: {
                Text("Typing")
            } footer: {
                Text("Suggests words as you type based on system dictionary.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Display Settings Tab

struct DisplaySettingsView: View {
    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Default Font Size")
                    Spacer()
                    Text("\(Int(settings.defaultFontSize))pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { settings.defaultFontSize },
                        set: { settings.defaultFontSize = $0 }
                    ),
                    in: 9...32,
                    step: 1
                )
                .tint(.accentColor)
            } header: {
                Text("Text")
            } footer: {
                Text("Default font size for new windows. Current windows can be adjusted with Cmd+ and Cmd-.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Enable Focus Mode by Default", isOn: Binding(
                    get: { settings.focusModeEnabled },
                    set: { settings.focusModeEnabled = $0 }
                ))
            } header: {
                Text("Focus")
            } footer: {
                Text("Focus mode dims all bullets except the currently focused one.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Data Settings Tab

struct DataSettingsView: View {
    @State private var showDeleteConfirm1 = false
    @State private var showDeleteConfirm2 = false

    var body: some View {
        Form {
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm1 = true
                } label: {
                    Text("Delete All Data")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Permanently deletes all outlines, settings, and synced data from this device and iCloud.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Delete All Data?", isPresented: $showDeleteConfirm1) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                showDeleteConfirm2 = true
            }
        } message: {
            Text("This will permanently delete all your outlines, settings, and synced data from this device and iCloud.")
        }
        .alert("Are you absolutely sure?", isPresented: $showDeleteConfirm2) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                Task {
                    await DataResetManager.deleteAllData()
                }
            }
        } message: {
            Text("All data will be permanently erased. This action cannot be undone.")
        }
    }
}

// MARK: - Integrations Settings Tab

struct IntegrationsSettingsView: View {
    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        Form {
            // Calendar Integration
            Section {
                Toggle("Enable Calendar Integration", isOn: Binding(
                    get: { settings.calendarIntegrationEnabled },
                    set: { newValue in
                        settings.calendarIntegrationEnabled = newValue
                        if !newValue {
                            CalendarSyncEngine.shared.removeAllCalendarEvents()
                        } else {
                            Task { await CalendarSyncEngine.shared.requestAccess(); await CalendarSyncEngine.shared.syncCalendarEvents() }
                        }
                    }
                ))

                if settings.calendarIntegrationEnabled {
                    CalendarPickerView()

                    Button("Force Resync Calendars") {
                        Task { await CalendarSyncEngine.shared.forceSync() }
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Disabling removes all calendar events from the outline.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // Reminders Integration
            Section {
                Toggle("Enable Reminders Integration", isOn: Binding(
                    get: { settings.reminderIntegrationEnabled },
                    set: { newValue in
                        settings.reminderIntegrationEnabled = newValue
                        if !newValue {
                            ReminderSyncEngine.shared.removeAllReminders()
                        } else {
                            Task { _ = await ReminderSyncEngine.shared.requestAccess(); await ReminderSyncEngine.shared.syncExternalChanges() }
                        }
                    }
                ))

                if settings.reminderIntegrationEnabled {
                    Toggle("Bidirectional Sync", isOn: Binding(
                        get: { settings.reminderBidirectionalSync },
                        set: { settings.reminderBidirectionalSync = $0 }
                    ))

                    ReminderListPickerView()

                    Button("Force Resync Reminders") {
                        Task { await ReminderSyncEngine.shared.forceResync() }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Disabling removes all reminders from the outline. Bidirectional sync allows editing reminders from the outline.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsView: View {
    private var manager: ShortcutManager { ShortcutManager.shared }
    @State private var conflictWarning: String?

    private var categories: [(String, [ShortcutActionInfo])] {
        let grouped = Dictionary(grouping: ShortcutManager.actionDefinitions) { $0.category }
        return [
            ("Navigation", grouped["Navigation"] ?? []),
            ("Editing", grouped["Editing"] ?? []),
            ("View", grouped["View"] ?? []),
        ]
    }

    var body: some View {
        Form {
            ForEach(categories, id: \.0) { category, actions in
                Section {
                    ForEach(actions, id: \.name) { info in
                        shortcutRow(info: info)
                    }
                } header: {
                    Text(category)
                }
            }

            Section {
                Button("Reset All to Defaults") {
                    manager.resetAllToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Shortcut Conflict", isPresented: Binding(
            get: { conflictWarning != nil },
            set: { if !$0 { conflictWarning = nil } }
        )) {
            Button("OK") { conflictWarning = nil }
        } message: {
            Text(conflictWarning ?? "")
        }
    }

    @ViewBuilder
    private func shortcutRow(info: ShortcutActionInfo) -> some View {
        let currentBinding = manager.binding(for: info.name) ?? info.defaultBinding
        let isCustom = manager.hasCustomBinding(for: info.name)

        HStack {
            Text(info.displayName)
                .frame(minWidth: 160, alignment: .leading)

            Spacer()

            ShortcutRecorderView(
                actionName: info.name,
                currentBinding: Binding(
                    get: { currentBinding },
                    set: { _ in }
                ),
                onBindingChanged: { newBinding in
                    // Check for conflicts
                    if let conflict = manager.conflictingAction(for: newBinding, excludingAction: info.name) {
                        let conflictName = ShortcutManager.actionDefinitions.first { $0.name == conflict }?.displayName ?? conflict
                        conflictWarning = "\(newBinding.displayString) is already used by \"\(conflictName)\". Change that shortcut first."
                    } else {
                        manager.setCustomBinding(newBinding, for: info.name)
                    }
                }
            )
            .frame(width: 120)

            if isCustom {
                Button {
                    manager.resetToDefault(actionName: info.name)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
    }
}

#Preview {
    SettingsView()
}
#endif

// MARK: - Shortcuts List View (Shared between iOS and macOS)

import SwiftUI

/// Lists all customizable keyboard shortcuts with key recorder for each action.
struct ShortcutsListView: View {
    private var manager: ShortcutManager { ShortcutManager.shared }
    @State private var conflictWarning: String?

    private var categories: [(String, [ShortcutActionInfo])] {
        let grouped = Dictionary(grouping: ShortcutManager.actionDefinitions) { $0.category }
        return [
            ("Navigation", grouped["Navigation"] ?? []),
            ("Editing", grouped["Editing"] ?? []),
            ("View", grouped["View"] ?? []),
        ]
    }

    var body: some View {
        List {
            ForEach(categories, id: \.0) { category, actions in
                Section {
                    ForEach(actions, id: \.name) { info in
                        shortcutRow(info: info)
                    }
                } header: {
                    Text(category)
                }
            }

            Section {
                Button("Reset All to Defaults") {
                    manager.resetAllToDefaults()
                }
            }
        }
        #if os(iOS)
        .navigationTitle("Keyboard Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Shortcut Conflict", isPresented: Binding(
            get: { conflictWarning != nil },
            set: { if !$0 { conflictWarning = nil } }
        )) {
            Button("OK") { conflictWarning = nil }
        } message: {
            Text(conflictWarning ?? "")
        }
    }

    @ViewBuilder
    private func shortcutRow(info: ShortcutActionInfo) -> some View {
        let currentBinding = manager.binding(for: info.name) ?? info.defaultBinding
        let isCustom = manager.hasCustomBinding(for: info.name)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.displayName)
                if isCustom {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            ShortcutRecorderView(
                actionName: info.name,
                currentBinding: Binding(
                    get: { currentBinding },
                    set: { _ in }
                ),
                onBindingChanged: { newBinding in
                    if let conflict = manager.conflictingAction(for: newBinding, excludingAction: info.name) {
                        let conflictName = ShortcutManager.actionDefinitions.first { $0.name == conflict }?.displayName ?? conflict
                        conflictWarning = "\(newBinding.displayString) is already used by \"\(conflictName)\". Change that shortcut first."
                    } else {
                        manager.setCustomBinding(newBinding, for: info.name)
                    }
                }
            )
            .frame(width: 120, height: 32)

            if isCustom {
                Button {
                    manager.resetToDefault(actionName: info.name)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Calendar Picker (Shared between iOS and macOS)

import EventKit

/// A view listing all available EKCalendars with toggles.
/// Empty selection = all calendars (all toggles appear ON).
struct CalendarPickerView: View {
    private var settings: SettingsManager { SettingsManager.shared }
    @State private var availableCalendars: [EKCalendar] = []

    var body: some View {
        Group {
            if CalendarSyncEngine.shared.isAuthorized {
                if availableCalendars.isEmpty {
                    Text("No calendars found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: Binding(
                            get: {
                                let ids = settings.selectedCalendarIds
                                // Empty = all selected
                                return ids.isEmpty || ids.contains(calendar.calendarIdentifier)
                            },
                            set: { newValue in
                                var ids = settings.selectedCalendarIds
                                if ids.isEmpty {
                                    // Switching from "all" to specific — add all except the toggled-off one
                                    ids = availableCalendars.map(\.calendarIdentifier)
                                    if !newValue {
                                        ids.removeAll { $0 == calendar.calendarIdentifier }
                                    }
                                } else {
                                    if newValue {
                                        if !ids.contains(calendar.calendarIdentifier) {
                                            ids.append(calendar.calendarIdentifier)
                                        }
                                        // If all are now selected, reset to empty (= all)
                                        if ids.count == availableCalendars.count {
                                            ids = []
                                        }
                                    } else {
                                        ids.removeAll { $0 == calendar.calendarIdentifier }
                                    }
                                }
                                settings.selectedCalendarIds = ids
                                // Re-sync calendar events with new selection
                                Task {
                                    await CalendarSyncEngine.shared.syncCalendarEvents()
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                            }
                        }
                        .tint(.accentColor)
                    }
                }
            } else {
                Text("Calendar access not granted")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            availableCalendars = CalendarSyncEngine.shared.availableCalendars()
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        #if os(iOS)
        .navigationTitle("Select Calendars")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A view listing all available reminder lists with toggles.
/// Empty selection = all lists (all toggles appear ON).
struct ReminderListPickerView: View {
    private var settings: SettingsManager { SettingsManager.shared }
    @State private var availableLists: [EKCalendar] = []

    var body: some View {
        Group {
            if ReminderSyncEngine.shared.isAuthorized {
                if availableLists.isEmpty {
                    Text("No reminder lists found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableLists, id: \.calendarIdentifier) { list in
                        Toggle(isOn: Binding(
                            get: {
                                let ids = settings.selectedReminderListIds
                                return ids.isEmpty || ids.contains(list.calendarIdentifier)
                            },
                            set: { newValue in
                                var ids = settings.selectedReminderListIds
                                if ids.isEmpty {
                                    ids = availableLists.map(\.calendarIdentifier)
                                    if !newValue {
                                        ids.removeAll { $0 == list.calendarIdentifier }
                                    }
                                } else {
                                    if newValue {
                                        if !ids.contains(list.calendarIdentifier) {
                                            ids.append(list.calendarIdentifier)
                                        }
                                        if ids.count == availableLists.count {
                                            ids = []
                                        }
                                    } else {
                                        ids.removeAll { $0 == list.calendarIdentifier }
                                    }
                                }
                                settings.selectedReminderListIds = ids
                                Task { await ReminderSyncEngine.shared.forceResync() }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(cgColor: list.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(list.title)
                            }
                        }
                        .tint(.accentColor)
                    }
                }
            } else {
                Text("Reminders access not granted")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            availableLists = ReminderSyncEngine.shared.availableReminderLists()
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        #if os(iOS)
        .navigationTitle("Select Reminder Lists")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
