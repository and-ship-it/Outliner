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
