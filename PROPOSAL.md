# Lineout.ly — Product Proposal

## Vision

A **thinking environment** for people who work with ideas. Not a document editor — a place to prioritize, focus, and navigate complexity throughout your day.

**The core loop:**
```
Capture → Structure → Focus → Complete → Step Back → Repeat
```

---

## The Problem

Your brain holds one idea at a time. But your day has hundreds.

- Tasks pile up, priorities blur
- You start something, get pulled into details, lose the big picture
- Context switching destroys focus
- Flat lists don't match how ideas actually relate

## The Solution: Structured Depth

**Zoom in** to focus on one thing. Work on it. **Zoom out** to see where it fits. Move things around as priorities shift. Your entire mental workspace in one infinite, collapsible structure.

---

## Core Philosophy

**"Depth without drowning."**

- **One thing at a time** — Zoom eliminates everything else
- **Structure matches thought** — Ideas nest naturally
- **Fluid priority** — Move anything, anytime, instantly
- **Trust the system** — Capture fast, organize later

---

## A Day in Lineout.ly

### Morning: Survey
```
My Life                          ← Root level: everything
├── Today                        ← Zoom here to start
│   ├── Ship login feature
│   ├── Call with Alex
│   └── Review PRs
├── This Week
│   ├── Q1 planning doc
│   └── Hire designer
├── Projects
│   ├── App redesign
│   └── API migration
└── Someday
    └── Learn Rust
```
You see your whole world. You know what matters today.

### Mid-morning: Focus
```
Ship login feature               ← ⌘+. to zoom in
├── Fix token refresh bug        ← Working here
│   ├── Check expiry logic
│   └── Test edge cases
├── Add "remember me"
└── Write tests
```
Everything else disappears. Just this task and its parts.

### Noon: Restructure
A new priority appears. Quick capture at root, then move:
```
⌘+Shift+O  → Summon app
Enter      → "Urgent: server down"
⌘+↑ ⌘+↑    → Move to top of Today
⌘+.        → Zoom in, start working
```

### Afternoon: Step Back
```
⌘+,        → Zoom out one level
⌘+, again  → Back to root
```
See the whole day. Reprioritize. Check off completed items.

### Evening: Clean Up
Move unfinished items to tomorrow. Archive completed work. Done.

---

## Novel Concept: Title + Body

Every node has two parts:

```
┌─────────────────────────────────────────────────┐
│ • Ship login feature                    [▾] [↗] │  ← Title (always visible)
├─────────────────────────────────────────────────┤
│ We need to fix the token refresh because users  │  ← Body (expandable prose)
│ are getting logged out after 30 minutes. The    │
│ current implementation doesn't handle refresh   │
│ tokens correctly.                               │
│                                                 │
│ Also need to consider UX of "remember me" —     │
│ should it be checked by default?                │
├─────────────────────────────────────────────────┤
│     • Fix token refresh                         │  ← Children (sub-items)
│     • Add "remember me" checkbox                │
│     • Write integration tests                   │
└─────────────────────────────────────────────────┘
```

### Three View States

**1. Collapsed** — Just titles (scanning mode)
```
• Ship login feature
• Call with Alex
• Review PRs
```

**2. Expanded** — Title + body visible (context mode)
```
• Ship login feature
  We need to fix the token refresh because users
  are getting logged out after 30 minutes...
    • Fix token refresh
    • Add "remember me"
```

**3. Zoomed** — Full focus (writing mode)
```
Ship login feature
─────────────────────────────────────────

We need to fix the token refresh because users
are getting logged out after 30 minutes. The
current implementation doesn't handle refresh
tokens correctly.

Also need to consider UX of "remember me" —
should it be checked by default?

─────────────────────────────────────────
• Fix token refresh
• Add "remember me" checkbox
• Write integration tests
```

### Why This Works

| Mode | Use Case | You See |
|------|----------|---------|
| Collapsed | Prioritize, scan, reorder | Titles only |
| Expanded | Quick context check | Title + body preview |
| Zoomed | Deep work, writing | Full prose + children |

