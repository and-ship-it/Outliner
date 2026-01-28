# Lineout-ly

A fast, keyboard-first outliner for organizing thoughts. macOS and iOS with iCloud sync.

---

## Product Vision

### What This Is

**A thinking space, not a storage system.**

Lineout-ly is for people who already have a "second brain" (Obsidian, Notion, Apple Notes) and manage tasks in Reminders/Calendar. They need a **fast scratchpad** where they can:
- Quickly organize thoughts
- Plan and adjust on the fly
- Restructure without fear
- Navigate with keyboard OR touch

### Core Philosophy

| Principle | Meaning |
|-----------|---------|
| **Speed of reorganization** | Not typing speed - restructuring speed. Hands stay on keyboard, thoughts flow into structure. |
| **Not scared to disassemble** | Restructuring feels safe and instant. Tear it apart, rebuild it, undo if wrong. |
| **Thinking tool, not archive** | Thoughts form here, then graduate to permanent home. Weekly reset keeps it fresh. |
| **Dual-mode excellence** | Keyboard-first on Mac/iPad. Touch-first excellence on iOS. Same mental model. |

### What Makes It Different

| Other Outliners | Lineout-ly |
|-----------------|------------|
| Accumulate forever | Weekly reset |
| "Where does this go?" | Everything starts here |
| Mouse-heavy reorganization | Keyboard-driven |
| Touch is afterthought | Touch is first-class |
| Rich text complexity | Markdown simplicity |

### Target User

Someone who:
- Has iPad with Magic Keyboard and wants desktop-class navigation
- Uses iPhone and wants Craft.do-level touch fluidity
- Already has Obsidian/Notion for long-term storage
- Needs a place to think, not a place to file

---

## Implemented Features

### Weekly Documents (DONE)
- Files named by week: `2025-Jan-W05.md`
- New week automatically creates new file
- Previous weeks stay in folder as archive
- Week start day setting in Edit menu (Sunday/Monday/Saturday)

### Fast Launch with Collapsed View (DONE)
- Opens directly to home/root view (no auto-zoom)
- All nodes with children are collapsed on launch
- Fast loading with minimal visible nodes
- Preserves document structure for quick navigation

### Simplified Navigation (DONE)
- Removed detailed breadcrumb trail
- Shows only "Home" button when zoomed
- Week indicator shown at bottom right
- Window title shows week name at root

### iOS Touch Gestures (DONE)
- Swipe right to indent
- Swipe left to outdent
- Long-press to enter selection mode
- Drag and drop to reorder
- Two-finger tap to enter multi-selection mode
- Double-tap bullet to zoom in
- Swipe from left edge to zoom out (like iOS back gesture)

### Smart Link Pasting (DONE)
- Paste URL → automatically fetches page title
- Creates short title (max 5 words)
- Displays as underlined grey clickable text
- Click to open link in browser
- Markdown format: `[Title](url)`

### Share Extension (DONE)
- Share content to app from any iOS app
- Creates "Shared" node at root level if not exists
- Adds short description bullet under "Shared"
- Nested content: links become smart links, text becomes bullets
- Supports URLs (with title fetching) and text (list parsing)

### Settings with iCloud Sync (DONE)
- Three-dot settings button on iOS (like Reminders)
- Settings sync across devices via iCloud
- Font size, focus mode, autocomplete toggle, week start day

---

## Future Roadmap

### Planned Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Calendar integration** | Drag bullet to day → calendar event | Medium |
| **Reminders integration** | Drag bullet → reminder | Medium |
| **Export to Obsidian** | Weekly archive syncs to vault | Medium |

---

## Architecture

### Single-Document Model
- One shared document (`main.md`) stored in iCloud Drive
- All windows/tabs share the same document
- Auto-saves changes with 1-second debounce

### Key Files
| File | Purpose |
|------|---------|
| `OutlineDocument.swift` | Document model with undo/redo support |
| `OutlineNode.swift` | Tree node model (title, body, children, collapse state) |
| `WindowManager.swift` | Shared state across windows, tab tracking, node locking |
| `iCloudManager.swift` | iCloud file operations |
| `ContentView.swift` | Root view per window, manages per-tab state |
| `OutlineView.swift` | Main outline display with zoom and search |
| `NodeRow.swift` | Single bullet row with text field |
| `OutlineTextField.swift` | Custom NSTextField/UITextField with keyboard handling |
| `BulletView.swift` | Bullet/chevron indicator |
| `LinkParser.swift` | URL detection, title fetching, markdown link formatting |
| `SmartPasteParser.swift` | Parses pasted content into outline structure |
| `SettingsManager.swift` | App settings with iCloud sync |
| `ShareExtension/ShareViewController.swift` | iOS Share Extension handler |

