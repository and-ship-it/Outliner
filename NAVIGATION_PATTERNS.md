# Lineout Navigation Patterns & Keyboard Behaviors

This document describes all navigation patterns, keyboard shortcuts, and interaction behaviors implemented in Lineout. Use this as a reference when maintaining or porting to other platforms (iOS, Windows, web).

---

## Table of Contents

1. [Arrow Key Navigation](#arrow-key-navigation)
2. [Enter Key Behaviors](#enter-key-behaviors)
3. [Tab Key Behaviors](#tab-key-behaviors)
4. [Modifier Key Combinations](#modifier-key-combinations)
5. [Focus & Cursor Management](#focus--cursor-management)
6. [Multi-line Text Handling](#multi-line-text-handling)
7. [Tree Lines Visual Logic](#tree-lines-visual-logic)
8. [Edge Cases & Special Behaviors](#edge-cases--special-behaviors)

---

## Arrow Key Navigation

### Up Arrow (↑)

| Context | Behavior |
|---------|----------|
| Cursor on first visual line | Navigate to previous bullet (focus moves up) |
| Cursor on wrapped line (not first) | Move cursor up within the text (default OS behavior) |
| Empty bullet | Navigate to previous bullet |
| First bullet in document | No action (stay on current bullet) |
| Cursor at end of single-line text | Navigate to previous bullet |

**Implementation Note:** Must check if cursor is on the "first visual line" of wrapped text. If text wraps to multiple lines, only navigate to previous bullet when cursor is on the topmost visual line.

### Down Arrow (↓)

| Context | Behavior |
|---------|----------|
| Cursor on last visual line, NOT at end of text | Move cursor to end of text |
| Cursor on last visual line, AT end of text | Navigate to next bullet (focus moves down) |
| Cursor on wrapped line (not last) | Move cursor down within the text (default OS behavior) |
| Empty bullet | Navigate to next bullet |
| Last bullet in document, cursor not at end | Move cursor to end of text |
| Last bullet in document, cursor at end | No action (stay at end) |

**Implementation Note:** When on the last bullet and pressing down, first move cursor to end of text. This provides a smooth "end of document" experience.

### Left Arrow (←)

| Context | Behavior |
|---------|----------|
| Default | Standard OS text navigation (move cursor left) |

*No custom handling - uses default OS behavior.*

### Right Arrow (→)

| Context | Behavior |
|---------|----------|
| Default | Standard OS text navigation (move cursor right) |

*No custom handling - uses default OS behavior.*

---

## Enter Key Behaviors

### Plain Enter

| Context | Behavior |
|---------|----------|
| Empty bullet | Create new sibling bullet below |
| Cursor at beginning of text (position 0) | Create new sibling bullet above |
| Cursor at end of text | Create new sibling bullet below (empty) |
| Cursor in middle of text | Split line: current bullet keeps text before cursor, new bullet below gets text after cursor |

**Critical Rule:** Empty bullets should ALWAYS create a new sibling below when Enter is pressed. Never outdent on Enter.

### Command + Enter (⌘↵)

| Context | Behavior |
|---------|----------|
| Any | Always create new sibling bullet below |

---

## Tab Key Behaviors

### Tab

| Context | Behavior |
|---------|----------|
| Any focused bullet | Indent (make child of previous sibling) |
| First bullet at current level | No action (cannot indent without previous sibling) |

### Shift + Tab

| Context | Behavior |
|---------|----------|
| Any focused bullet | Outdent (move to parent's level) |
| Top-level bullet | No action (cannot outdent further) |

**Implementation Note:** Tab/Shift+Tab should work with single press. Must intercept in delegate's `doCommandBy` method to prevent double-press requirement.

---

## Modifier Key Combinations

### Command + Arrow Keys

| Shortcut | Action |
|----------|--------|
| ⌘↑ | Collapse focused bullet |
| ⌘↓ | Expand focused bullet |
| ⌘⌥↑ | Collapse all children of focused bullet |
| ⌘⌥↓ | Expand all children of focused bullet |

### Option + Arrow Keys

| Shortcut | Action |
|----------|--------|
| ⌥↑ | Move bullet up (swap with previous sibling) |
| ⌥↓ | Move bullet down (swap with next sibling) |

### Shift + Arrow Keys

| Shortcut | Action |
|----------|--------|
| ⇧↓ | Progressive selection (see below) |

### Other Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘. | Zoom in (focus on current bullet as root) |
| ⌘, | Zoom out (go to parent level) |
| Escape | Zoom to document root |
| ⌘⇧⌫ | Delete bullet and all its children |

---

## Focus & Cursor Management

### When Focus Moves to a Bullet

1. Text field becomes first responder
2. Cursor is positioned at the **beginning** (position 0)
3. No text is selected

### When Creating New Bullet

1. New bullet is created in the tree structure
2. Focus moves to new bullet (via `DispatchQueue.main.async` to allow SwiftUI view creation)
3. Cursor positioned at beginning

### Focus Change Detection

- Track focus changes via `controlTextDidBeginEditing` and `controlTextDidEndEditing`
- Use `isUpdatingFocus` flag to prevent feedback loops between SwiftUI and AppKit

---

## Multi-line Text Handling

### Text Wrapping

- Text wraps visually but remains logically single-line
- Line break mode: `.byWordWrapping`
- Maximum number of lines: unlimited (0)
- Cell wraps: true
- Cell scrollable: false

### Visual Line Detection

**First Visual Line Check:**
```
1. Get total glyph count and text length
2. If empty (0 glyphs or 0 length) → return true (is first line)
3. Get cursor location
4. If cursor >= textLength, use last glyph index
5. Get line fragment for glyph at cursor position
6. Return true if line fragment starts at glyph 0
```

**Last Visual Line Check:**
```
1. Get total glyph count and text length
2. If empty → return true (is last line)
3. Get cursor location
4. If cursor >= textLength, use last glyph index
5. Get line fragment for cursor position
6. Get line fragment for last glyph in text
7. Return true if both fragments start at same location
```

### Dynamic Height

- `intrinsicContentSize` calculates height based on wrapped text
- Height recalculates when:
  - Text changes
  - Width changes (layout)
  - Font changes

---

## Tree Lines Visual Logic

### When to Draw Vertical Lines

A vertical line is drawn at indent level N if the ancestor at that level has more siblings below it.

**Algorithm:**
```
For each visible node:
  treeLines = []
  current = node

  while current has parent AND parent is not zoom root AND parent is not document root:
    hasSiblingsBelow = current.nextSibling != nil
    treeLines.insert(hasSiblingsBelow, at: 0)
    current = parent

  return treeLines
```

### Line Positioning

| Property | Value |
|----------|-------|
| Width | 1 pixel |
| Color | Gray with 0.25 opacity |
| Horizontal position | `indentWidth + 10` from left of indent column (aligns with bullet center) |
| Vertical extension | `-6` top padding, `-4` bottom padding (to connect rows) |

### Line Appearance Rules

- Lines must be solid (no gaps between rows)
- Lines should align vertically with bullet centers
- Lines extend from parent level down through all children at that level
- Line stops when no more siblings exist at that level

---

## Edge Cases & Special Behaviors

### Empty Bullet Navigation

| Action | Behavior |
|--------|----------|
| Up arrow on empty bullet | Navigate to previous bullet |
| Down arrow on empty bullet | Navigate to next bullet |
| Enter on empty bullet | Create new sibling below (NOT outdent) |

### Cursor at End of Text

| Action | Behavior |
|--------|----------|
| Up arrow when cursor at end of single-line text | Navigate to previous bullet |
| Down arrow when cursor at end, not last bullet | Navigate to next bullet |
| Down arrow when cursor at end, IS last bullet | No action (already at end) |

### Newly Created Bullet

| Action | Behavior |
|--------|----------|
| Up arrow immediately after creating bullet | Navigate to previous bullet (works even before typing) |
| Enter immediately after creating bullet | Create another new sibling below |

### Progressive Selection (Shift+Down)

| Press Count | Behavior |
|-------------|----------|
| First | Select first word on the line |
| Second | Select entire line |
| Third+ | Extend selection to next bullets (handled at document level) |

**Reset Conditions:**
- More than 2 seconds between presses
- Text content changes
- Focus changes

---

## Platform-Specific Implementation Notes

### macOS (Current)

- Uses `NSTextField` with `NSViewRepresentable`
- Keyboard handling via `performKeyEquivalent` (for modifier keys) and `doCommandBy` delegate method (for plain keys)
- Text wrapping via cell configuration
- Dynamic height via `intrinsicContentSize` override

### iOS (Future)

- Use `UITextField` or `UITextView` with `UIViewRepresentable`
- Keyboard handling via `UIKeyCommand` for shortcuts
- Consider using `inputAccessoryView` for toolbar shortcuts
- Text wrapping is native to `UITextView`

### Windows (Future)

- Use native Win32 edit controls or WPF `TextBox`
- Keyboard handling via `WM_KEYDOWN` messages or WPF key bindings
- Implement IME support for international input
- Consider UWP for modern Windows apps

### Web (Future)

- Use `contenteditable` div or `<textarea>`
- Keyboard handling via `keydown` event listeners
- Check `event.key` and modifier flags (`event.ctrlKey`, `event.metaKey`, etc.)
- Use CSS for text wrapping and dynamic height

---

## Testing Checklist

When modifying navigation code, verify these scenarios:

### Arrow Key Tests
- [ ] Up arrow on first bullet does nothing
- [ ] Up arrow on middle bullet moves to previous
- [ ] Up arrow on empty bullet moves to previous
- [ ] Up arrow at end of single-line text moves to previous
- [ ] Up arrow on wrapped text (not first line) moves cursor up within text
- [ ] Down arrow on last bullet moves cursor to end (if not already there)
- [ ] Down arrow at end of last bullet does nothing
- [ ] Down arrow on empty bullet moves to next
- [ ] Down arrow on wrapped text (not last line) moves cursor down within text

### Enter Key Tests
- [ ] Enter on empty bullet creates sibling below
- [ ] Enter at beginning of text creates sibling above
- [ ] Enter at end of text creates empty sibling below
- [ ] Enter in middle of text splits line correctly
- [ ] Multiple Enter presses on empty bullets create multiple siblings

### Tab Key Tests
- [ ] Tab indents (single press)
- [ ] Shift+Tab outdents (single press)
- [ ] Tab on first sibling does nothing
- [ ] Shift+Tab on top-level does nothing

### Focus Tests
- [ ] New bullet receives focus
- [ ] Cursor at beginning after focus
- [ ] Can immediately type after focus
- [ ] Can immediately navigate after focus (without typing first)

---

## Version History

| Date | Changes |
|------|---------|
| 2026-01-24 | Initial documentation created |
| 2026-01-24 | Added empty bullet handling |
| 2026-01-24 | Fixed cursor-at-end navigation |
| 2026-01-24 | Fixed down arrow on last bullet behavior |

---

## Related Files

- `OutlineTextField.swift` - Keyboard handling and text field logic
- `OutlineDocument.swift` - Document operations (create, delete, move nodes)
- `NodeRow.swift` - Visual row rendering including tree lines
- `OutlineView.swift` - Main view and tree line calculation
- `OutlineNode.swift` - Node data model and tree structure
