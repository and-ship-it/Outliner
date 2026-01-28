//
//  OutlineTextField.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

/// Actions that can be triggered from keyboard shortcuts in the text field
/// Shared across macOS and iOS platforms
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
    case navigateLeftToPrevious   // Left arrow at start of text → go to prev bullet, cursor at end
    case navigateRightToNext      // Right arrow at end of text → go to next bullet, cursor at start
    case zoomIn
    case zoomOut
    case zoomToRoot
    case selectRowDown    // Shift+Down: select current row, then extend down
    case selectRowUp      // Shift+Up: select current row, then extend up
    case progressiveSelectAll  // Cmd+A progressive selection
    case clearSelection        // Escape to clear selection
    case copySelected          // Cmd+C with multi-selection
    case cutSelected           // Cmd+X with multi-selection
    case deleteWithChildren
    case deleteSelected        // Delete all selected nodes (Cmd+Shift+Backspace with selection)
    case deleteEmpty           // Delete empty bullet on backspace (merge with previous)
    case mergeWithPrevious(String)  // Merge current text with previous bullet (backspace at beginning)
    case toggleTask
    case toggleFocusMode
    case goHomeAndCollapseAll
    case toggleSearch
    case smartPaste([OutlineNode], cursorAtEnd: Bool, cursorAtStart: Bool)  // Structured paste
    case insertLink(URL)  // Insert URL and fetch title asynchronously
}