### Per-Tab State
Each tab maintains independent:
- **Zoom level** - Which node is zoomed into
- **Collapse state** - Which nodes are collapsed (Set<UUID>)
- **Font size** - Text size (9-32pt)
- **Always on top** - Window floats above others

### Fast Launch with Collapsed View
Every app launch optimizes for fast loading:
- Opens directly to home/root view (no auto-zoom)
- All nodes with children are collapsed on launch
- Minimizes visible nodes for quick initial render
- User can expand/navigate to any section as needed

---

## Keyboard Shortcuts

### Navigation
| Action | Shortcut |
|--------|----------|
| Navigate to previous bullet | **↑** (when at first line or empty) |
| Navigate to next bullet | **↓** (when at last line or empty) |
| Move cursor to start of text | **Cmd+↑** |
| Move cursor to end of text | **Cmd+↓** |

### Bullet Operations
| Action | Shortcut |
|--------|----------|
| New bullet below | **Enter** (at end of text) |
| New bullet above | **Enter** (at start of text) |
| Split line | **Enter** (in middle of text) |
| New bullet (force below) | **Cmd+Enter** |
| Delete bullet with children | **Cmd+Shift+Backspace** |

### Moving Bullets
| Action | Shortcut |
|--------|----------|
| Move bullet up | **Shift+Option+↑** |
| Move bullet down | **Shift+Option+↓** |
| Indent (make child of above) | **Tab** or **Shift+Option+→** |
| Outdent (move to parent level) | **Shift+Tab** or **Shift+Option+←** |

### Collapse/Expand
| Action | Shortcut |
|--------|----------|
| Collapse focused bullet | **Cmd+Shift+↑** |
| Expand focused bullet | **Cmd+Shift+↓** |
| Collapse all children | **Cmd+Shift+Option+↑** |
| Expand all children | **Cmd+Shift+Option+↓** |

### Zoom (Focus on subtree)
| Action | Shortcut |
|--------|----------|
| Zoom into focused bullet | **Cmd+.** |
| Zoom out one level | **Cmd+,** |
| Zoom to root (home) | **Escape** |
| Go home and collapse all | **Cmd+Shift+H** |

### Selection
| Action | Shortcut |
|--------|----------|
| Select all text in bullet | **Cmd+A** (first press) |
| Expand selection to siblings | **Cmd+A** (subsequent presses) |
| Select row below | **Shift+↓** |
| Select row above | **Shift+↑** |
| Clear selection | **Escape** |
| Delete all selected | **Cmd+Shift+Backspace** (with selection) |
| Delete empty bullet (merge up) | **Backspace** (when bullet is empty) |

### View
| Action | Shortcut |
|--------|----------|
| Increase font size | **Cmd++** |
| Decrease font size | **Cmd+-** |
| Reset font size | **Cmd+0** |
| Toggle focus mode | **Cmd+Shift+F** |
| Toggle always on top | **Cmd+Option+T** |
| Toggle search | **Cmd+F** (press again to close) |

### Tabs & Windows
| Action | Shortcut |
|--------|----------|
| New tab (zoomed to focused) | **Cmd+T** |
| New window | **Cmd+N** |
| Switch to tab 1-9 | **Cmd+1** through **Cmd+9** |

### Tasks
| Action | Shortcut |
|--------|----------|
| Toggle task checkbox | **Cmd+Shift+L** |

### Edit
| Action | Shortcut |
|--------|----------|
| Undo | **Cmd+Z** |
| Redo | **Cmd+Shift+Z** |

### Other
| Action | Shortcut |
|--------|----------|
| Show in Finder | **Cmd+Shift+R** |
| Accept autocomplete suggestion | **→** (when at end of text) |
| Clear autocomplete suggestion | **Escape** |

---

## UI/UX Behaviors

