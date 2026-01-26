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
                    Text("Sunday").tag(0)
                    Text("Monday").tag(1)
                    Text("Saturday").tag(6)
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

#Preview {
    SettingsView()
}
#endif