**The same node serves multiple purposes:**
- As a **task**: "Ship login feature"
- As a **document**: The body contains your thinking, notes, decisions
- As a **container**: Children break it into actionable pieces

### Keyboard Flow

```
↑/↓             Navigate between nodes
←               Collapse (hide body + children)
→               Expand (show body + children)
⌘+.             Zoom in (full focus, write prose)
⌘+,             Zoom out (back to context)
Enter           New sibling
⌘+Enter         Start writing body (or new child)
```

### Markdown Format

```markdown
- Ship login feature

  We need to fix the token refresh because users
  are getting logged out after 30 minutes. The
  current implementation doesn't handle refresh
  tokens correctly.

  Also need to consider UX of "remember me" —
  should it be checked by default?

    - Fix token refresh
    - Add "remember me" checkbox
    - Write integration tests
```

**Rules:**
- Title: Line starting with `- `
- Body: Indented paragraph(s) after title, before children
- Children: Deeper indented `- ` lines
- Blank line separates body from children

---

## Key Interactions

### Quick Capture (Anywhere)
```
⌘+Shift+O          → Summon app (global)
Start typing       → New node at current level
Enter              → Confirm, stay in place
⌘+.                → Zoom into it and expand
```

### Focus Session
```
⌘+.                → Zoom into node (world shrinks)
Work...            → Edit, create children, restructure
⌘+,                → Step back out (world expands)
Escape             → Jump to root (see everything)
```

### Rapid Restructure
```
⌘+↑ / ⌘+↓          → Reorder (priority sort)
Tab / Shift+Tab    → Nest / unnest (change scope)
⌘+X, navigate, ⌘+V → Move anywhere
```

---

## Architecture

### Single Document, Infinite Space

**One outline = One file = One mental space**

```
┌─────────────────────────────────────────┐
│      User Experience: Infinite canvas   │
├─────────────────────────────────────────┤
│      Storage: Single .md file (~300KB)  │
├─────────────────────────────────────────┤
│   Memory: Full tree loaded (instant)    │
├─────────────────────────────────────────┤
│   Rendering: LazyVStack (30 nodes max)  │
└─────────────────────────────────────────┘
```

**Why single document works at scale:**

| Nodes | File Size | Parse Time | Memory |
|-------|-----------|------------|--------|
| 1,000 | ~30 KB | <10ms | ~2 MB |
| 10,000 | ~300 KB | <50ms | ~20 MB |
| 50,000 | ~1.5 MB | <200ms | ~100 MB |

- **Rendering is the bottleneck, not data** — SwiftUI's `LazyVStack` only renders visible nodes (~30 at a time)
- **Collapsed branches are free** — Children of collapsed nodes aren't rendered
- **Users self-organize** — Large outlines naturally have collapsed sections

### Data Model: The Outline Node

```
OutlineNode
├── id: UUID
├── title: String                // The bullet line (always visible)
├── body: String?                // Optional prose (visible when expanded/zoomed)
├── children: [OutlineNode]      // Unlimited nesting
├── isCollapsed: Bool            // Controls visibility of body + children
├── createdAt: Date
├── modifiedAt: Date
└── parent: OutlineNode?         // Weak reference for navigation
```

**Title vs Body:**
- `title`: Short, scannable — what you see when collapsed
- `body`: Long-form thinking — notes, context, prose
- Both are optional, but title defaults to empty string
- A "task" might have no body, just title + children
- A "note" might be all body, no children

### Document Structure

Single markdown file with indentation-based hierarchy:

```markdown
# Document Title

- First thought
    - Nested idea
        - Deeper still
            - No limits
    - Another branch
- Second thought
    - Sub-item
```

**Why Markdown?**
- Universal format — opens in any text editor
- Human-readable without parsing
- Git-friendly for version control
- Future-proof

### File Storage

```
~/Library/Mobile Documents/iCloud~com~lineoutly~app/Documents/
└── My Outline.md      # One file, infinite depth
```

