//
//  Lineout_lyApp.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct Lineout_lyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        // Single-document app with iCloud sync
        WindowGroup("", id: "main") {
            ContentView()
        }
        .commands {
            // Remove New Document command
            CommandGroup(replacing: .newItem) {
                // Empty - no new document creation
            }

            OutlineCommands()
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        #endif
    }
}

// MARK: - Outline Commands

struct OutlineCommands: Commands {
    @FocusedValue(\.document) var document
    @FocusedValue(\.zoomedNodeId) var zoomedNodeIdBinding
    @FocusedValue(\.fontSize) var fontSizeBinding
    @FocusedValue(\.isFocusMode) var focusModeBinding
    @FocusedValue(\.isSearching) var searchingBinding
    @AppStorage("autocompleteEnabled") var autocompleteEnabled: Bool = true

    var body: some Commands {
        // File menu additions
        CommandGroup(after: .saveItem) {
            Divider()

            Button("Show in Finder") {
                showInFinder()
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])
        }

        // Tab commands
        CommandGroup(before: .windowArrangement) {
            Button("New Tab") {
                openNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            // Tab switching shortcuts (Cmd+1 through Cmd+9)
            ForEach(1...9, id: \.self) { index in
                Button("Select Tab \(index)") {
                    selectTab(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }

            Divider()
        }

        // Edit menu additions
        CommandGroup(after: .undoRedo) {
            Divider()

            Button("Indent") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.indent()
                }
            }
            .keyboardShortcut(.tab, modifiers: [])
            .disabled(document == nil)

            Button("Outdent") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.outdent()
                }
            }
            .keyboardShortcut(.tab, modifiers: .shift)
            .disabled(document == nil)

            Divider()

            Button("Find...") {
                searchingBinding?.wrappedValue = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(document == nil)

            Divider()

            Toggle("Word Autocomplete", isOn: $autocompleteEnabled)
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") {
                zoomIn()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(document == nil)

            Button("Zoom Out") {
                zoomOut()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(document == nil)

            Button("Zoom to Root") {
                zoomToRoot()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(document == nil)

            Button("Go Home") {
                goHomeAndCollapseAll()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(document == nil)

            Divider()

            Button("Make Larger") {
                increaseFontSize()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Make Smaller") {
                decreaseFontSize()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                resetFontSize()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Toggle("Focus Mode", isOn: Binding(
                get: { focusModeBinding?.wrappedValue ?? false },
                set: { focusModeBinding?.wrappedValue = $0 }
            ))
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        // Outline menu
        CommandMenu("Outline") {
            Button("New Bullet") {
                document?.createSiblingBelow()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(document == nil)

            Divider()

            Button("Move Up") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.moveUp()
                }
            }
            .keyboardShortcut(.upArrow, modifiers: .option)
            .disabled(document == nil)

            Button("Move Down") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.moveDown()
                }
            }
            .keyboardShortcut(.downArrow, modifiers: .option)
            .disabled(document == nil)

            Divider()

            Button("Collapse") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.collapseFocused()
                }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(document == nil)

            Button("Expand") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.expandFocused()
                }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(document == nil)

            Button("Collapse All Children") {
                if let node = document?.focusedNode {
                    document?.collapseAllChildren(of: node)
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(document == nil)

            Button("Expand All Children") {
                if let node = document?.focusedNode {
                    document?.expandAllChildren(of: node)
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(document == nil)
        }
    }

    // MARK: - Tab Actions

    private func openNewTab() {
        #if os(macOS)
        // Set pending zoom to current focused node
        let focusedId = document?.focusedNodeId
        WindowManager.shared.pendingZoom = focusedId

        // Trigger native "New Tab" which creates a new window in the same tab group
        NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
        #endif
    }

    private func selectTab(at index: Int) {
        #if os(macOS)
        guard let window = NSApp.keyWindow,
              let tabGroup = window.tabGroup,
              index < tabGroup.windows.count else { return }

        let targetWindow = tabGroup.windows[index]
        targetWindow.makeKeyAndOrderFront(nil)
        #endif
    }

    // MARK: - Zoom Actions

    private func zoomIn() {
        guard let doc = document,
              let focused = doc.focusedNode else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            zoomedNodeIdBinding?.wrappedValue = focused.id
        }
    }

    private func zoomOut() {
        guard let doc = document,
              let zoomedId = zoomedNodeIdBinding?.wrappedValue,
              let zoomed = doc.root.find(id: zoomedId) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            if let parent = zoomed.parent, !parent.isRoot {
                zoomedNodeIdBinding?.wrappedValue = parent.id
            } else {
                zoomedNodeIdBinding?.wrappedValue = nil
            }
        }
    }

    private func zoomToRoot() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomedNodeIdBinding?.wrappedValue = nil
        }
    }

    private func goHomeAndCollapseAll() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomedNodeIdBinding?.wrappedValue = nil
            document?.collapseAll()
        }
    }

    // MARK: - Font Size Actions

    private func increaseFontSize() {
        guard let binding = fontSizeBinding else { return }
        let newSize = min(binding.wrappedValue + 1, 32) // Max 32pt
        binding.wrappedValue = newSize
    }

    private func decreaseFontSize() {
        guard let binding = fontSizeBinding else { return }
        let newSize = max(binding.wrappedValue - 1, 9) // Min 9pt
        binding.wrappedValue = newSize
    }

    private func resetFontSize() {
        fontSizeBinding?.wrappedValue = 13 // Default size
    }

    // MARK: - Show in Finder

    private func showInFinder() {
        #if os(macOS)
        // Show the iCloud folder in Finder
        if let appFolder = iCloudManager.shared.appFolderURL {
            NSWorkspace.shared.activateFileViewerSelecting([appFolder])
        } else if iCloudManager.shared.localFallbackURL.path.isEmpty == false {
            // Show local fallback folder
            NSWorkspace.shared.activateFileViewerSelecting([iCloudManager.shared.localFallbackURL])
        }
        #endif
    }
}

// MARK: - Focused Value for Zoomed Node ID

struct FocusedZoomedNodeIdKey: FocusedValueKey {
    typealias Value = Binding<UUID?>
}

extension FocusedValues {
    var zoomedNodeId: Binding<UUID?>? {
        get { self[FocusedZoomedNodeIdKey.self] }
        set { self[FocusedZoomedNodeIdKey.self] = newValue }
    }
}

// MARK: - Focused Value for Font Size

struct FocusedFontSizeKey: FocusedValueKey {
    typealias Value = Binding<Double>
}

extension FocusedValues {
    var fontSize: Binding<Double>? {
        get { self[FocusedFontSizeKey.self] }
        set { self[FocusedFontSizeKey.self] = newValue }
    }
}

// MARK: - Focused Value for Focus Mode

struct FocusedFocusModeKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isFocusMode: Binding<Bool>? {
        get { self[FocusedFocusModeKey.self] }
        set { self[FocusedFocusModeKey.self] = newValue }
    }
}

// MARK: - Focused Value for Search

struct FocusedSearchKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isSearching: Binding<Bool>? {
        get { self[FocusedSearchKey.self] }
        set { self[FocusedSearchKey.self] = newValue }
    }
}

// MARK: - App Delegate

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep the app running when all windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Reopen main window when dock icon is clicked and no windows are open
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, create a new one
            NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
        }
        return true
    }
}
#endif