#if os(macOS)
import AppKit

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
    var protectedPrefixLength: Int = 0  // Number of characters at start that cannot be edited (e.g. date prefix)
    var isTaskCompleted: Bool = false  // Whether this is a completed task (strikethrough + grey)
    var isUnseen: Bool = false  // Whether this node was externally created and not yet seen (blue text)
    var isDateNode: Bool = false  // Whether this is a date node (keeps standard color for protected prefix)
    var hasNextNode: Bool = true  // Whether there's a next node to navigate to
    var placeholder: String? = nil  // Placeholder text shown when empty
    var searchQuery: String = ""  // Current search query for highlighting matches
    var hasSelection: Bool = false  // Whether there's a multi-node selection active
    var nodeId: UUID  // The ID of the node this text field represents (for view recycling safety)
    var nodeTitle: String = ""  // For debugging
    var cursorAtEnd: Bool = false  // Position cursor at end when focusing (for merge-up)
    var cursorOffset: Int? = nil  // Position cursor at specific character offset (for merge-with-previous)
    var focusVersion: Int = 0  // Increments to force focus refresh even when focusedNodeId unchanged
    var onCursorPositioned: (() -> Void)? = nil  // Called after cursor is positioned (to reset flag)
    var onFocusChange: (Bool) -> Void
    var onAction: ((OutlineAction) -> Void)?
    var onSplitLine: ((String) -> Void)?  // Called when splitting line, passes text after cursor
    var isReadOnly: Bool = false  // Disable editing for old week browsing
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

            // Update multi-selection state
            outlineTextField.hasMultiSelection = self.hasSelection

            // Store the current node ID on the text field (critical for view recycling)
            let expectedNodeId = self.nodeId
            let expectedNodeTitle = self.nodeTitle
            outlineTextField.currentNodeId = expectedNodeId
            outlineTextField.currentNodeTitle = expectedNodeTitle

            // Handle mouse click focus - ensure document.focusedNodeId is updated
            let currentOnFocusChange = self.onFocusChange
            outlineTextField.onMouseDownFocus = { [weak outlineTextField] in
                guard let tf = outlineTextField else { return }
                print("[DEBUG] onMouseDownFocus: CALLED - expected node='\(expectedNodeTitle)' (id: \(expectedNodeId.uuidString.prefix(8))), current node='\(tf.currentNodeTitle)' (id: \(tf.currentNodeId?.uuidString.prefix(8) ?? "nil"))")

                // CRITICAL: Check if the text field is still showing the same node
                // If not, this callback is stale due to view recycling
                if tf.currentNodeId != expectedNodeId {
                    print("[DEBUG] onMouseDownFocus: STALE CALLBACK - node changed from '\(expectedNodeTitle)' to '\(tf.currentNodeTitle)', skipping")
                    return
                }

                print("[DEBUG] onMouseDownFocus: calling onFocusChange(true) for node '\(expectedNodeTitle)'")
                currentOnFocusChange(true)
            }
        }

        // Editable unless in read-only mode (old week browsing)
        textField.isEditable = !isReadOnly
        textField.isSelectable = true

        // Determine base text color (blue for unseen externally-created nodes)
        let baseTextColor: NSColor = isUnseen ? .systemBlue : .labelColor

        // Update text color, strikethrough, search highlighting, and link styling
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
            textField.textColor = baseTextColor
            let attributedString = NSMutableAttributedString(string: text, attributes: [
                .foregroundColor: baseTextColor,
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
            // Check for markdown links and style them
            let links = LinkParser.parseMarkdownLinks(text)
            if !links.isEmpty {
                textField.textColor = baseTextColor
                let attributedString = NSMutableAttributedString(string: text, attributes: [
                    .foregroundColor: baseTextColor,
                    .font: weightedFont
                ])

                // Style each markdown link
                for link in links {
                    let fullRange = NSRange(link.range, in: text)

                    // Make the entire [text](url) very dim
                    attributedString.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: fullRange)

                    // Find and style just the link text part (between [ and ])
                    let linkPattern = "\\[([^\\]]+)\\]"
                    if let regex = try? NSRegularExpression(pattern: linkPattern, options: []),
                       let match = regex.firstMatch(in: text, options: [], range: fullRange),
                       let textPartRange = Range(match.range(at: 1), in: text) {
                        let nsTextRange = NSRange(textPartRange, in: text)
                        // Link text: grey, underlined
                        attributedString.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsTextRange)
                        attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsTextRange)
                        attributedString.addAttribute(.underlineColor, value: NSColor.secondaryLabelColor, range: nsTextRange)
                        // Store URL for click handling
                        attributedString.addAttribute(.link, value: link.url, range: nsTextRange)
                    }
                }

                textField.attributedStringValue = attributedString

                // Store links on the text field for click handling
                if let outlineTextField = textField as? OutlineNSTextField {
                    outlineTextField.markdownLinks = links.map { (NSRange($0.range, in: text), $0.url) }
                }
            } else {
                textField.textColor = baseTextColor
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
                        textField.attributedStringValue.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
                            if value != nil { hasFormatting = true }
                        }
                        if hasFormatting {
                            textField.stringValue = text
                        }
                    }
                }
            }
        }

        // Fade protected prefix for reminder metadata children (note/link/recurrence).
        // Date nodes keep standard label color — they're protected but not faded.
        if protectedPrefixLength > 0 && text.count >= protectedPrefixLength && !isDateNode {
            let prefixRange = NSRange(location: 0, length: protectedPrefixLength)
            let current = NSMutableAttributedString(attributedString: textField.attributedStringValue)
            current.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: prefixRange)
            textField.attributedStringValue = current
        }

        // Handle focus changes from SwiftUI -> AppKit
        // Simple approach: ensure first responder and cursor visibility
        let fieldEditor = textField.currentEditor()
        let isCurrentlyFirstResponder = fieldEditor != nil &&
            textField.window?.firstResponder === fieldEditor

        if isFocused {
            // Check if focusVersion changed - forces a refocus even if already first responder
            let needsForcedRefocus = focusVersion != context.coordinator.lastFocusVersion
            if needsForcedRefocus {
                print("[DEBUG] updateNSView: focusVersion changed \(context.coordinator.lastFocusVersion) -> \(focusVersion), forcing refocus")
                context.coordinator.lastFocusVersion = focusVersion
            }

            if !isCurrentlyFirstResponder && !context.coordinator.isUpdatingFocus {
                // Not currently focused - need to become first responder
                print("[DEBUG] updateNSView: will refocus - isCurrentlyFirstResponder=\(isCurrentlyFirstResponder), needsForcedRefocus=\(needsForcedRefocus)")
                context.coordinator.isUpdatingFocus = true

                // Capture values for async block
                let shouldCursorAtEnd = cursorAtEnd
                let specificOffset = cursorOffset
                let cursorPositionedCallback = onCursorPositioned
                let coordinator = context.coordinator

                // Use async dispatch to ensure view is fully ready after structural changes
                DispatchQueue.main.async {
                    // Use selectText to ensure editing session starts (creates field editor)
                    textField.selectText(nil)

                    // Now set cursor position
                    if let editor = textField.currentEditor() {
                        if let offset = specificOffset {
                            // Position at specific offset (for merge-with-previous)
                            let safeOffset = min(offset, editor.string.count)
                            editor.selectedRange = NSRange(location: safeOffset, length: 0)
                            cursorPositionedCallback?()  // Reset the flag
                        } else if shouldCursorAtEnd {
                            // Position at end (for merge-up after backspace delete)
                            editor.selectedRange = NSRange(location: editor.string.count, length: 0)
                            cursorPositionedCallback?()  // Reset the flag
                        } else {
                            // Position at start for keyboard navigation
                            editor.selectedRange = NSRange(location: 0, length: 0)
                        }
                    }

                    // Reset flag AFTER async work completes
                    coordinator.isUpdatingFocus = false
                }
            }

            // ALWAYS ensure insertion point is visible when we should be focused
            if let editor = textField.currentEditor() as? NSTextView {
                editor.updateInsertionPointStateAndRestartTimer(true)
            }
        } else if isCurrentlyFirstResponder && !context.coordinator.isUpdatingFocus {
            // Resign first responder
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
        var lastFocusVersion: Int = 0  // Track focus version to detect forced refreshes

        init(_ parent: OutlineTextField) {
            self.parent = parent
            self.lastFocusVersion = parent.focusVersion
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }

            // If protected prefix, ensure it's preserved
            if parent.protectedPrefixLength > 0 {
                let currentText = textField.stringValue
                let prefix = String(parent.text.prefix(parent.protectedPrefixLength))
                if !currentText.hasPrefix(prefix) {
                    // Restore prefix + keep anything typed after it
                    let suffix = currentText.count > parent.protectedPrefixLength
                        ? String(currentText.dropFirst(min(currentText.count, parent.protectedPrefixLength)))
                        : ""
                    textField.stringValue = prefix + suffix
                }
                parent.text = textField.stringValue
                return
            }

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
            print("[DEBUG] controlTextDidBeginEditing: isUpdatingFocus=\(isUpdatingFocus)")
            guard !isUpdatingFocus else {
                print("[DEBUG] controlTextDidBeginEditing: SKIPPED (isUpdatingFocus)")
                return
            }
            print("[DEBUG] controlTextDidBeginEditing: calling onFocusChange(true)")
            parent.onFocusChange(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            print("[DEBUG] controlTextDidEndEditing: isUpdatingFocus=\(isUpdatingFocus)")
            guard !isUpdatingFocus else {
                print("[DEBUG] controlTextDidEndEditing: SKIPPED (isUpdatingFocus)")
                return
            }
            print("[DEBUG] controlTextDidEndEditing: calling onFocusChange(false)")
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

            case #selector(NSResponder.moveLeft(_:)):
                // Navigate to previous bullet if cursor is at position 0
                let leftCursor = textView.selectedRange().location
                if leftCursor == 0 && textView.selectedRange().length == 0 {
                    parent.onAction?(.navigateLeftToPrevious)
                    return true
                }
                return false

            case #selector(NSResponder.moveRight(_:)):
                // Navigate to next bullet if cursor is at end of text
                let rightCursor = textView.selectedRange().location
                if rightCursor >= textView.string.count && textView.selectedRange().length == 0 {
                    parent.onAction?(.navigateRightToNext)
                    return true
                }
                return false

            case #selector(NSResponder.moveDownAndModifySelection(_:)):
                // Shift+Down: select row and extend down
                print("[DEBUG] doCommandBy: moveDownAndModifySelection, calling selectRowDown")
                parent.onAction?(.selectRowDown)
                return true

            case #selector(NSResponder.moveUpAndModifySelection(_:)):
                // Shift+Up: select row and extend up
                print("[DEBUG] doCommandBy: moveUpAndModifySelection, calling selectRowUp")
                parent.onAction?(.selectRowUp)
                return true

            case #selector(NSResponder.insertTab(_:)):
                // Tab = indent
                parent.onAction?(.indent)
                return true

            case #selector(NSResponder.insertBacktab(_:)):
                // Shift+Tab = outdent
                parent.onAction?(.outdent)
                return true

            case #selector(NSResponder.deleteBackward(_:)):
                // Backspace on empty bullet: delete the bullet and move to previous
                if textView.string.isEmpty {
                    parent.onAction?(.deleteEmpty)
                    return true
                }
                // Backspace at beginning of bullet with text: merge with previous bullet
                let cursorPosition = textView.selectedRange().location
                if cursorPosition == 0 && !textView.string.isEmpty {
                    let currentText = textView.string
                    parent.onAction?(.mergeWithPrevious(currentText))
                    return true
                }
                // Otherwise, let default backspace behavior delete character
                return false

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
    var hasMultiSelection: Bool = false  // Whether there's a multi-node selection active

    // Store the current node ID to handle view recycling correctly
    var currentNodeId: UUID?
    var currentNodeTitle: String = ""  // For debugging

    // Markdown links for click handling
    var markdownLinks: [(range: NSRange, url: URL)] = []

    // STATIC flag: tracks if ANY OutlineNSTextField is receiving a mouse click
    // This is needed because view recycling can cause a different text field instance
    // to become first responder than the one that received the mouse click
    private static var anyTextFieldReceivingClick = false

    // Progressive Cmd+A selection state
    private var cmdASelectionLevel: Int = 0  // 0 = text only, 1+ = bullet expansion
    private var lastCmdATime: TimeInterval = 0

    // Autocomplete state
    private var currentSuggestion: String = ""
    private(set) var isShowingSuggestion: Bool = false
    private var actualText: String = ""  // The real text without suggestion

    // Custom field editor for thick cursor
    private var thickCursorEditor: ThickCursorTextView?

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

    override func mouseDown(with event: NSEvent) {
        // Check if clicking on a markdown link - open URL instead of editing
        if !markdownLinks.isEmpty {
            let clickPoint = convert(event.locationInWindow, from: nil)
            if let clickedURL = urlAtPoint(clickPoint) {
                // Cmd+click or single click on link opens URL
                NSWorkspace.shared.open(clickedURL)
                return
            }
        }

        // CRITICAL: Call onMouseDownFocus IMMEDIATELY, BEFORE super.mouseDown
        // This updates document.focusedNodeId before SwiftUI reacts to the click
        // Otherwise SwiftUI will force-focus the OLD node based on stale focusedNodeId
        print("[DEBUG] mouseDown: calling onMouseDownFocus IMMEDIATELY for node '\(currentNodeTitle)'")
        onMouseDownFocus?()

        // Now proceed with normal mouse down handling
        print("[DEBUG] mouseDown: calling super.mouseDown for node '\(currentNodeTitle)'")
        super.mouseDown(with: event)
        print("[DEBUG] mouseDown: super.mouseDown completed for node '\(currentNodeTitle)'")
    }

    /// Check if a point is within a markdown link and return its URL
    private func urlAtPoint(_ point: NSPoint) -> URL? {
        // Try to use layout manager when editing (more accurate)
        if let layoutManager = (currentEditor() as? NSTextView)?.layoutManager,
           let textContainer = (currentEditor() as? NSTextView)?.textContainer {
            let textPoint = NSPoint(x: point.x - 2, y: point.y)  // Adjust for text inset
            let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            for (range, url) in markdownLinks {
                if charIndex >= range.location && charIndex < range.location + range.length {
                    return url
                }
            }
            return nil
        }

        // Not editing - estimate position from bounds
        guard let cell = cell else { return nil }
        let cellFrame = bounds
        let textRect = cell.titleRect(forBounds: cellFrame)

        // Estimate character position from click
        let relativeX = point.x - textRect.origin.x
        let textWidth = max(textRect.width, 1.0)
        let textCount = max(stringValue.count, 1)
        let charWidth = textWidth / CGFloat(textCount)
        let estimatedCharIndex = Int(relativeX / charWidth)

        // Check if estimated position falls within any link range
        for (range, url) in markdownLinks {
            if estimatedCharIndex >= range.location && estimatedCharIndex < range.location + range.length {
                return url
            }
        }
        return nil
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        print("[DEBUG] becomeFirstResponder: result=\(result), node='\(currentNodeTitle)'")
        // Note: Focus is now handled in mouseDown, not here
        // This avoids race conditions with SwiftUI's focus management
        return result
    }

    override func resignFirstResponder() -> Bool {
        return super.resignFirstResponder()
    }

    /// Reset selection state (called when text changes)
    func resetSelectionState() {
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

        // Clear multi-selection on any key press except:
        // - Cmd+Shift+Backspace (which deletes selected)
        // - Escape (which handles clearing itself)
        // - Cmd+A (which handles selection itself)
        // - Shift+Up/Down (which extends selection)
        // - Cmd+C (copy selected)
        // - Cmd+X (cut selected)
        // - Tab/Shift+Tab, Cmd+]/Cmd+[ (indent/outdent selected)
        if hasMultiSelection {
            let isCmdShiftBackspace = event.keyCode == 51 && hasCommand && hasShift
            let isEscape = event.keyCode == 53
            let isCmdA = event.keyCode == 0 && hasCommand && !hasShift && !hasOption
            let isShiftUp = event.keyCode == 126 && hasShift && !hasCommand && !hasOption
            let isShiftDown = event.keyCode == 125 && hasShift && !hasCommand && !hasOption
            let isCmdC = event.keyCode == 8 && hasCommand && !hasShift && !hasOption
            let isCmdX = event.keyCode == 7 && hasCommand && !hasShift && !hasOption
            let isTab = event.keyCode == 48
            let isCmdBracket = (event.keyCode == 30 || event.keyCode == 33) && hasCommand && !hasShift && !hasOption

            if !isCmdShiftBackspace && !isEscape && !isCmdA && !isShiftUp && !isShiftDown && !isCmdC && !isCmdX && !isTab && !isCmdBracket {
                cmdASelectionLevel = 0
                actionHandler?(.clearSelection)
            }
        }

        // Handle key equivalents (keys with modifiers)
        switch event.keyCode {
        case 126: // Up arrow
            if hasCommand && hasShift && hasOption {
                // Cmd+Shift+Option+Up: collapse all children
                actionHandler?(.collapseAll)
                return true
            } else if hasCommand && hasShift {
                // Cmd+Shift+Up: collapse
                print("[DEBUG] performKeyEquivalent: Cmd+Shift+Up detected, calling collapse")
                actionHandler?(.collapse)
                return true
            } else if hasShift && hasOption {
                // Shift+Option+Up: move bullet up
                actionHandler?(.moveUp)
                return true
            } else if hasShift && !hasCommand && !hasOption {
                // Shift+Up: select row and extend up
                print("[DEBUG] performKeyEquivalent: Shift+Up detected, calling selectRowUp")
                actionHandler?(.selectRowUp)
                return true
            }
            // Plain Cmd+Up: let system handle (move to start of text/document)

        case 125: // Down arrow
            if hasCommand && hasShift && hasOption {
                // Cmd+Shift+Option+Down: expand all children
                actionHandler?(.expandAll)
                return true
            } else if hasCommand && hasShift {
                // Cmd+Shift+Down: expand
                actionHandler?(.expand)
                return true
            } else if hasShift && hasOption {
                // Shift+Option+Down: move bullet down
                actionHandler?(.moveDown)
                return true
            } else if hasShift && !hasCommand && !hasOption {
                // Shift+Down: select row and extend down
                print("[DEBUG] performKeyEquivalent: Shift+Down detected, calling selectRowDown")
                actionHandler?(.selectRowDown)
                return true
            }
            // Plain Cmd+Down: let system handle (move to end of text/document)

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

        case 30: // ] — Cmd+] indent (standard Apple shortcut)
            if hasCommand && !hasShift && !hasOption {
                clearSuggestion()
                actionHandler?(.indent)
                return true
            }

        case 33: // [ — Cmd+[ outdent (standard Apple shortcut)
            if hasCommand && !hasShift && !hasOption {
                clearSuggestion()
                actionHandler?(.outdent)
                return true
            }

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
            if hasCommand && hasShift && !hasOption {
                actionHandler?(.zoomIn)
                return true
            }

        case 43: // Comma (,)
            if hasCommand && hasShift && !hasOption {
                actionHandler?(.zoomOut)
                return true
            }

        case 51: // Delete/Backspace
            if hasCommand && hasShift {
                // Cmd+Shift+Delete: delete selected nodes if there's a selection,
                // otherwise delete focused bullet and all children
                if hasMultiSelection {
                    actionHandler?(.deleteSelected)
                } else {
                    actionHandler?(.deleteWithChildren)
                }
                return true
            }
            // Clear ghost suggestion before backspace so it deletes actual text
            if isShowingSuggestion {
                clearSuggestion()
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

        case 8: // C
            if hasCommand && !hasShift && !hasOption {
                // Cmd+C: Copy selected nodes if multi-selection active
                if hasMultiSelection {
                    actionHandler?(.copySelected)
                    return true
                }
                // Otherwise let default copy handle text selection
            }

        case 7: // X
            if hasCommand && !hasShift && !hasOption {
                // Cmd+X: Cut selected nodes if multi-selection active
                if hasMultiSelection {
                    actionHandler?(.cutSelected)
                    return true
                }
                // Otherwise let default cut handle text selection
            }

        case 9: // V
            if hasCommand && !hasShift && !hasOption {
                // Cmd+V: Smart Paste
                if handleSmartPaste() {
                    return true
                }
                // If smart paste returned false, let default paste handle it
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

    // MARK: - Smart Paste

    /// Handle smart paste - returns true if paste was handled, false to use default
    private func handleSmartPaste() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else {
            print("[SmartPaste] No string content in pasteboard")
            return false
        }

        // Check if pasting just a URL - convert to smart link
        if let url = SmartPasteParser.isJustURL(text) {
            print("[SmartPaste] Detected URL: \(url)")
            actionHandler?(.insertLink(url))
            return true
        }

        print("[SmartPaste] Parsing: '\(text.prefix(50))...' (\(text.count) chars)")
        let result = SmartPasteParser.parse(text)
        print("[SmartPaste] Result: \(result.nodes.count) nodes, isSingleLine=\(result.isSingleLine)")

        // Single line without structure → let default paste handle it
        if result.isSingleLine && result.nodes.count <= 1 {
            if let node = result.nodes.first {
                // If it's a simple node (no children, not a task), use default paste
                if !node.hasChildren && !node.isTask {
                    return false
                }
            } else {
                // Empty result, use default paste
                return false
            }
        }

        // Structured content → smart paste
        if !result.nodes.isEmpty {
            let cursorPos: Int
            if let editor = currentEditor() {
                cursorPos = editor.selectedRange.location
            } else {
                cursorPos = stringValue.count
            }
            let textLength = stringValue.count
            let cursorAtEnd = cursorPos >= textLength
            let cursorAtStart = cursorPos == 0

            actionHandler?(.smartPaste(result.nodes, cursorAtEnd: cursorAtEnd, cursorAtStart: cursorAtStart))
            return true
        }

        return false
    }

    override func keyDown(with event: NSEvent) {
        // Clear multi-selection on any regular key press (typing)
        if hasMultiSelection {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = flags.contains(.command)

            // Only clear if it's a regular typing key (no command modifier)
            if !hasCommand {
                cmdASelectionLevel = 0
                actionHandler?(.clearSelection)
            }
        }

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
        SettingsManager.shared.autocompleteEnabled
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
// iOS implementation with UITextView for text wrapping
import UIKit

struct OutlineTextField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var protectedPrefixLength: Int = 0  // Number of characters at start that cannot be edited (e.g. date prefix)
    var isDateNode: Bool = false  // Whether this is a date node (keeps standard color for protected prefix)
    var nodeId: UUID = UUID()
    var nodeTitle: String = ""
    var cursorAtEnd: Bool = false
    var cursorOffset: Int? = nil  // Position cursor at specific character offset (for merge-with-previous)
    var focusVersion: Int = 0
    var onCursorPositioned: (() -> Void)? = nil
    var onFocusChange: (Bool) -> Void
    var onCreateSibling: (() -> Void)? = nil
    var onNavigateUp: (() -> Void)? = nil  // Navigate to previous node
    var onNavigateDown: (() -> Void)? = nil  // Navigate to next node
    var onInsertLink: ((URL) -> Void)? = nil  // Insert URL as smart link
    var onDeleteEmpty: (() -> Void)? = nil  // Delete empty bullet on backspace (merge up)
    var onAction: ((OutlineAction) -> Void)? = nil  // General action handler for keyboard shortcuts
    var hasMultiSelection: (() -> Bool)? = nil  // Check if document has multi-selection
    var isReadOnly: Bool = false  // Disable editing for old week browsing
    var isUnseen: Bool = false  // Whether this node was externally created and not yet seen (blue text)
    var suppressKeyboard: Bool = false  // When true, don't programmatically becomeFirstResponder (launch/carousel)
    var fontSize: CGFloat = 17
    var fontWeight: UIFont.Weight = .regular

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WrappingTextView {
        let textView = WrappingTextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false  // Critical for auto-sizing
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.returnKeyType = .default
        textView.isEditable = !isReadOnly

        // Remove any extra padding
        textView.contentInset = .zero

        // Store coordinator reference for callbacks
        let coordinator = context.coordinator

        // Set up navigation callbacks
        textView.onNavigateUp = { [weak coordinator] in
            coordinator?.parent.onNavigateUp?()
        }
        textView.onNavigateDown = { [weak coordinator] in
            coordinator?.parent.onNavigateDown?()
        }
        textView.onReturn = { [weak coordinator] in
            coordinator?.parent.onCreateSibling?()
        }
        textView.onInsertLink = { [weak coordinator] url in
            coordinator?.parent.onInsertLink?(url)
        }
        textView.onDeleteEmpty = { [weak coordinator] in
            coordinator?.parent.onDeleteEmpty?()
        }
        textView.actionHandler = { [weak coordinator] action in
            coordinator?.parent.onAction?(action)
        }
        textView.hasMultiSelection = { [weak coordinator] in
            coordinator?.parent.hasMultiSelection?() ?? false
        }

        return textView
    }

    func updateUIView(_ textView: WrappingTextView, context: Context) {
        // Keep coordinator's parent reference up to date (critical for callbacks!)
        context.coordinator.parent = self

        // Update font and editable state
        let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        textView.font = font
        textView.isEditable = !isReadOnly

        // Determine base text color (blue for unseen externally-created nodes)
        let baseTextColor: UIColor = isUnseen ? .systemBlue : .label
        textView.textColor = baseTextColor

        // Check for markdown links and apply styling
        let links = LinkParser.parseMarkdownLinks(text)
        if !links.isEmpty && textView.text != text {
            let attributedString = NSMutableAttributedString(string: text, attributes: [
                .foregroundColor: baseTextColor,
                .font: font
            ])

            // Style each markdown link
            for link in links {
                let fullRange = NSRange(link.range, in: text)

                // Make the entire [text](url) very dim
                attributedString.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: fullRange)

                // Find and style just the link text part (between [ and ])
                let linkPattern = "\\[([^\\]]+)\\]"
                if let regex = try? NSRegularExpression(pattern: linkPattern, options: []),
                   let match = regex.firstMatch(in: text, options: [], range: fullRange),
                   let textPartRange = Range(match.range(at: 1), in: text) {
                    let nsTextRange = NSRange(textPartRange, in: text)
                    // Link text: grey, underlined
                    attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: nsTextRange)
                    attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsTextRange)
                    attributedString.addAttribute(.underlineColor, value: UIColor.secondaryLabel, range: nsTextRange)
                }
            }

            textView.attributedText = attributedString
            textView.markdownLinks = links.map { (NSRange($0.range, in: text), $0.url) }
        } else if textView.text != text {
            // No links - use plain text
            textView.text = text
            textView.markdownLinks = []
        }

        // Fade protected prefix for reminder metadata children (note/link/recurrence).
        // Date nodes keep standard label color — they're protected but not faded.
        if protectedPrefixLength > 0 && text.count >= protectedPrefixLength && !isDateNode {
            let prefixRange = NSRange(location: 0, length: protectedPrefixLength)
            let current: NSMutableAttributedString
            if let existing = textView.attributedText {
                current = NSMutableAttributedString(attributedString: existing)
            } else {
                current = NSMutableAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
                ])
            }
            current.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: prefixRange)
            textView.attributedText = current
        }

        // Handle focus changes
        // Only call becomeFirstResponder for the focused field
        // DON'T call resignFirstResponder - let iOS handle it automatically
        // This keeps the keyboard visible during focus transitions between bullets
        // Skip if suppressKeyboard is true (launch or carousel dismiss — user must tap to activate keyboard)
        if isFocused && !suppressKeyboard && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
                if let offset = cursorOffset {
                    // Position cursor at specific offset (for merge-with-previous)
                    let safeOffset = min(offset, textView.text.count)
                    if let position = textView.position(from: textView.beginningOfDocument, offset: safeOffset) {
                        textView.selectedTextRange = textView.textRange(from: position, to: position)
                    }
                } else if cursorAtEnd {
                    // Position cursor at end
                    let endPosition = textView.endOfDocument
                    textView.selectedTextRange = textView.textRange(from: endPosition, to: endPosition)
                }
            }
        }
        // Note: We deliberately don't resignFirstResponder here
        // When focus moves to a new text view, it automatically takes over
        // This prevents keyboard from dismissing during bullet creation
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: OutlineTextField

        init(_ parent: OutlineTextField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // If protected prefix, ensure it's preserved
            if parent.protectedPrefixLength > 0 {
                let currentText = textView.text ?? ""
                let prefix = String(parent.text.prefix(parent.protectedPrefixLength))
                if !currentText.hasPrefix(prefix) {
                    let suffix = currentText.count > parent.protectedPrefixLength
                        ? String(currentText.dropFirst(min(currentText.count, parent.protectedPrefixLength)))
                        : ""
                    textView.text = prefix + suffix
                }
                parent.text = textView.text ?? ""
                textView.invalidateIntrinsicContentSize()
                return
            }
            parent.text = textView.text ?? ""
            // Invalidate intrinsic content size for height recalculation
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        // Handle return key to create sibling + protect date prefix + block tab insertion
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                print("[DEBUG] textView shouldChangeTextIn: newline detected, calling onCreateSibling")
                parent.onCreateSibling?()
                return false
            }
            // Block tab character insertion — Tab is handled as indent/outdent in pressesBegan
            if text == "\t" {
                return false
            }
            // Block edits within the protected prefix range
            if parent.protectedPrefixLength > 0 && range.location < parent.protectedPrefixLength {
                return false
            }
            return true
        }
    }
}