- **Location**: iCloud Drive container
- **Format**: Single `.md` file
- **Sync**: Automatic via iCloud Drive (no CloudKit complexity)
- **Access**: Visible in Files app, openable by any markdown editor

Future: Optional "workspaces" for users who outgrow a single outline (Phase 6+)

---

## Keyboard-First Design

### Navigation (No Modifier)

| Key | Action |
|-----|--------|
| `↑` / `↓` | Move between siblings |
| `←` | Collapse node / Go to parent |
| `→` | Expand node / Enter first child |
| `Tab` | Indent (make child of above) |
| `Shift+Tab` | Outdent (move to parent level) |
| `Enter` | New sibling below |
| `Shift+Enter` | New sibling above |

### Editing

| Key | Action |
|-----|--------|
| `⌘+Enter` | New child |
| `⌘+Backspace` | Delete node (with confirmation if has children) |
| `Escape` | Exit edit mode / Clear selection |

### Structure Manipulation

| Key | Action |
|-----|--------|
| `⌘+↑` | Move node up |
| `⌘+↓` | Move node down |
| `⌘+←` | Collapse all children |
| `⌘+→` | Expand all children |
| `⌘+.` | Zoom into node (focus) |
| `⌘+,` | Zoom out (back to parent) |
| `Escape` | Zoom to root |

### Quick Actions

| Key | Action |
|-----|--------|
| `⌘+N` | New document |
| `⌘+O` | Open document |
| `⌘+S` | Save (also auto-saves) |
| `⌘+F` | Find in document |
| `⌘+Shift+F` | Find across all documents |
| `⌘+K` | Command palette |

### Global (macOS)

| Key | Action |
|-----|--------|
| `⌘+Shift+O` | Summon Lineout.ly (configurable) |

---

## Node Movement: The Heart of Outlining

Moving nodes must feel **instant and effortless**. Three ways to move:

### 1. Keyboard Movement (Primary)

**Vertical: Move among siblings**
```
⌘ + ↑    Move node up (swap with sibling above)
⌘ + ↓    Move node down (swap with sibling below)
```

**Horizontal: Change hierarchy**
```
Tab          Indent → become child of node above
Shift + Tab  Outdent → become sibling of parent
```

**Visual feedback:**
- Node briefly highlights as it moves
- Smooth 150ms animation
- Haptic feedback on iOS

**Example: Indent**
```
Before:                 After Tab:
- Task A                - Task A
- Task B  ← cursor          - Task B  ← now child of A
- Task C                - Task C
```

**Example: Move Up**
```
Before:                 After ⌘+↑:
- Task A                - Task B  ← moved up
- Task B  ← cursor      - Task A
- Task C                - Task C
```

### 2. Drag & Drop (Mouse/Touch)

**Grab handle:** The bullet point is the drag handle

**Drop indicators:**
```
─────────────────────   ← Blue line: drop as sibling above
  • Target Node
─────────────────────   ← Blue line: drop as sibling below
    ┌─ ─ ─ ─ ─ ─ ─ ┐   ← Blue indent: drop as first child
```

**Smart drop zones:**
- **Upper 25%** of node → sibling above
- **Lower 25%** of node → sibling below
- **Middle 50%** of node → first child (indent)
- **Left edge** while dragging → outdent to that level

**Drag across collapsed nodes:**
- Hover over collapsed node for 500ms → auto-expands
- Drop on collapsed node → becomes last child

**Multi-select drag:**
- `Shift+Click` to select range
- `⌘+Click` to add to selection
- Drag any selected node → all move together

### 3. Cut/Copy/Paste (Power Move)

```
⌘ + X    Cut node (with all children)
⌘ + C    Copy node (with all children)
⌘ + V    Paste as sibling below cursor
⌘ + Shift + V    Paste as first child of cursor
```

**Use case:** Move node to completely different part of outline
1. Navigate to source, `⌘+X`
2. Navigate to destination, `⌘+V`
3. Done.

### 4. Quick Move Command (Future: Phase 5)

```
⌘ + M    Opens move dialog
```