### Text Editing
- **Wrapping**: Text wraps visually but is logically single-line
- **Cursor positioning**: Cursor starts at beginning when focusing a bullet
- **Multi-line navigation**: ↑/↓ move within wrapped text; only navigate to other bullets at first/last visual line

### Autocomplete
- Shows ghost text suggestions after 2+ characters
- Based on system spell checker completions
- Accept with **→** arrow key
- Dismiss with **Escape**
- Can be disabled in View menu

### Focus Mode
- Dims all bullets except the currently focused one
- Helps concentrate on one thought at a time
- Toggle with **Cmd+Shift+F**

### Zoom
- Zooming into a bullet shows that bullet as editable header at the top
- Children appear indented below the header
- Empty child auto-created if bullet has no children (cursor focused there)
- Tab/window title shows the zoomed bullet's name
- Each tab can be zoomed to different nodes
- New tab (**Cmd+T**) opens zoomed to current bullet

### Collapse State
- **Per-tab**: Each tab has independent collapse state
- Collapsing in Tab 1 doesn't affect Tab 2
- Chevron indicates collapsed (→) or expanded (↓)

### Multi-Selection
- **Cmd+A** progressively expands selection:
  1. First press: Select all text in current bullet
  2. Second press: Select current bullet
  3. Third press: Select siblings
  4. Further presses: Expand to parent level
- Selected bullets highlighted with accent color
- **Cmd+Shift+Backspace** deletes all selected
- Any other key cancels selection

### Node Locking
- When editing in one tab, node is locked in other tabs
- Lock indicator (🔒) shown on locked nodes
- Prevents concurrent editing conflicts

---

## Navigation Patterns

### Cursor Navigation (Within a Bullet)
```
Single-line bullet:
┌─────────────────────────────────┐
│ • This is a single line         │
└─────────────────────────────────┘
  ↑                             ↑
  Cmd+↑ (start)         Cmd+↓ (end)

Multi-line wrapped bullet:
┌─────────────────────────────────┐
│ • This is a longer bullet that  │  ← Line 1: ↑ navigates to prev bullet
│   wraps to multiple visual      │  ← Line 2: ↑/↓ move within text
│   lines in the editor           │  ← Line 3: ↓ navigates to next bullet
└─────────────────────────────────┘
```

- **←/→** - Move cursor left/right within text
- **↑/↓** - Move cursor up/down within wrapped text
- **Cmd+←** - Jump to start of line
- **Cmd+→** - Jump to end of line
- **Cmd+↑** - Jump to start of bullet text
- **Cmd+↓** - Jump to end of bullet text
- **Option+←/→** - Jump by word

### Bullet Navigation (Between Bullets)
```
┌─────────────────────────────────┐
│ • Bullet A                      │  ← ↑ from B goes here
├─────────────────────────────────┤
│ • Bullet B (focused)            │  ← Current focus
├─────────────────────────────────┤
│ • Bullet C                      │  ← ↓ from B goes here
└─────────────────────────────────┘
```

- **↑** at first visual line → Navigate to previous visible bullet
- **↓** at last visual line → Navigate to next visible bullet
- **↑/↓** on empty bullet → Always navigate to adjacent bullet

### Hierarchy Navigation
```
• Parent
  • Child 1        ← Tab from here indents under "Parent"
  • Child 2
    • Grandchild   ← Shift+Tab outdents to "Child" level
  • Child 3
```

- **Tab** - Indent: Make current bullet a child of the bullet above
- **Shift+Tab** - Outdent: Move current bullet up one level in hierarchy
- **Shift+Option+→** - Alternative indent
- **Shift+Option+←** - Alternative outdent

### Reordering (Moving Bullets)
```
Before:                    After Shift+Option+↑:
• Bullet A                 • Bullet B (moved up)
• Bullet B (focused)  →    • Bullet A
• Bullet C                 • Bullet C
```

- **Shift+Option+↑** - Move bullet up (swap with previous sibling)
- **Shift+Option+↓** - Move bullet down (swap with next sibling)
- Maintains hierarchy (children move with parent)
- Cannot move past parent boundaries

### Collapse/Expand Navigation
```
Expanded:                  Collapsed:
• Parent                   • Parent ▸ (chevron right)
  • Child 1                  (children hidden)
  • Child 2
  • Child 3
```