/// Custom UITextView that supports text wrapping and spacebar trackpad navigation
class WrappingTextView: UITextView, UIGestureRecognizerDelegate {
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onReturn: (() -> Void)?
    var onInsertLink: ((URL) -> Void)?
    var onDeleteEmpty: (() -> Void)?
    var actionHandler: ((OutlineAction) -> Void)?
    var hasMultiSelection: (() -> Bool)?

    // Progressive Cmd+A state tracking (matches macOS behavior)
    private var cmdASelectionLevel: Int = 0
    private var lastCmdATime: TimeInterval = 0

    // Markdown links for tap handling
    var markdownLinks: [(range: NSRange, url: URL)] = []

    // Cursor boundary navigation state (spacebar trackpad + arrow keys)
    private var lastSelectionStart: UITextPosition?
    private var consecutiveUpAttempts: Int = 0
    private var consecutiveDownAttempts: Int = 0
    private var lastChangeTime: Date = Date()
    private let navigationThreshold: Int = 1
    private var isInContinuousNavigation: Bool = false
    private var lastNavigationDirection: Int = 0  // -1 for up, 1 for down, 0 for none

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Critical settings for auto-sizing
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0

        // Add tap gesture for link handling
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }

    // MARK: - Backspace on Empty

    override func deleteBackward() {
        if text.isEmpty {
            onDeleteEmpty?()
            return
        }
        // Backspace at beginning of bullet with text: merge with previous bullet
        if let range = selectedTextRange,
           range.isEmpty,
           offset(from: beginningOfDocument, to: range.start) == 0 {
            actionHandler?(.mergeWithPrevious(text))
            return
        }
        super.deleteBackward()
    }

    // MARK: - Intrinsic Content Size

    override var intrinsicContentSize: CGSize {
        // Calculate the size needed for the text content
        let textWidth = bounds.width > 0 ? bounds.width : 200
        let size = sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 22))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Invalidate when layout changes to recalculate height
        invalidateIntrinsicContentSize()
    }

    // MARK: - Link Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !markdownLinks.isEmpty else { return }

        let tapPoint = gesture.location(in: self)
        if let tappedURL = urlAtPoint(tapPoint) {
            UIApplication.shared.open(tappedURL)
        }
    }

    private func urlAtPoint(_ point: CGPoint) -> URL? {
        // Convert point to text container coordinates
        let textContainerOffset = CGPoint(
            x: textContainerInset.left,
            y: textContainerInset.top
        )
        let locationInTextContainer = CGPoint(
            x: point.x - textContainerOffset.x,
            y: point.y - textContainerOffset.y
        )

        // Get the character index at tap point
        let charIndex = layoutManager.characterIndex(
            for: locationInTextContainer,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        // Check if this index is within any link range
        for (range, url) in markdownLinks {
            if charIndex >= range.location && charIndex < range.location + range.length {
                return url
            }
        }
        return nil
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !markdownLinks.isEmpty else { return false }
        let tapPoint = touch.location(in: self)
        return urlAtPoint(tapPoint) != nil
    }

    // MARK: - Selection Change Detection for Spacebar Trackpad Navigation

    override var selectedTextRange: UITextRange? {
        didSet {
            checkBoundaryNavigation()
        }
    }

    private func checkBoundaryNavigation() {
        guard let selectedRange = selectedTextRange else { return }

        let currentPosition = selectedRange.start
        let now = Date()
        let timeSinceLastChange = now.timeIntervalSince(lastChangeTime)

        // Reset continuous navigation mode after a pause
        if timeSinceLastChange > 0.5 {
            isInContinuousNavigation = false
            lastNavigationDirection = 0
        }

        let textLength = text?.count ?? 0
        let cursorOffset = offset(from: beginningOfDocument, to: currentPosition)

        // Check if cursor is at the beginning (for up navigation)
        if cursorOffset == 0 {
            if let last = lastSelectionStart,
               offset(from: beginningOfDocument, to: last) == 0,
               timeSinceLastChange < 0.3 {
                consecutiveUpAttempts += 1

                let threshold = (isInContinuousNavigation && lastNavigationDirection == -1) ? 1 : navigationThreshold

                if consecutiveUpAttempts >= threshold {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onNavigateUp?()
                    consecutiveUpAttempts = 0
                    isInContinuousNavigation = true
                    lastNavigationDirection = -1
                }
            }
            consecutiveDownAttempts = 0
        }
        // Check if cursor is at the end (for down navigation)
        else if cursorOffset >= textLength {
            if let last = lastSelectionStart,
               offset(from: last, to: endOfDocument) == 0,
               timeSinceLastChange < 0.3 {
                consecutiveDownAttempts += 1

                let threshold = (isInContinuousNavigation && lastNavigationDirection == 1) ? 1 : navigationThreshold

                if consecutiveDownAttempts >= threshold {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onNavigateDown?()
                    consecutiveDownAttempts = 0
                    isInContinuousNavigation = true
                    lastNavigationDirection = 1
                }
            }
            consecutiveUpAttempts = 0
        } else {
            // Cursor is in the middle
            consecutiveUpAttempts = 0
            consecutiveDownAttempts = 0
            isInContinuousNavigation = false
            lastNavigationDirection = 0
        }

        lastSelectionStart = currentPosition
        lastChangeTime = now
    }

    // MARK: - Keyboard Shortcut Handling (External Keyboard)

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            let hasCommand = key.modifierFlags.contains(.command)
            let hasShift = key.modifierFlags.contains(.shift)
            let hasOption = key.modifierFlags.contains(.alternate)

            // --- Selection clearing (matches macOS behavior) ---
            // Most key combos clear multi-selection, except selection-specific shortcuts
            if hasMultiSelection?() == true {
                let preservesSelection: Bool = {
                    switch key.keyCode {
                    case .keyboardDeleteOrBackspace where hasCommand && hasShift: return true
                    case .keyboardEscape: return true
                    case .keyboardA where hasCommand && !hasShift && !hasOption: return true
                    case .keyboardUpArrow where hasShift && !hasCommand && !hasOption: return true
                    case .keyboardDownArrow where hasShift && !hasCommand && !hasOption: return true
                    case .keyboardC where hasCommand && !hasShift && !hasOption: return true
                    case .keyboardX where hasCommand && !hasShift && !hasOption: return true
                    case .keyboardTab: return true
                    case .keyboardOpenBracket where hasCommand: return true
                    case .keyboardCloseBracket where hasCommand: return true
                    default: return false
                    }
                }()
                if !preservesSelection && (hasCommand || hasShift || hasOption) {
                    cmdASelectionLevel = 0
                    actionHandler?(.clearSelection)
                }
            }

            // --- Zoom ---

            // Cmd+Shift+. → Zoom In
            if key.keyCode == .keyboardPeriod, hasCommand, hasShift, !hasOption {
                actionHandler?(.zoomIn)
                return
            }

            // Cmd+Shift+, → Zoom Out
            if key.keyCode == .keyboardComma, hasCommand, hasShift, !hasOption {
                actionHandler?(.zoomOut)
                return
            }

            // Escape → Clear suggestion / clear selection / zoom to root
            if key.keyCode == .keyboardEscape {
                if hasMultiSelection?() == true {
                    cmdASelectionLevel = 0
                    actionHandler?(.clearSelection)
                } else {
                    actionHandler?(.zoomToRoot)
                }
                return
            }

            // Cmd+Shift+H → Go home and collapse all
            if key.keyCode == .keyboardH, hasCommand, hasShift, !hasOption {
                actionHandler?(.goHomeAndCollapseAll)
                return
            }

            // --- Collapse / Expand ---

            // Cmd+Shift+Option+Up → Collapse all children
            if key.keyCode == .keyboardUpArrow, hasCommand, hasShift, hasOption {
                actionHandler?(.collapseAll)
                return
            }

            // Cmd+Shift+Up → Collapse
            if key.keyCode == .keyboardUpArrow, hasCommand, hasShift, !hasOption {
                actionHandler?(.collapse)
                return
            }

            // Cmd+Shift+Option+Down → Expand all children
            if key.keyCode == .keyboardDownArrow, hasCommand, hasShift, hasOption {
                actionHandler?(.expandAll)
                return
            }

            // Cmd+Shift+Down → Expand
            if key.keyCode == .keyboardDownArrow, hasCommand, hasShift, !hasOption {
                actionHandler?(.expand)
                return
            }

            // --- Move / Reorder ---

            // Shift+Option+Up → Move bullet up
            if key.keyCode == .keyboardUpArrow, hasShift, hasOption, !hasCommand {
                actionHandler?(.moveUp)
                return
            }

            // Shift+Option+Down → Move bullet down
            if key.keyCode == .keyboardDownArrow, hasShift, hasOption, !hasCommand {
                actionHandler?(.moveDown)
                return
            }

            // --- Selection ---

            // Shift+Up → Select row up
            if key.keyCode == .keyboardUpArrow, hasShift, !hasCommand, !hasOption {
                actionHandler?(.selectRowUp)
                return
            }

            // Shift+Down → Select row down
            if key.keyCode == .keyboardDownArrow, hasShift, !hasCommand, !hasOption {
                actionHandler?(.selectRowDown)
                return
            }

            // Cmd+A → Progressive select all (matches macOS behavior)
            if key.keyCode == .keyboardA, hasCommand, !hasShift, !hasOption {
                handleProgressiveCmdA()
                return
            }

            // Cmd+C → Copy selected nodes (only with multi-selection)
            if key.keyCode == .keyboardC, hasCommand, !hasShift, !hasOption {
                if hasMultiSelection?() == true {
                    actionHandler?(.copySelected)
                    return
                }
                // Let default handle text copy
            }

            // Cmd+X → Cut selected nodes (only with multi-selection)
            if key.keyCode == .keyboardX, hasCommand, !hasShift, !hasOption {
                if hasMultiSelection?() == true {
                    actionHandler?(.cutSelected)
                    return
                }
                // Let default handle text cut
            }

            // --- Indent / Outdent ---

            // Tab → Indent, Shift+Tab → Outdent
            if key.keyCode == .keyboardTab {
                if hasShift {
                    actionHandler?(.outdent)
                } else {
                    actionHandler?(.indent)
                }
                return
            }

            // Cmd+] → Indent (alt)
            if key.keyCode == .keyboardCloseBracket, hasCommand, !hasShift, !hasOption {
                actionHandler?(.indent)
                return
            }

            // Cmd+[ → Outdent (alt)
            if key.keyCode == .keyboardOpenBracket, hasCommand, !hasShift, !hasOption {
                actionHandler?(.outdent)
                return
            }

            // --- Create / Delete ---

            // Cmd+Enter → Force create sibling below
            if key.keyCode == .keyboardReturnOrEnter, hasCommand, !hasShift, !hasOption {
                actionHandler?(.createSiblingBelow)
                return
            }

            // Cmd+Shift+Backspace → Delete with children / delete selected
            if key.keyCode == .keyboardDeleteOrBackspace, hasCommand, hasShift {
                if hasMultiSelection?() == true {
                    actionHandler?(.deleteSelected)
                } else {
                    actionHandler?(.deleteWithChildren)
                }
                return
            }

            // --- Toggle ---

            // Cmd+Shift+L → Toggle task
            if key.keyCode == .keyboardL, hasCommand, hasShift, !hasOption {
                actionHandler?(.toggleTask)
                return
            }

            // Cmd+Shift+F → Toggle focus mode
            if key.keyCode == .keyboardF, hasCommand, hasShift, !hasOption {
                actionHandler?(.toggleFocusMode)
                return
            }

            // Cmd+F → Toggle search
            if key.keyCode == .keyboardF, hasCommand, !hasShift, !hasOption {
                actionHandler?(.toggleSearch)
                return
            }

            // --- Arrow Navigation at boundaries ---

            // Left arrow at position 0 → navigate to previous bullet (cursor at end)
            if key.keyCode == .keyboardLeftArrow, !hasShift, !hasCommand, !hasOption {
                if let range = selectedTextRange,
                   range.isEmpty,
                   offset(from: beginningOfDocument, to: range.start) == 0 {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onNavigateUp?()
                    return
                }
            }

            // Right arrow at end of text → navigate to next bullet (cursor at start)
            if key.keyCode == .keyboardRightArrow, !hasShift, !hasCommand, !hasOption {
                if let range = selectedTextRange,
                   range.isEmpty,
                   offset(from: range.start, to: endOfDocument) == 0 {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onNavigateDown?()
                    return
                }
            }
        }

        super.pressesBegan(presses, with: event)
    }

    /// Handle progressive Cmd+A (matches macOS behavior)
    /// First press: select all text in bullet. Subsequent presses: expand outline selection.
    private func handleProgressiveCmdA() {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let timeSinceLastPress = currentTime - lastCmdATime
        lastCmdATime = currentTime

        // Reset if more than 1 second since last press
        if timeSinceLastPress > 1.0 {
            cmdASelectionLevel = 0
        }

        cmdASelectionLevel += 1

        if cmdASelectionLevel == 1 {
            // First press: select all text in current text view
            selectAll(nil)
            return
        }

        // Subsequent presses: progressive outline selection
        actionHandler?(.progressiveSelectAll)
    }

    // MARK: - Paste Handling

    override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string else {
            super.paste(sender)
            return
        }

        // Check if pasting just a URL
        if let url = SmartPasteParser.isJustURL(text) {
            onInsertLink?(url)
            return
        }

        // Default paste behavior
        super.paste(sender)
    }
}
#endif