```
┌─────────────────────────────────────┐
│ Move "Current Node" to...           │
│ ┌─────────────────────────────────┐ │
│ │ 🔍 Type to search...            │ │
│ └─────────────────────────────────┘ │
│                                     │
│   Recent destinations:              │
│   • Project Alpha > Tasks           │
│   • Inbox                           │
│   • Archive                         │
│                                     │
│   ↑↓ navigate  ⏎ select  esc close │
└─────────────────────────────────────┘
```

### Movement Rules

1. **Can't move to own descendant** — Prevents circular references
2. **Undo always available** — `⌘+Z` reverses any move
3. **Children travel with parent** — Moving a node moves its entire subtree
4. **Zoom context preserved** — Moving within zoomed view stays in zoom

### Movement Animation

```swift
// 150ms spring animation for all moves
withAnimation(.spring(duration: 0.15)) {
    node.moveTo(newParent, at: index)
}
```

- **Keyboard moves:** Node slides to new position
- **Drag:** Ghost preview follows cursor, original fades
- **Drop:** Node snaps into place with subtle bounce

---

## Zoom: The Killer Feature

**Zooming** transforms any node into a temporary root. The breadcrumb trail shows your path:

```
Documents › Project Alpha › Phase 2 › Tasks
```

- Click any breadcrumb to zoom to that level
- `⌘+,` steps back one level
- `Escape` returns to document root
- Zoomed state persists per document

---

## Visual Design: Jony Ive Principles

### Typography

- **Primary**: SF Pro Text (system font, optimized for readability)
- **Monospace option**: SF Mono for code-focused outlines
- **Hierarchy through weight**, not color:
  - Root: Semibold
  - Level 1: Medium
  - Level 2+: Regular

### Color Palette

```
Background:     #FFFFFF (light) / #1C1C1E (dark)
Primary Text:   #000000 (light) / #FFFFFF (dark)
Secondary:      #8E8E93
Accent:         #007AFF (selection, focus)
Subtle Border:  #E5E5EA (light) / #38383A (dark)
```

### Spacing System (8pt grid)

```
Indent:         24pt per level
Line height:    28pt
Bullet size:    6pt circle
Bullet margin:  12pt from text
```

### The Bullet

A simple filled circle that transforms:

- **Has children (collapsed)**: `▸` (disclosure triangle)
- **Has children (expanded)**: `▾`
- **No children**: `•`
- **Hover**: Subtle highlight for drag affordance

### Animation

- **Duration**: 200ms
- **Curve**: Ease-out
- **Collapse/Expand**: Height transition with opacity
- **Zoom**: Subtle scale + fade

### Focus States

