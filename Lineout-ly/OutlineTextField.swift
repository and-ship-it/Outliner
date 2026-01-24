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
    case progressiveSelectDown
    case deleteWithChildren
}

/// Host view that manages the text field and handles dynamic sizing
class WrappingTextFieldHost: NSView {
    var textField: NSTextField?

    override var intrinsicContentSize: NSSize {
        guard let textField = textField else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 22)
        }
        return textField.intrinsicContentSize
    }

    override func layout() {
        super.layout()
        // Position the text field to fill the host view
        textField?.frame = bounds
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // When our width changes, the text field needs to recalculate its height
        textField?.frame = bounds
        textField?.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }
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

    func makeNSView(context: Context) -> WrappingTextFieldHost {
        let hostView = WrappingTextFieldHost()

        let textField = OutlineNSTextField()
        textField.delegate = context.coordinator
        textField.actionHandler = { [context] action in
            context.coordinator.parent.onAction?(action)
        }
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none

        // Enable wrapping - text wraps visually but logically remains single line
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.maximumNumberOfLines = 0 // Allow unlimited visual lines

        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // High priority for vertical - we want to take up the space we need
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        hostView.textField = textField
        hostView.addSubview(textField)

        return hostView
    }

    func updateNSView(_ nsView: WrappingTextFieldHost, context: Context) {
        guard let textField = nsView.textField else { return }

        // Update text if changed externally
        if textField.stringValue != text {
            textField.stringValue = text
        }

        // Update font
        let weightedFont = NSFont.systemFont(ofSize: font.pointSize, weight: fontWeight)
        if textField.font != weightedFont {
            textField.font = weightedFont
            // Font change affects size, so invalidate
            textField.invalidateIntrinsicContentSize()
            nsView.invalidateIntrinsicContentSize()
        }

        // Update action handler
        if let outlineTextField = textField as? OutlineNSTextField {
            outlineTextField.actionHandler = { action in
                context.coordinator.parent.onAction?(action)
            }
        }

        // Handle focus changes from SwiftUI -> AppKit
        // Only trigger focus if we're not already focused
        let isCurrentlyFirstResponder = textField.window?.firstResponder == textField.currentEditor()

        if isFocused && !isCurrentlyFirstResponder && !context.coordinator.isUpdatingFocus {
            context.coordinator.isUpdatingFocus = true

            // Try immediate focus first (works when view is already in hierarchy)
            if let window = textField.window {
                let didBecome = window.makeFirstResponder(textField)

                if didBecome {
                    // Position cursor at start, no selection
                    if let editor = textField.currentEditor() {
                        editor.selectedRange = NSRange(location: 0, length: 0)
                    }
                    context.coordinator.isUpdatingFocus = false
                } else {
                    // If immediate focus failed, try async (view might not be fully ready)
                    DispatchQueue.main.async {
                        guard let window = textField.window else {
                            context.coordinator.isUpdatingFocus = false
                            return
                        }

                        let didBecomeAsync = window.makeFirstResponder(textField)

                        if didBecomeAsync {
                            // Position cursor at start, no selection
                            if let editor = textField.currentEditor() {
                                editor.selectedRange = NSRange(location: 0, length: 0)
                            }
                        }

                        context.coordinator.isUpdatingFocus = false
                    }
                }
            } else {
                // No window yet, must wait
                DispatchQueue.main.async {
                    guard let window = textField.window else {
                        context.coordinator.isUpdatingFocus = false
                        return
                    }

                    let didBecomeAsync = window.makeFirstResponder(textField)

                    if didBecomeAsync {
                        // Position cursor at start, no selection
                        if let editor = textField.currentEditor() {
                            editor.selectedRange = NSRange(location: 0, length: 0)
                        }
                    }

                    context.coordinator.isUpdatingFocus = false
                }
            }
        } else if !isFocused && isCurrentlyFirstResponder && !context.coordinator.isUpdatingFocus {
            // If SwiftUI says we shouldn't be focused but we are, resign first responder
            context.coordinator.isUpdatingFocus = true
            textField.window?.makeFirstResponder(nil)
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

            // Invalidate intrinsic content size when text changes
            // This ensures the view recalculates height for wrapped text
            textField.invalidateIntrinsicContentSize()
            if let hostView = textField.superview as? WrappingTextFieldHost {
                hostView.invalidateIntrinsicContentSize()
            }

            // Reset progressive selection state when text changes
            if let outlineTextField = textField as? OutlineNSTextField {
                outlineTextField.resetSelectionState()
            }
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
                // Only navigate to previous bullet if cursor is on first visual line
                if isAtFirstVisualLine(textView) {
                    parent.onAction?(.navigateUp)
                    return true
                }
                // Otherwise, let default up-arrow behavior move cursor within wrapped text
                return false

            case #selector(NSResponder.moveDown(_:)):
                // Check if Shift is held (this handles Shift+Down in some cases)
                if NSEvent.modifierFlags.contains(.shift) {
                    // Let performKeyEquivalent handle it
                    return false
                }
                // Only navigate to next bullet if cursor is on last visual line
                if isAtLastVisualLine(textView) {
                    let cursorLocation = textView.selectedRange().location
                    let textLength = textView.string.count

                    // If cursor is not at end of text, move to end first
                    if cursorLocation < textLength {
                        textView.setSelectedRange(NSRange(location: textLength, length: 0))
                        return true
                    }

                    // Cursor is at end, try to navigate to next bullet
                    parent.onAction?(.navigateDown)
                    return true
                }
                // Otherwise, let default down-arrow behavior move cursor within wrapped text
                return false

            case #selector(NSResponder.moveDownAndModifySelection(_:)):
                // This is Shift+Down - handle progressive selection
                if let textField = control as? OutlineNSTextField {
                    textField.handleProgressiveSelectDown()
                }
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
                // - Empty bullet: create sibling below
                // - Beginning (with text): create above
                // - End: create below (empty)
                // - Middle: split line, create below with remaining text
                let cursorPosition = textView.selectedRange().location
                let text = textView.string
                let textLength = text.count

                // Empty bullet - always create sibling below
                if textLength == 0 {
                    parent.onAction?(.createSiblingBelow)
                } else if cursorPosition == 0 {
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

        // MARK: - Visual Line Detection for Wrapped Text

        /// Determines if the cursor is on the first visual line of wrapped text
        private func isAtFirstVisualLine(_ textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  let _ = textView.textContainer else {
                return true // Default to allowing navigation if we can't determine
            }

            let textLength = textView.string.count
            let totalGlyphs = layoutManager.numberOfGlyphs

            // Empty text - always allow navigation up
            if totalGlyphs == 0 || textLength == 0 {
                return true
            }

            let selectedRange = textView.selectedRange()
            let cursorLocation = selectedRange.location

            // Edge case: cursor is at the very end of the text
            // For this case, check if all text fits on one line
            let glyphIndex: Int
            if cursorLocation >= textLength {
                glyphIndex = totalGlyphs - 1
            } else {
                glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorLocation)
            }

            // Find which line fragment the cursor is on
            var lineFragmentRange = NSRange(location: 0, length: 0)
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineFragmentRange)

            // If the line fragment starts at glyph 0, we're on the first visual line
            return lineFragmentRange.location == 0
        }

        /// Determines if the cursor is on the last visual line of wrapped text
        private func isAtLastVisualLine(_ textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return true // Default to allowing navigation if we can't determine
            }

            let selectedRange = textView.selectedRange()
            let cursorLocation = selectedRange.location
            let totalGlyphs = layoutManager.numberOfGlyphs
            let textLength = textView.string.count

            // Empty text
            if totalGlyphs == 0 || textLength == 0 {
                return true
            }

            // Edge case: cursor is at the very end of the text (after the last character)
            // This position is textLength, which is beyond the last character index
            // For this case, we need to check the glyph for the last actual character
            let glyphIndex: Int
            if cursorLocation >= textLength {
                // Cursor is at or beyond end of text - use the last valid glyph
                glyphIndex = totalGlyphs - 1
            } else {
                // Normal case: get glyph for current cursor position
                glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorLocation)
            }

            // Find which line fragment the cursor is on
            var lineFragmentRange = NSRange(location: 0, length: 0)
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineFragmentRange)

            // Find the last line fragment in the entire text
            let lastGlyphIndex = totalGlyphs - 1
            var lastLineFragmentRange = NSRange(location: 0, length: 0)
            layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: &lastLineFragmentRange)

            // If our current line fragment starts at the same position as the last line fragment,
            // we're on the last visual line
            return lineFragmentRange.location == lastLineFragmentRange.location
        }
    }
}

