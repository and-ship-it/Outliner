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

    var body: some Commands {
        // File menu additions
        CommandGroup(after: .saveItem) {
            Divider()

            Button("Show in Finder") {
                showInFinder()
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])
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
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") {
                withAnimation(.easeOut(duration: 0.2)) {
                    document?.zoomIn()
                }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(document == nil)

            Button("Zoom Out") {
                withAnimation(.easeOut(duration: 0.2)) {
                    document?.zoomOut()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(document == nil)

            Button("Zoom to Root") {
                withAnimation(.easeOut(duration: 0.2)) {
                    document?.zoomToRoot()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(document == nil)
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
