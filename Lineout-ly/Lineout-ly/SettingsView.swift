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

            DataSettingsView()
                .tabItem {
                    Label("Data", systemImage: "trash")
                }
        }
        .frame(width: 450, height: 250)
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

#Preview {
    SettingsView()
}
#endif
