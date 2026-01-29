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

            CalendarsSettingsView()
                .tabItem {
                    Label("Calendars", systemImage: "calendar")
                }

            DataSettingsView()
                .tabItem {
                    Label("Data", systemImage: "trash")
                }
        }
        .frame(width: 450, height: 300)
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

// MARK: - Calendars Settings Tab

struct CalendarsSettingsView: View {
    var body: some View {
        Form {
            Section {
                CalendarPickerView()
            } header: {
                Text("Displayed Calendars")
            } footer: {
                Text("Select which calendars to show under each day. Empty selection shows all calendars.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
#endif

// MARK: - Calendar Picker (Shared between iOS and macOS)

import SwiftUI
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