- **Cmd+Shift+↑** - Collapse focused bullet (hide children)
- **Cmd+Shift+↓** - Expand focused bullet (show children)
- **Click chevron** - Toggle collapse state
- Collapsed bullets show **▸**, expanded show **▾**

### Zoom Navigation
```
Home view:                 Zoomed into "Project A":
• Project A                • Project A (editable header)
  • Task 1                   • Task 1 (cursor here)
  • Task 2         →         • Task 2
• Project B                  • Task 3
• Project C
                           Tab title: "Project A"
```

- **Cmd+.** - Zoom into focused bullet (shows bullet as header, focuses first child)
- **Cmd+,** - Zoom out one level (to parent)
- **Escape** - Zoom to root (go home)
- **Cmd+Shift+H** - Go home AND collapse all bullets
- **Breadcrumb clicks** - Jump to any ancestor level

### Tab Navigation
```
┌─────┬─────────┬─────────┐
│ Tab1│  Tab2   │  Tab3   │  ← Cmd+1/2/3 to switch
│Home │Project A│Project B│  ← Each has own zoom/collapse
└─────┴─────────┴─────────┘
```

- **Cmd+T** - New tab zoomed to current bullet
- **Cmd+1-9** - Switch to tab by number
- **Cmd+W** - Close current tab
- Each tab has independent zoom and collapse state

### Search Navigation
```
┌─────────────────────────────────┐
│ 🔍 search query    3 found  ▲▼  │  ← Cmd+F opens
├─────────────────────────────────┤
│ • Result 1 with [highlight]     │
│ • Result 2 with [highlight]     │
│ • Result 3 with [highlight]     │
└─────────────────────────────────┘
```

- **Cmd+F** - Toggle search bar (open/close)
- **Enter** - Jump to next result (expands collapsed ancestors)
- **▲/▼ buttons** - Navigate between results
- **Escape** - Close search
- Matches highlighted in yellow
- Search finds nodes inside collapsed parents and reveals them

### Selection Navigation
```
Progressive Cmd+A selection:

Press 1: Select text        Press 2: Select bullet
┌─────────────────────┐     ┌─────────────────────┐
│ • [Selected text]   │     │ ▓ Selected bullet ▓ │
│ • Other bullet      │     │ • Other bullet      │
└─────────────────────┘     └─────────────────────┘

Press 3: Select siblings    Press 4: Expand to parent
┌─────────────────────┐     ┌─────────────────────┐
│ ▓ Selected bullet ▓ │     │ ▓ Parent selected ▓ │
│ ▓ Sibling selected▓ │     │ ▓  Child selected ▓ │
│ ▓ Sibling selected▓ │     │ ▓  Child selected ▓ │
└─────────────────────┘     └─────────────────────┘
```

- **Cmd+A** - Progressive selection (text → bullet → siblings → parent)
- **Shift+↓** - Select current row + next row
- **Shift+↑** - Select current row + previous row
- **Escape** - Clear selection
- **Any key** - Cancels selection (except Cmd+Shift+Backspace, Shift+↑/↓)

### Navigation Flow Summary
```
                    Cmd+. (zoom in)
                         ↓
    ←── Cmd+, (zoom out) ●  Escape (home)
                         ↑

    ↑ (prev bullet)      ●      ↓ (next bullet)
                    (current)

    Shift+Opt+↑          ●      Shift+Opt+↓
    (move up)       (focused)   (move down)

    Shift+Tab            ●      Tab
    (outdent)       (hierarchy) (indent)

    Cmd+Shift+↑          ●      Cmd+Shift+↓
    (collapse)      (visibility)(expand)
```

---

## File Locations

| File | Location |
|------|----------|
| Weekly document | `~/Library/Mobile Documents/iCloud~computer~daydreamlab~Lineout-ly/Documents/Lineout-ly/2025-Jan-W05.md` |
| Local fallback | `~/Documents/Lineout-ly/` (when iCloud unavailable) |

### Weekly File Naming
- Format: `YYYY-MMM-WXX.md` (e.g., `2025-Jan-W05.md`)
- Week number is ISO week of year
- Month is from the first day of that week
- Week start day configurable: Sunday, Monday, or Saturday

---

## Development Notes

### Build Verification Rule
**After every code change, build the project before reporting back to the user.** Run `xcodebuild -scheme Lineout-ly -destination 'platform=macOS' build` and verify `BUILD SUCCEEDED`. If there are build errors, fix them before presenting the result. Do not hand off broken code.

