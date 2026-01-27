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

#if os(macOS)
/// Singleton to hold openWindow action reference
class WindowOpener {
    static let shared = WindowOpener()
    var openWindowAction: (() -> Void)?
}

/// Open a new window
private func openNewWindow() {
    // Clear pending zoom so new window starts at root
    WindowManager.shared.pendingZoom = nil

    // Check if there are any visible windows
    let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }

    if hasVisibleWindows {
        // Add a new tab to existing window
        NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
    } else {
        // No windows - use the stored openWindow action
        if let openAction = WindowOpener.shared.openWindowAction {
            openAction()
        } else {
            // Fallback: activate app and hope WindowGroup creates a window
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
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
            #if os(macOS)
            // Replace New Document with New Window (macOS only)
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            #endif

            OutlineCommands()
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        #endif

        // macOS Preferences window (Cmd+,)
        #if os(macOS)
        Settings {
            SettingsView()
        }
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
    @FocusedValue(\.isAlwaysOnTop) var alwaysOnTopBinding
    @FocusedValue(\.undoManager) var undoManager
    @FocusedValue(\.collapsedNodeIds) var collapsedNodeIdsBinding
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

        // Edit menu - Undo/Redo
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                undoManager?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(undoManager?.canUndo != true)

            Button("Redo") {
                undoManager?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(undoManager?.canRedo != true)
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
                searchingBinding?.wrappedValue.toggle()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(document == nil)

            Divider()

            Toggle("Word Autocomplete", isOn: $autocompleteEnabled)

            Divider()

            // Week start day setting
            Menu("Week Starts On") {
                ForEach(WeekStartDay.allCases) { day in
                    Button(action: {
                        UserDefaults.standard.set(day.rawValue, forKey: "weekStartDay")
                        // Note: This will take effect on next app launch
                    }) {
                        if iCloudManager.shared.weekStartDay == day {
                            Text("\(day.name) ✓")
                        } else {
                            Text(day.name)
                        }
                    }
                }
            }
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
            #if os(macOS)
            .keyboardShortcut(",", modifiers: .command)
            #else
            // Use different shortcut on iOS to avoid conflict with Settings (Cmd+,)
            .keyboardShortcut(",", modifiers: [.command, .shift])
            #endif
            .disabled(document == nil)

            Button("Zoom to Root") {
                zoomToRoot()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(document == nil)

            Button("Zoom to Top") {
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

            Toggle("Always on Top", isOn: Binding(
                get: { alwaysOnTopBinding?.wrappedValue ?? false },
                set: { alwaysOnTopBinding?.wrappedValue = $0 }
            ))
            .keyboardShortcut("t", modifiers: [.command, .option])
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
            .keyboardShortcut(.upArrow, modifiers: [.shift, .option])
            .disabled(document == nil)

            Button("Move Down") {
                withAnimation(.easeOut(duration: 0.15)) {
                    document?.moveDown()
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.shift, .option])
            .disabled(document == nil)

            Divider()

            Button("Collapse") {
                // Collapse uses per-tab state via collapsedNodeIdsBinding
                if let focused = document?.focusedNode, focused.hasChildren {
                    collapsedNodeIdsBinding?.wrappedValue.insert(focused.id)
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            .disabled(document == nil)

            Button("Expand") {
                // Expand uses per-tab state via collapsedNodeIdsBinding
                if let focused = document?.focusedNode {
                    collapsedNodeIdsBinding?.wrappedValue.remove(focused.id)
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            .disabled(document == nil)

            Button("Collapse All Children") {
                if let focused = document?.focusedNode {
                    // Collapse all descendants that have children
                    for descendant in focused.flattened() {
                        if descendant.hasChildren {
                            collapsedNodeIdsBinding?.wrappedValue.insert(descendant.id)
                        }
                    }
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .shift, .option])
            .disabled(document == nil)

            Button("Expand All Children") {
                if let focused = document?.focusedNode {
                    // Expand the focused node and all descendants
                    collapsedNodeIdsBinding?.wrappedValue.remove(focused.id)
                    for descendant in focused.flattened() {
                        collapsedNodeIdsBinding?.wrappedValue.remove(descendant.id)
                    }
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .shift, .option])
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
            doc.focusVersion += 1  // Force cursor refresh
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
            doc.focusVersion += 1  // Force cursor refresh
        }
    }

    private func zoomToRoot() {
        // Delete empty auto-created bullet before going home
        if let currentZoomId = zoomedNodeIdBinding?.wrappedValue,
           let doc = document {
            doc.deleteNodeIfEmpty(currentZoomId)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            zoomedNodeIdBinding?.wrappedValue = nil
            // Force cursor refresh after zoom change
            if let doc = document {
                doc.focusVersion += 1
            }
        }
    }

    private func goHomeAndCollapseAll() {
        // Delete empty auto-created bullet before going home
        if let currentZoomId = zoomedNodeIdBinding?.wrappedValue,
           let doc = document {
            doc.deleteNodeIfEmpty(currentZoomId)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            zoomedNodeIdBinding?.wrappedValue = nil
            // Collapse all nodes with children in per-tab state
            if let doc = document {
                var collapsed = Set<UUID>()
                for node in doc.root.flattened() {
                    if node.hasChildren {
                        collapsed.insert(node.id)
                    }
                }
                collapsedNodeIdsBinding?.wrappedValue = collapsed

                // Focus first visible node (first child of root after collapsing)
                if let firstNode = doc.root.children.first {
                    doc.focusedNodeId = firstNode.id
                    doc.focusVersion += 1
                }
            }
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
        #if os(iOS)
        fontSizeBinding?.wrappedValue = 17 // Default size (matches Apple Notes)
        #else
        fontSizeBinding?.wrappedValue = 13 // Default size
        #endif
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

// MARK: - Focused Value for Always on Top

struct FocusedAlwaysOnTopKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isAlwaysOnTop: Binding<Bool>? {
        get { self[FocusedAlwaysOnTopKey.self] }
        set { self[FocusedAlwaysOnTopKey.self] = newValue }
    }
}

// MARK: - Focused Value for Undo Manager

struct FocusedUndoManagerKey: FocusedValueKey {
    typealias Value = UndoManager
}

extension FocusedValues {
    var undoManager: UndoManager? {
        get { self[FocusedUndoManagerKey.self] }
        set { self[FocusedUndoManagerKey.self] = newValue }
    }
}

// MARK: - Focused Value for Collapsed Node IDs (per-tab)

struct FocusedCollapsedNodeIdsKey: FocusedValueKey {
    typealias Value = Binding<Set<UUID>>
}

extension FocusedValues {
    var collapsedNodeIds: Binding<Set<UUID>>? {
        get { self[FocusedCollapsedNodeIdsKey.self] }
        set { self[FocusedCollapsedNodeIdsKey.self] = newValue }
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
            // No visible windows, create a new one using stored action
            if let openAction = WindowOpener.shared.openWindowAction {
                openAction()
            } else {
                // Fallback
                NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
            }
        }
        return true
    }
}
#endif
