# Lineout-ly

A minimalist outliner app for macOS with iCloud sync, inspired by WorkFlowy and Roam Research.

## Architecture

### Single-Document Model
- One shared document (`main.md`) stored in iCloud Drive
- All windows/tabs share the same document
- Auto-saves changes with 1-second debounce
- Session state stored separately in `session.json`

### Key Files
| File | Purpose |
|------|---------|
| `OutlineDocument.swift` | Document model with undo/redo support |
| `OutlineNode.swift` | Tree node model (title, body, children, collapse state) |
| `WindowManager.swift` | Shared state across windows, tab tracking, node locking |
| `SessionManager.swift` | Session persistence (zoom, collapse, font size per tab) |
| `iCloudManager.swift` | iCloud file operations |
| `ContentView.swift` | Root view per window, manages per-tab state |
| `OutlineView.swift` | Main outline display with zoom and search |
| `NodeRow.swift` | Single bullet row with text field |
| `OutlineTextField.swift` | Custom NSTextField with keyboard handling |
| `BulletView.swift` | Bullet/chevron indicator |

### Per-Tab State
Each tab maintains independent:
- **Zoom level** - Which node is zoomed into
- **Collapse state** - Which nodes are collapsed (Set<UUID>)
- **Font size** - Text size (9-32pt)
- **Always on top** - Window floats above others

### Session Persistence
Saved to `session.json` on app quit, restored on launch:
- Per-tab state (zoom, collapse, font size, always-on-top)
- Active tab index
- Focused node ID
- Autocomplete enabled setting

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
| Progressive select down | **Shift+↓** |
| Clear selection | **Escape** |
| Delete all selected | **Cmd+Shift+Backspace** (with selection) |

### View
| Action | Shortcut |
|--------|----------|
| Increase font size | **Cmd++** |
| Decrease font size | **Cmd+-** |
| Reset font size | **Cmd+0** |
| Toggle focus mode | **Cmd+Shift+F** |
| Toggle always on top | **Cmd+Option+T** |
| Find/Search | **Cmd+F** |

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
- Zooming into a bullet shows only that subtree
- Breadcrumbs appear at bottom showing path
- Each tab can be zoomed to different nodes
- New tab (**Cmd+T**) opens zoomed to current bullet

### Collapse State
- **Per-tab**: Each tab has independent collapse state
- Collapsing in Tab 1 doesn't affect Tab 2
- Saved and restored with session
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

### Session Restore
- Enabled by default (toggle in View menu)
- Restores all tabs with their zoom, collapse, font size
- Restores which tab was active
- Restores focused node position

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
• Project A                • Project A (header)
  • Task 1                   • Task 1
  • Task 2         →         • Task 2
• Project B                  • Task 3
• Project C
                           Breadcrumb: 🏠 > Project A
```

- **Cmd+.** - Zoom into focused bullet (show only its subtree)
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

- **Cmd+F** - Open search bar
- **Enter** - Jump to next result
- **▲/▼ buttons** - Navigate between results
- **Escape** - Close search
- Matches highlighted in yellow

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
- **Shift+↓** - Progressive select (word → line → next bullet)
- **Escape** - Clear selection
- **Any key** - Cancels selection (except Cmd+Shift+Backspace)

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
| Document | `~/Library/Mobile Documents/iCloud~computer~daydreamlab~Lineout-ly/Documents/Lineout-ly/main.md` |
| Session | `~/Library/Mobile Documents/iCloud~computer~daydreamlab~Lineout-ly/Documents/Lineout-ly/session.json` |
| Local fallback | `~/Documents/Lineout-ly/` (when iCloud unavailable) |

---

## Development Notes

### Adding New Keyboard Shortcuts
1. Add action to `OutlineAction` enum in `OutlineTextField.swift`
2. Handle key in `performKeyEquivalent(with:)` method
3. Implement action in `NodeRow.handleAction(_:)`
4. Add menu item in `Lineout_lyApp.swift` if needed

### Per-Tab State
- State tracked in `WindowManager.tabCollapseStates`, `tabFontSizes`, etc.
- Passed to views via `@Binding`
- Changes synced to WindowManager via `onChange`
- Saved via `SessionManager.saveCurrentSession()`

### Undo/Redo
- `OutlineDocument.undoManager` tracks all structural changes
- Each mutation registers inverse operation
- Menu commands use `FocusedValue` to access undo manager