### Cross-Platform Rule
**All changes must be implemented for both macOS and iOS unless explicitly stated otherwise.** Many views have platform-specific code paths (e.g., `#if os(iOS)` / `#if os(macOS)`, separate `NSViewRepresentable` and `UIViewRepresentable` implementations). When making a change, always check and update both platform paths. If a change cannot be implemented the same way on both platforms, ask the user before proceeding.

### Adding New Keyboard Shortcuts
1. Add action to `OutlineAction` enum in `OutlineTextField.swift`
2. Handle key in `performKeyEquivalent(with:)` method
3. Implement action in `NodeRow.handleAction(_:)`
4. Add menu item in `Lineout_lyApp.swift` if needed

### Per-Tab State
- State tracked in `WindowManager.tabCollapseStates`, `tabFontSizes`, etc.
- Passed to views via `@Binding`
- Changes synced to WindowManager via `onChange`

### Undo/Redo
- `OutlineDocument.undoManager` tracks all structural changes
- Each mutation registers inverse operation
- Menu commands use `FocusedValue` to access undo manager

---

## Technical Decisions & Bug Fixes

### Focus Management (Critical)

**Problem**: Mouse clicks and keyboard navigation had separate focus paths, causing desync between visual focus and document state.

**Solution**: Unified focus through `tryFocusNode()` in NodeRow.swift
- `onMouseDownFocus` callback fires immediately on mouseDown (not after)
- `controlTextDidBeginEditing` also calls `tryFocusNode()` for keyboard focus
- Both paths converge to `document.setFocus(node)`

**Key files**:
- `OutlineTextField.swift:170-200` - onMouseDownFocus handling
- `NodeRow.swift:179-202` - tryFocusNode() implementation
- `OutlineDocument.swift:135-143` - setFocus()

### Backspace on Empty Bullet (Merge Up)

**Behavior**: Pressing backspace on empty bullet deletes it and moves focus to previous bullet with cursor at END of line.

**Implementation**:
- `deleteEmpty` action in OutlineAction enum
- `deleteFocused()` in OutlineDocument finds previous visible node
- `cursorAtEndOnNextFocus` flag tells OutlineTextField to position cursor at end
- `focusVersion` counter forces SwiftUI to re-render even when focusedNodeId doesn't change

**Key code**:
```swift
// OutlineDocument.swift
var cursorAtEndOnNextFocus: Bool = false
var focusVersion: Int = 0

func deleteFocused() {
    // ... find previous node ...
    cursorAtEndOnNextFocus = true
    focusVersion += 1
    focusedNodeId = previousNode.id
}
```

### Shift+Up/Down Row Selection

**Behavior**: Holding Shift+Up/Down selects whole rows progressively.

**Problem**: Selection was being cleared on every keystroke because Shift+Up/Down wasn't in the exception list.

**Solution**: Added `isShiftUp` and `isShiftDown` to the selection-clearing exception list in `performKeyEquivalent`:
```swift
let isShiftUp = event.keyCode == 126 && hasShift && !hasCommand && !hasOption
let isShiftDown = event.keyCode == 125 && hasShift && !hasCommand && !hasOption

if !isCmdShiftBackspace && !isEscape && !isCmdA && !isShiftUp && !isShiftDown {
    actionHandler?(.clearSelection)
}
```

### Collapse Zoomed Node

**Problem**: When zoomed into a node, collapsing the top (zoomed) node didn't hide its children.

**Cause**: `nodesWithDepth` in OutlineView.swift always showed children of zoomed node regardless of collapse state.

**Solution**: Check if zoomed node is in `collapsedNodeIds` before showing children:
```swift
if let zoomed = zoomedNode {
    result.append((node: zoomed, depth: 0, treeLines: []))
    if !collapsedNodeIds.contains(zoomed.id) {  // Added this check
        let children = flattenedVisible(from: zoomed)
        // ...
    }
}
```

### Search Navigation with Per-Tab Collapse

**Problem**: Search found nodes inside collapsed parents, but navigating to them didn't reveal them.

**Cause**: Original `navigateToSearchResult` expanded nodes using node's own `isCollapsed` property, but collapse state is now per-tab in `collapsedNodeIds`.