/// NSTextField subclass that handles outline keyboard shortcuts
class OutlineNSTextField: NSTextField {
    var actionHandler: ((OutlineAction) -> Void)?

    // Progressive selection state
    private enum SelectionLevel {
        case none
        case firstWord
        case wholeLine
        case extendToNextBullet
    }
    private var currentSelectionLevel: SelectionLevel = .none
    private var lastShiftDownTime: TimeInterval = 0

    // MARK: - Dynamic Height for Wrapped Text

    override var intrinsicContentSize: NSSize {
        // If we don't have a cell, fall back to super
        guard let cell = self.cell else {
            return super.intrinsicContentSize
        }

        // Use the current frame width to calculate wrapped height
        // This is critical for text wrapping to work properly
        let width = bounds.width > 0 ? bounds.width : 200 // Fallback to reasonable default

        // Calculate the height needed for wrapped text
        let cellSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude))

        return NSSize(width: NSView.noIntrinsicMetric, height: max(cellSize.height, 22))
    }

    override func layout() {
        super.layout()
        // Invalidate intrinsic content size when layout changes
        // This ensures height recalculates when width changes
        invalidateIntrinsicContentSize()
    }

    override var stringValue: String {
        didSet {
            // Invalidate intrinsic content size when text changes
            invalidateIntrinsicContentSize()
        }
    }

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

    override func resignFirstResponder() -> Bool {
        // Reset selection state when losing focus
        currentSelectionLevel = .none
        return super.resignFirstResponder()
    }

    /// Handle progressive Shift+Down selection
    func handleProgressiveSelectDown() {
        guard let editor = currentEditor() as? NSTextView else { return }

        let currentTime = Date.timeIntervalSinceReferenceDate
        let timeSinceLastPress = currentTime - lastShiftDownTime

        // Reset if too much time has passed (more than 2 seconds)
        if timeSinceLastPress > 2.0 {
            currentSelectionLevel = .none
        }

        lastShiftDownTime = currentTime

        let text = editor.string
        let currentRange = editor.selectedRange()

        switch currentSelectionLevel {
        case .none:
            // First Shift+Down: select first word
            selectFirstWord(in: editor, text: text, currentRange: currentRange)
            currentSelectionLevel = .firstWord

        case .firstWord:
            // Second Shift+Down: select whole line
            selectWholeLine(in: editor, text: text)
            currentSelectionLevel = .wholeLine

        case .wholeLine:
            // Third Shift+Down: extend to next bullet
            // This is handled at the document level, so we notify via action
            actionHandler?(.progressiveSelectDown)
            currentSelectionLevel = .extendToNextBullet

        case .extendToNextBullet:
            // Continue extending to subsequent bullets
            actionHandler?(.progressiveSelectDown)
        }
    }

    private func selectFirstWord(in editor: NSTextView, text: String, currentRange: NSRange) {
        // Find the first word boundary
        var wordRange = NSRange(location: 0, length: 0)

        if !text.isEmpty {
            let nsText = text as NSString
            // Skip leading whitespace
            var start = 0
            while start < text.count && text[text.index(text.startIndex, offsetBy: start)].isWhitespace {
                start += 1
            }

            // Find end of first word
            var end = start
            while end < text.count && !text[text.index(text.startIndex, offsetBy: end)].isWhitespace {
                end += 1
            }

            if end > start {
                wordRange = NSRange(location: start, length: end - start)
            }
        }

        editor.setSelectedRange(wordRange)
    }

    private func selectWholeLine(in editor: NSTextView, text: String) {
        // Select entire text content
        editor.setSelectedRange(NSRange(location: 0, length: text.count))
    }

    /// Reset selection state (called when text changes)
    func resetSelectionState() {
        currentSelectionLevel = .none
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
            } else if hasShift {
                // Shift+Down: progressive selection
                handleProgressiveSelectDown()
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

        case 51: // Delete/Backspace
            if hasCommand && hasShift {
                // Cmd+Shift+Delete: delete bullet and all children
                actionHandler?(.deleteWithChildren)
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
