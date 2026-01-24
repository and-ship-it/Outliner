//
//  OutlineTextField.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI
#if os(macOS)
import AppKit

/// Actions that can be triggered from keyboard shortcuts in the text field
enum OutlineAction {
    case collapse
    case expand
    case collapseAll
    case expandAll
    case moveUp
    case moveDown
    case indent
    case outdent
    case createSiblingAbove
    case createSiblingBelow
    case navigateUp
    case navigateDown
    case zoomIn
    case zoomOut
    case zoomToRoot
}

/// Custom TextField that doesn't select text on focus - positions cursor at start
struct OutlineTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onAction: ((OutlineAction) -> Void)?
    var onSplitLine: ((String) -> Void)?  // Called when splitting line, passes text after cursor
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var fontWeight: NSFont.Weight = .regular

    func makeNSView(context: Context) -> NSTextField {
        let textField = OutlineNSTextField()
        textField.delegate = context.coordinator
        textField.actionHandler = { [context] action in
            context.coordinator.parent.onAction?(action)
        }
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.maximumNumberOfLines = 1
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Update text if changed externally
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Update font
        let weightedFont = NSFont.systemFont(ofSize: font.pointSize, weight: fontWeight)
        if nsView.font != weightedFont {
            nsView.font = weightedFont
        }

        // Update action handler
        if let outlineTextField = nsView as? OutlineNSTextField {
            outlineTextField.actionHandler = { action in
                context.coordinator.parent.onAction?(action)
            }
        }

        // Handle focus changes from SwiftUI -> AppKit
        // Only trigger focus if we're not already focused
        let isCurrentlyFirstResponder = nsView.window?.firstResponder == nsView.currentEditor()

        if isFocused && !isCurrentlyFirstResponder && !context.coordinator.isUpdatingFocus {
            context.coordinator.isUpdatingFocus = true

            // Try immediate focus first (works when view is already in hierarchy)
            if let window = nsView.window {
                let didBecome = window.makeFirstResponder(nsView)

                if didBecome {
                    // Position cursor at start, no selection
                    if let editor = nsView.currentEditor() {
                        editor.selectedRange = NSRange(location: 0, length: 0)
                    }
                    context.coordinator.isUpdatingFocus = false
                } else {
                    // If immediate focus failed, try async (view might not be fully ready)
                    DispatchQueue.main.async {
                        guard let window = nsView.window else {
                            context.coordinator.isUpdatingFocus = false
                            return
                        }

                        let didBecomeAsync = window.makeFirstResponder(nsView)

                        if didBecomeAsync {
                            // Position cursor at start, no selection
                            if let editor = nsView.currentEditor() {
                                editor.selectedRange = NSRange(location: 0, length: 0)
                            }
                        }

                        context.coordinator.isUpdatingFocus = false
                    }
                }
            } else {
                // No window yet, must wait
                DispatchQueue.main.async {
                    guard let window = nsView.window else {
                        context.coordinator.isUpdatingFocus = false
                        return
                    }

                    let didBecomeAsync = window.makeFirstResponder(nsView)

                    if didBecomeAsync {
                        // Position cursor at start, no selection
                        if let editor = nsView.currentEditor() {
                            editor.selectedRange = NSRange(location: 0, length: 0)
                        }
                    }

                    context.coordinator.isUpdatingFocus = false
                }
            }
        } else if !isFocused && isCurrentlyFirstResponder && !context.coordinator.isUpdatingFocus {
            // If SwiftUI says we shouldn't be focused but we are, resign first responder
            context.coordinator.isUpdatingFocus = true
            nsView.window?.makeFirstResponder(nil)
            context.coordinator.isUpdatingFocus = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OutlineTextField
        var isUpdatingFocus = false

        init(_ parent: OutlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard !isUpdatingFocus else { return }
            parent.onFocusChange(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !isUpdatingFocus else { return }
            parent.onFocusChange(false)
        }

        // Intercept text commands
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                // Single line - always navigate up
                parent.onAction?(.navigateUp)
                return true

            case #selector(NSResponder.moveDown(_:)):
                // Single line - always navigate down
                parent.onAction?(.navigateDown)
                return true

            case #selector(NSResponder.insertTab(_:)):
                // Tab = indent
                parent.onAction?(.indent)
                return true

            case #selector(NSResponder.insertBacktab(_:)):
                // Shift+Tab = outdent
                parent.onAction?(.outdent)
                return true

            case #selector(NSResponder.insertNewline(_:)):
                // Enter creates a new sibling bullet
                // Behavior depends on cursor position:
                // - Beginning (with text): create above
                // - End: create below (empty)
                // - Middle: split line, create below with remaining text
                let cursorPosition = textView.selectedRange().location
                let text = textView.string
                let textLength = text.count

                if cursorPosition == 0 && textLength > 0 {
                    // Cursor at beginning of non-empty line -> create bullet above
                    parent.onAction?(.createSiblingAbove)
                } else if cursorPosition >= textLength {
                    // Cursor at end -> create empty bullet below
                    parent.onAction?(.createSiblingBelow)
                } else {
                    // Cursor in middle -> split the line
                    let index = text.index(text.startIndex, offsetBy: cursorPosition)
                    let textBefore = String(text[..<index])
                    let textAfter = String(text[index...])

                    // Update current text to just the part before cursor
                    parent.text = textBefore

                    // Create new bullet below with the text after cursor
                    parent.onSplitLine?(textAfter)
                }
                return true

            default:
                return false
            }
        }
    }
}

/// NSTextField subclass that handles outline keyboard shortcuts
class OutlineNSTextField: NSTextField {
    var actionHandler: ((OutlineAction) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Position cursor at start after becoming first responder
            DispatchQueue.main.async { [weak self] in
                if let editor = self?.currentEditor() {
                    editor.selectedRange = NSRange(location: 0, length: 0)
                }
            }
        }
        return result
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasShift = flags.contains(.shift)

        // Handle key equivalents (keys with modifiers)
        switch event.keyCode {
        case 126: // Up arrow
            if hasCommand && hasOption {
                actionHandler?(.collapseAll)
                return true
            } else if hasCommand {
                actionHandler?(.collapse)
                return true
            } else if hasOption {
                actionHandler?(.moveUp)
                return true
            }

        case 125: // Down arrow
            if hasCommand && hasOption {
                actionHandler?(.expandAll)
                return true
            } else if hasCommand {
                actionHandler?(.expand)
                return true
            } else if hasOption {
                actionHandler?(.moveDown)
                return true
            }

        case 48: // Tab
            if hasShift {
                actionHandler?(.outdent)
            } else {
                actionHandler?(.indent)
            }
            return true

        case 36: // Return/Enter
            if hasCommand {
                // ⌘+Enter always creates below
                actionHandler?(.createSiblingBelow)
                return true
            }

        case 53: // Escape
            actionHandler?(.zoomToRoot)
            return true

        case 47: // Period (.)
            if hasCommand {
                actionHandler?(.zoomIn)
                return true
            }

        case 43: // Comma (,)
            if hasCommand {
                actionHandler?(.zoomOut)
                return true
            }

        default:
            break
        }

        return super.performKeyEquivalent(with: event)
    }

}

#else
// iOS fallback - use standard TextField (single line)
struct OutlineTextField: View {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var font: Font = .body
    var fontWeight: Font.Weight = .regular

    @FocusState private var textFieldFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .fontWeight(fontWeight)
            .focused($textFieldFocused)
            .onChange(of: isFocused) { _, newValue in
                textFieldFocused = newValue
            }
            .onChange(of: textFieldFocused) { _, newValue in
                onFocusChange(newValue)
            }
    }
}
#endif