**Solution**: Created local `navigateToSearchResult` in OutlineView.swift that removes ancestors from `collapsedNodeIds`:
```swift
private func navigateToSearchResult(_ node: OutlineNode) {
    var current = node.parent
    while let parent = current {
        collapsedNodeIds.remove(parent.id)
        current = parent.parent
    }
    document.focusedNodeId = node.id
}
```

### Cmd+F Toggle Search

**Problem**: Cmd+F only opened search, didn't close it.

**Solution**: Changed menu command from `= true` to `.toggle()`:
```swift
Button("Find...") {
    searchingBinding?.wrappedValue.toggle()
}
```

---

## Debug Logging

Extensive debug logging is intentionally left in place for development. Key debug points:

| Location | What it logs |
|----------|--------------|
| `tryFocusNode()` | Focus acquisition, lock status |
| `setFocus()` | Document focus changes |
| `onFocusChange()` | NSTextField focus events |
| `controlTextDidBeginEditing` | Text field activation |
| `controlTextDidEndEditing` | Text field deactivation |
| `performKeyEquivalent` | Keyboard shortcut detection |
| `collapse/expand` | Collapse state changes |

To find debug output: `[DEBUG]` prefix in console.

---

## Code Architecture

### Data Flow

```
User Input (keyboard/mouse)
    ↓
OutlineTextField (NSViewRepresentable)
    ↓
OutlineAction enum (e.g., .indent, .moveUp)
    ↓
NodeRow.handleAction(_:)
    ↓
OutlineDocument methods (e.g., indent(), moveUp())
    ↓
structureDidChange() → structureVersion += 1
    ↓
SwiftUI re-renders
    ↓
iCloudManager.scheduleAutoSave()
```

### Per-Tab State Flow

```
ContentView (@State)
    ↓
Bindings passed to OutlineView
    ↓
Bindings passed to NodeRow
    ↓
Changes flow back up via @Binding
    ↓
WindowManager stores for tab tracking
```

### Key Bindings Pattern

All keyboard shortcuts flow through `performKeyEquivalent(with:)` in OutlineTextField.swift:
1. Check modifiers (Cmd, Shift, Option, Control)
2. Check keyCode
3. Call `actionHandler?(.someAction)`
4. Return `true` to consume the event

### Node Locking Pattern

Prevents concurrent editing across windows/tabs:
1. `WindowManager.tryLock(nodeId:for:)` attempts to acquire
2. If locked by another window, returns false
3. If unlocked or owned by same window, returns true and stores lock
4. `releaseLock(nodeId:for:)` releases when focus moves away

---

## File Structure

```
Lineout-ly/
├── Lineout_lyApp.swift      # App entry, menu commands
├── ContentView.swift        # Root view, tab management
├── OutlineView.swift        # Main outline display
├── NodeRow.swift            # Single bullet row
├── OutlineTextField.swift   # Custom NSTextField (keyboard handling)
├── BulletView.swift         # Bullet/chevron indicator
├── OutlineDocument.swift    # Document model
├── OutlineNode.swift        # Tree node model
├── WindowManager.swift      # Cross-window state, optimistic UI loading
├── iCloudManager.swift      # iCloud file operations
└── TrashBin.swift           # Deleted nodes storage
```

---

## Common Tasks

### Add a New Keyboard Shortcut

1. Add case to `OutlineAction` enum in `OutlineTextField.swift`
2. Add key detection in `performKeyEquivalent(with:)`
3. Add handler in `NodeRow.handleAction(_:)`
4. (Optional) Add menu item in `Lineout_lyApp.swift`

### Add a New Per-Tab Setting

1. Add `@State` in `ContentView.swift`
2. Pass as `@Binding` through `OutlineView` → `NodeRow`
3. Add storage in `WindowManager.swift`

### Debug Focus Issues

1. Look for `[DEBUG]` lines in console
2. Check `tryFocusNode` - is it being called?
3. Check `setFocus` - is document state updating?
4. Check `updateNSView` - is SwiftUI triggering re-render?
5. Check `focusVersion` - might need to increment to force refresh

### Debug Collapse/Visibility Issues

1. Check `collapsedNodeIds` - is the node in the set?
2. Check `nodesWithDepth` - is the node being included?
3. Check `flattenedVisible` - is it respecting collapsed state?
4. Remember: collapse state is PER-TAB, not on the node itself
