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
    case progressiveSelectAll  // Cmd+A progressive selection
    case clearSelection        // Escape to clear selection
    case deleteWithChildren
    case toggleTask
    case toggleFocusMode
    case goHomeAndCollapseAll
    case toggleSearch
}

/// Custom field editor (standard cursor)
class ThickCursorTextView: NSTextView {
    // Using standard cursor - no custom drawing needed
}

/// Custom cell that uses our thick cursor field editor
class ThickCursorTextFieldCell: NSTextFieldCell {
    private var customFieldEditor: ThickCursorTextView?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if customFieldEditor == nil {
            customFieldEditor = ThickCursorTextView()
            customFieldEditor?.isFieldEditor = true
            customFieldEditor?.isRichText = false
        }
        return customFieldEditor
    }
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
    var isLocked: Bool = false  // Whether this node is locked by another tab
    var isTaskCompleted: Bool = false  // Whether this is a completed task (strikethrough + grey)
    var hasNextNode: Bool = true  // Whether there's a next node to navigate to
    var placeholder: String? = nil  // Placeholder text shown when empty
    var searchQuery: String = ""  // Current search query for highlighting matches
    var onFocusChange: (Bool) -> Void
    var onAction: ((OutlineAction) -> Void)?
    var onSplitLine: ((String) -> Void)?  // Called when splitting line, passes text after cursor
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var fontWeight: NSFont.Weight = .regular

    func makeNSView(context: Context) -> WrappingTextFieldHost {
        let hostView = WrappingTextFieldHost()

        let textField = OutlineNSTextField()
        textField.delegate = context.coordinator
        // Action handler will be set in updateNSView
        textField.actionHandler = nil
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

        // Set placeholder if provided
        if let placeholder = placeholder {
            textField.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.placeholderTextColor,
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
                ]
            )
        }

        hostView.textField = textField
        hostView.addSubview(textField)

        return hostView
    }

    func updateNSView(_ nsView: WrappingTextFieldHost, context: Context) {
        guard let textField = nsView.textField else { return }

        // Keep coordinator's parent reference up to date
        context.coordinator.parent = self

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

        // Update placeholder - clear it if no longer applicable
        if let placeholder = placeholder {
            textField.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.placeholderTextColor,
                    .font: weightedFont
                ]
            )
        } else {
            textField.placeholderAttributedString = nil
        }

        // Update action handler - capture the current onAction directly
        if let outlineTextField = textField as? OutlineNSTextField {
            let currentOnAction = self.onAction
            outlineTextField.actionHandler = { action in
                currentOnAction?(action)
            }

            // Update locked state
            outlineTextField.isNodeLocked = self.isLocked

            // Handle mouse click focus - ensure document.focusedNodeId is updated
            // But don't allow focus on locked nodes
            let currentOnFocusChange = self.onFocusChange
            outlineTextField.onMouseDownFocus = {
                if outlineTextField.isNodeLocked {
                    // Don't accept focus on locked nodes - resign immediately
                    outlineTextField.window?.makeFirstResponder(nil)
                    return
                }
                currentOnFocusChange(true)
            }
        }

        // Update editable state based on lock
        textField.isEditable = !isLocked
        textField.isSelectable = !isLocked

        // Update text color, strikethrough, and search highlighting
        if isTaskCompleted {
            textField.textColor = NSColor.secondaryLabelColor
            // Apply strikethrough using attributed string
            let attributes: [NSAttributedString.Key: Any] = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.secondaryLabelColor,
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: weightedFont
            ]
            textField.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        } else if !searchQuery.isEmpty {
            // Apply search highlighting
            textField.textColor = NSColor.labelColor
            let attributedString = NSMutableAttributedString(string: text, attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: weightedFont
            ])

            // Find and highlight all occurrences of the search query (case-insensitive)
            let lowercasedText = text.lowercased()
            let lowercasedQuery = searchQuery.lowercased()
            var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

            while let range = lowercasedText.range(of: lowercasedQuery, range: searchRange) {
                let nsRange = NSRange(range, in: text)
                attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.5), range: nsRange)
                searchRange = range.upperBound..<lowercasedText.endIndex
            }

            textField.attributedStringValue = attributedString
        } else {
            textField.textColor = NSColor.labelColor
            // Remove strikethrough/highlighting by setting plain string
            if textField.attributedStringValue.string == text {
                // Check if it has strikethrough or highlighting and remove it
                let range = NSRange(location: 0, length: textField.attributedStringValue.length)
                if range.length > 0 {
                    var hasFormatting = false
                    textField.attributedStringValue.enumerateAttribute(.strikethroughStyle, in: range) { value, _, _ in
                        if value != nil { hasFormatting = true }
                    }
                    textField.attributedStringValue.enumerateAttribute(.backgroundColor, in: range) { value, _, _ in
                        if value != nil { hasFormatting = true }
                    }
                    if hasFormatting {
                        textField.stringValue = text
                    }
                }
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

            // Get the actual text (excluding any ghost suggestion)
            if let outlineTextField = textField as? OutlineNSTextField {
                // Use actualText if suggestion is showing, otherwise use stringValue
                let actualText = outlineTextField.getActualText()
                parent.text = actualText

                // Reset progressive selection state when text changes
                outlineTextField.resetSelectionState()
            } else {
                parent.text = textField.stringValue
            }

            // Invalidate intrinsic content size when text changes
            // This ensures the view recalculates height for wrapped text
            textField.invalidateIntrinsicContentSize()
            if let hostView = textField.superview as? WrappingTextFieldHost {
                hostView.invalidateIntrinsicContentSize()
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
                // Navigate to previous bullet if empty OR at first visual line
                if textView.string.isEmpty || isAtFirstVisualLine(textView) {
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

                // Navigate to next bullet if empty OR at last visual line
                if textView.string.isEmpty || isAtLastVisualLine(textView) {
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
                  let _ = textView.textContainer else {
                return true // Default to allowing navigation if we can't determine
            }

            let totalGlyphs = layoutManager.numberOfGlyphs
            let textLength = textView.string.count

            // Empty text - always on last line
            if totalGlyphs == 0 || textLength == 0 {
                return true
            }

            // Check if text has only one line (no wrapping) - always on last line
            var firstLineRange = NSRange(location: 0, length: 0)
            layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLineRange)

            var lastLineRange = NSRange(location: 0, length: 0)
            layoutManager.lineFragmentRect(forGlyphAt: totalGlyphs - 1, effectiveRange: &lastLineRange)

            // If first and last line fragments are the same, text is single line
            if firstLineRange.location == lastLineRange.location {
                return true
            }

            // Multi-line text: check cursor position
            let selectedRange = textView.selectedRange()
            let cursorLocation = selectedRange.location

            let glyphIndex: Int
            if cursorLocation >= textLength {
                glyphIndex = totalGlyphs - 1
            } else {
                glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorLocation)
            }

            var cursorLineRange = NSRange(location: 0, length: 0)
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &cursorLineRange)

            return cursorLineRange.location == lastLineRange.location
        }
    }
}