- Selected line: Light blue background (#007AFF at 10% opacity)
- Editing: Blue caret, no border (text IS the interface)
- Drag preview: Slight elevation shadow

---

## Platform Adaptations

### macOS

- **Window**: Resizable, remembers position
- **Menu bar**: Full menu structure with all shortcuts
- **Global shortcut**: Configurable in System Preferences
- **Sidebar**: Document list (collapsible)
- **Touch Bar**: Quick actions (if available)

### iOS/iPadOS

- **Navigation**: Slide between documents
- **Keyboard**: Full external keyboard support (same shortcuts)
- **Touch**:
  - Tap to select/edit
  - Long-press to drag
  - Swipe right to indent
  - Swipe left to outdent
- **iPad multitasking**: Split view, slide over

---

## Technical Implementation

### Stack

```
┌─────────────────────────────────────┐
│           SwiftUI Views             │
├─────────────────────────────────────┤
│         View Models (MVVM)          │
├─────────────────────────────────────┤
│    OutlineDocument (FileDocument)   │
├─────────────────────────────────────┤
│      Markdown Parser/Serializer     │
├─────────────────────────────────────┤
│           iCloud Drive              │
└─────────────────────────────────────┘
```

### Key Components

1. **OutlineDocument**: Conforms to `FileDocument` for native save/load
2. **OutlineNode**: Observable model for reactive UI
3. **OutlineView**: Recursive SwiftUI view for infinite nesting
4. **KeyboardHandler**: Central keyboard event processing
5. **MarkdownCodec**: Parse/serialize outline ↔ markdown

### Sync Strategy

Using **iCloud Drive** (not CloudKit):
- Files live in app's iCloud container
- System handles sync automatically
- Conflict resolution via file coordination
- Works offline, syncs when connected

### Performance

- **Lazy loading**: Only render visible nodes
- **Virtualization**: Recycle views for large outlines
- **Diffing**: Minimal updates on changes
- **Background parsing**: Parse markdown off main thread

---

## Roadmap

### Phase 1: Foundation (Current)
- [ ] OutlineNode data model with parent/child relationships
- [ ] Markdown parser/serializer (bidirectional)
- [ ] Recursive OutlineView with LazyVStack virtualization
- [ ] Expand/collapse functionality
- [ ] Keyboard navigation (↑↓←→)
- [ ] Basic selection and focus management

### Phase 2: Movement & Editing (Critical)
- [ ] **Move up/down** (⌘+↑↓) — swap siblings
- [ ] **Indent/outdent** (Tab/Shift+Tab) — change hierarchy
- [ ] **Drag & drop** with smart drop zones
- [ ] **Cut/Copy/Paste** (⌘+X/C/V) — move anywhere
- [ ] Create/delete nodes (Enter/⌘+Backspace)
- [ ] Inline text editing
- [ ] Undo/Redo stack (⌘+Z/⌘+Shift+Z)
- [ ] Movement animations (150ms spring)
- [ ] Auto-save on every change

### Phase 3: Zoom & Focus
- [ ] Zoom into node (⌘+.)
- [ ] Breadcrumb navigation
- [ ] Zoom out (⌘+,)
- [ ] Persist zoom state

### Phase 4: Documents
- [ ] FileDocument implementation
- [ ] iCloud Drive integration
- [ ] Document browser
- [ ] Recent documents

### Phase 5: Polish
- [ ] Global shortcut (macOS)
- [ ] Command palette (⌘+K)
- [ ] Search within document
- [ ] Search across documents
- [ ] Animations and transitions

### Phase 6: Advanced
- [ ] Tags/labels
- [ ] Links between nodes
- [ ] Export (PDF, OPML, HTML)
- [ ] Themes

---

## File Format Specification

### Basic Structure

```markdown
# Document Title

- Node 1
    - Child 1.1
        - Grandchild 1.1.1
    - Child 1.2
- Node 2
```

### Rules

1. Document title: First `# ` line
2. Nodes: Lines starting with `- ` (after indentation)
3. Indentation: 4 spaces per level
4. Empty lines: Preserved for readability
5. Metadata (future): YAML front matter

### Example with Metadata

```markdown
---
created: 2025-01-24T10:30:00Z
modified: 2025-01-24T14:22:00Z
collapsed:
  - uuid-of-collapsed-node-1
  - uuid-of-collapsed-node-2
zoom: uuid-of-zoomed-node
---

# Project Planning

- Research Phase
    - Market analysis
    - Competitor review
- Development
    - MVP features
        - Core editing
        - Sync
    - Nice to have
        - Themes
        - Export
```

---

## Success Metrics

1. **Speed**: Open to typing < 500ms
2. **Reliability**: Zero data loss
3. **Discoverability**: Users find zoom within first session
4. **Stickiness**: Daily active use for note-taking

---

## Name Consideration

Current: **Lineout.ly**

Alternatives to consider:
- **Outline** (simple, direct)
- **Deeply** (captures nesting)
- **Thread** (captures connected thoughts)
- **Canvas** (captures infinite space)

---

## Next Steps

1. **Approve this proposal** — Align on scope and priorities
2. **Implement OutlineNode model** — Foundation for everything
3. **Build Markdown codec** — Enable file format
4. **Create recursive OutlineView** — Basic UI
5. **Add keyboard handling** — Core interaction model

---

*"Simplicity is the ultimate sophistication."* — Leonardo da Vinci