/// NSTextField subclass that handles outline keyboard shortcuts
class OutlineNSTextField: NSTextField {
    var actionHandler: ((OutlineAction) -> Void)?
    var onMouseDownFocus: (() -> Void)?  // Called when text field gains focus via mouse click
    var isNodeLocked: Bool = false  // Whether this node is locked by another tab

    // Progressive selection state (Shift+Down)
    private enum SelectionLevel {
        case none
        case firstWord
        case wholeLine
        case extendToNextBullet
    }
    private var currentSelectionLevel: SelectionLevel = .none
    private var lastShiftDownTime: TimeInterval = 0

    // Progressive Cmd+A selection state
    private var cmdASelectionLevel: Int = 0  // 0 = text only, 1+ = bullet expansion
    private var lastCmdATime: TimeInterval = 0

    // Autocomplete state
    private var currentSuggestion: String = ""
    private(set) var isShowingSuggestion: Bool = false
    private var actualText: String = ""  // The real text without suggestion

    // Custom field editor for thick cursor
    private var thickCursorEditor: ThickCursorTextView?

    // Track if we're becoming first responder via mouse
    private var isBecomingFirstResponderViaClick = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupThickCursorCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupThickCursorCell()
    }

    private func setupThickCursorCell() {
        // Create and set a custom cell that uses our thick cursor field editor
        let customCell = ThickCursorTextFieldCell()
        customCell.wraps = true
        customCell.isScrollable = false
        self.cell = customCell
    }

    /// Get the actual text without any suggestion
    func getActualText() -> String {
        return isShowingSuggestion ? actualText : stringValue
    }

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

    override var acceptsFirstResponder: Bool {
        // Don't accept focus if this node is locked by another tab
        if isNodeLocked {
            return false
        }
        return super.acceptsFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        // Don't process mouse down if locked
        if isNodeLocked {
            return
        }
        // Track that we're focusing via mouse click
        isBecomingFirstResponderViaClick = true
        super.mouseDown(with: event)
        isBecomingFirstResponderViaClick = false
    }

    override func becomeFirstResponder() -> Bool {
        // Double-check: don't become first responder if locked
        if isNodeLocked {
            return false
        }
        let result = super.becomeFirstResponder()
        if result {
            // Notify about focus change if this came from a mouse click
            if isBecomingFirstResponderViaClick {
                onMouseDownFocus?()
            }

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
        cmdASelectionLevel = 0
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle key equivalents if THIS text field is being edited (has focus)
        // Otherwise, the event should propagate to other text fields
        guard currentEditor() != nil else {
            return super.performKeyEquivalent(with: event)
        }

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

        case 124: // Right arrow
            // Accept suggestion when at end of text and no modifiers
            if !hasCommand && !hasOption && !hasShift {
                if isShowingSuggestion {
                    if let editor = currentEditor() as? NSTextView {
                        let cursorPosition = editor.selectedRange().location
                        if cursorPosition == actualText.count {
                            _ = acceptSuggestion()
                            return true
                        }
                    }
                }
            }

        case 48: // Tab
            // Clear any suggestion when indenting/outdenting
            clearSuggestion()
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
            // Clear suggestion first if showing
            if isShowingSuggestion {
                clearSuggestion()
                return true
            }
            // Then clear multi-selection if active
            if cmdASelectionLevel > 0 {
                cmdASelectionLevel = 0
                actionHandler?(.clearSelection)
                return true
            }
            // Otherwise zoom to root
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

        case 37: // L
            if hasCommand && hasShift {
                // Cmd+Shift+L: toggle task mode
                actionHandler?(.toggleTask)
                return true
            }

        case 3: // F
            if hasCommand && hasShift {
                // Cmd+Shift+F: toggle focus mode
                actionHandler?(.toggleFocusMode)
                return true
            } else if hasCommand && !hasShift && !hasOption {
                // Cmd+F: toggle search
                actionHandler?(.toggleSearch)
                return true
            }

        case 4: // H
            if hasCommand && hasShift {
                // Cmd+Shift+H: go home and collapse all
                actionHandler?(.goHomeAndCollapseAll)
                return true
            }

        case 0: // A
            if hasCommand && !hasShift && !hasOption {
                // Cmd+A: Progressive select all
                return handleProgressiveCmdA()
            }

        default:
            break
        }

        return super.performKeyEquivalent(with: event)
    }

    /// Handle progressive Cmd+A selection
    /// First press: select all text in bullet
    /// Subsequent presses: expand to sibling bullets, then parent's siblings, etc.
    private func handleProgressiveCmdA() -> Bool {
        guard let editor = currentEditor() as? NSTextView else { return false }

        let currentTime = Date.timeIntervalSinceReferenceDate
        let timeSinceLastPress = currentTime - lastCmdATime

        // Reset if too much time has passed (more than 1.5 seconds)
        if timeSinceLastPress > 1.5 {
            cmdASelectionLevel = 0
        }

        lastCmdATime = currentTime

        let text = editor.string
        let currentSelection = editor.selectedRange()

        // Check if all text is already selected
        let isAllTextSelected = currentSelection.location == 0 && currentSelection.length == text.count

        if cmdASelectionLevel == 0 && !isAllTextSelected {
            // First Cmd+A: select all text in this bullet
            editor.setSelectedRange(NSRange(location: 0, length: text.count))
            cmdASelectionLevel = 1
            return true
        } else {
            // Already selected all text (or second+ press): expand to bullets
            cmdASelectionLevel += 1
            actionHandler?(.progressiveSelectAll)
            return true
        }
    }

    override func keyDown(with event: NSEvent) {
        // Handle plain arrow keys on empty text fields
        // (doCommandBy may not be called for empty fields)
        if stringValue.isEmpty {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let noModifiers = flags.isEmpty || flags == .numericPad

            if noModifiers {
                switch event.keyCode {
                case 126: // Up arrow
                    actionHandler?(.navigateUp)
                    return
                case 125: // Down arrow
                    actionHandler?(.navigateDown)
                    return
                default:
                    break
                }
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Autocomplete

    /// Get the current word being typed (word before cursor)
    private func getCurrentWord() -> (word: String, range: NSRange)? {
        guard let editor = currentEditor() as? NSTextView else { return nil }
        let text = editor.string
        let cursorPosition = editor.selectedRange().location

        guard cursorPosition > 0 && cursorPosition <= text.count else { return nil }

        // Find word boundaries
        let nsText = text as NSString
        let wordRange = nsText.rangeOfCharacter(from: .whitespaces, options: .backwards, range: NSRange(location: 0, length: cursorPosition))

        let wordStart = wordRange.location == NSNotFound ? 0 : wordRange.location + 1
        let wordLength = cursorPosition - wordStart

        guard wordLength >= 2 else { return nil }  // Only suggest for 2+ characters

        let word = nsText.substring(with: NSRange(location: wordStart, length: wordLength))
        return (word, NSRange(location: wordStart, length: wordLength))
    }

    /// Get completion suggestions for a partial word
    private func getCompletions(for partialWord: String) -> [String] {
        let checker = NSSpellChecker.shared
        let language = checker.language()

        // Get completions from spell checker
        let completions = checker.completions(
            forPartialWordRange: NSRange(location: 0, length: partialWord.count),
            in: partialWord,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []

        // Filter to only include completions that start with the partial word (case-insensitive)
        return completions.filter { $0.lowercased().hasPrefix(partialWord.lowercased()) }
    }

    /// Check if autocomplete is enabled (defaults to true)
    private var isAutocompleteEnabled: Bool {
        // If key doesn't exist, default to true
        if UserDefaults.standard.object(forKey: "autocompleteEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "autocompleteEnabled")
    }

    /// Update the inline suggestion based on current text
    func updateSuggestion() {
        // Check if autocomplete is enabled in settings
        guard isAutocompleteEnabled else {
            clearSuggestion()
            return
        }

        guard let editor = currentEditor() as? NSTextView else {
            clearSuggestion()
            return
        }

        // Only show suggestion when cursor is at the end
        let cursorPosition = editor.selectedRange().location
        let textLength = editor.string.count

        guard cursorPosition == textLength else {
            clearSuggestion()
            return
        }

        guard let (currentWord, _) = getCurrentWord() else {
            clearSuggestion()
            return
        }

        let completions = getCompletions(for: currentWord)

        guard let firstCompletion = completions.first,
              firstCompletion.lowercased() != currentWord.lowercased() else {
            clearSuggestion()
            return
        }

        // Get the remaining part of the suggestion
        let suggestionSuffix = String(firstCompletion.dropFirst(currentWord.count))

        guard !suggestionSuffix.isEmpty else {
            clearSuggestion()
            return
        }

        // Store the suggestion
        currentSuggestion = suggestionSuffix
        actualText = stringValue
        isShowingSuggestion = true

        // Show ghost text by appending attributed suggestion
        showGhostText(suggestionSuffix)
    }

    /// Show the ghost text suggestion
    private func showGhostText(_ suggestion: String) {
        guard let editor = currentEditor() as? NSTextView else { return }

        let currentText = actualText
        let fullText = currentText + suggestion

        let attributedString = NSMutableAttributedString(string: fullText)

        // Style the actual text normally
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        attributedString.setAttributes(textAttributes, range: NSRange(location: 0, length: currentText.count))

        // Style the suggestion as ghost text
        let ghostAttributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        attributedString.setAttributes(ghostAttributes, range: NSRange(location: currentText.count, length: suggestion.count))

        // Update the text view
        editor.textStorage?.setAttributedString(attributedString)

        // Keep cursor at end of actual text (before suggestion)
        editor.setSelectedRange(NSRange(location: currentText.count, length: 0))
    }

    /// Clear the current suggestion
    func clearSuggestion() {
        guard isShowingSuggestion else { return }

        isShowingSuggestion = false
        currentSuggestion = ""

        // Restore actual text
        if let editor = currentEditor() as? NSTextView {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
            let attributedString = NSAttributedString(string: actualText, attributes: attributes)
            editor.textStorage?.setAttributedString(attributedString)
            editor.setSelectedRange(NSRange(location: actualText.count, length: 0))
        }
    }

    /// Accept the current suggestion
    func acceptSuggestion() -> Bool {
        guard isShowingSuggestion && !currentSuggestion.isEmpty else { return false }

        // Accept the suggestion
        let newText = actualText + currentSuggestion

        isShowingSuggestion = false
        currentSuggestion = ""
        actualText = newText

        // Reset text with normal styling
        if let editor = currentEditor() as? NSTextView {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
            let attributedString = NSAttributedString(string: newText, attributes: attributes)
            editor.textStorage?.setAttributedString(attributedString)
            editor.setSelectedRange(NSRange(location: newText.count, length: 0))
        }

        // Update stringValue to sync with binding
        stringValue = newText

        return true
    }

    /// Called when text changes - override to update suggestions
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)

        // Update actualText if we're not showing a suggestion
        if !isShowingSuggestion {
            actualText = stringValue
        } else {
            // User typed something while suggestion was showing
            // The stringValue now contains corrupted text (actual + typed char + suggestion remnants)
            // We need to figure out what they actually typed

            let newText = stringValue
            let expectedFullText = actualText + currentSuggestion

            // If user typed a character, the new text is longer than actualText
            // but the character was inserted at actualText.count position
            if newText != expectedFullText {
                // Text was modified - extract what was added
                // The cursor was at actualText.count, so new char was inserted there
                if newText.count > actualText.count {
                    // Find the new character(s) that were typed
                    // They should be at position actualText.count
                    let insertionPoint = actualText.count

                    // Get the new text without the suggestion (which may be corrupted)
                    // The safest approach: take actualText + new chars typed
                    // New chars = everything from insertionPoint that's NOT the old suggestion

                    let afterInsertion = String(newText.dropFirst(insertionPoint))
                    // Remove the old suggestion from the end if it's still there
                    var newChars = afterInsertion
                    if afterInsertion.hasSuffix(currentSuggestion) {
                        newChars = String(afterInsertion.dropLast(currentSuggestion.count))
                    } else if !currentSuggestion.isEmpty && afterInsertion.contains(currentSuggestion.first!) {
                        // Suggestion might be partially there, just take 1 char
                        newChars = String(afterInsertion.prefix(1))
                    }

                    actualText = actualText + newChars
                }
                // else: deletion or other edit, just use newText
                else {
                    actualText = newText
                }
            }

            // Clear suggestion and restore clean state
            isShowingSuggestion = false
            currentSuggestion = ""

            // Reset the text field to just the actual text
            if let editor = currentEditor() as? NSTextView {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor.labelColor
                ]
                let attributedString = NSAttributedString(string: actualText, attributes: attributes)
                editor.textStorage?.setAttributedString(attributedString)
                editor.setSelectedRange(NSRange(location: actualText.count, length: 0))
            }
            stringValue = actualText
        }

        // Debounce suggestion updates
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(delayedUpdateSuggestion), object: nil)
        perform(#selector(delayedUpdateSuggestion), with: nil, afterDelay: 0.15)
    }

    @objc private func delayedUpdateSuggestion() {
        updateSuggestion()
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
