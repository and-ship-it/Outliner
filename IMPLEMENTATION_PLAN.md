# Lineout.ly — Implementation Plan

**Goal:** The simplest, fastest, best outliner across iOS and macOS.

**Scope:** Core outliner only. No integrations. No sync complexity. Just pure outlining.

---

## What We're Building

```
┌─────────────────────────────────────────┐
│  One infinite outline                   │
│  ├── Unlimited nesting                  │
│  ├── Collapse / Expand                  │
│  ├── Zoom in / Zoom out                 │
│  ├── Move nodes (keyboard + drag)       │
│  ├── Title + Body per node              │
│  └── Saves to iCloud as markdown        │
└─────────────────────────────────────────┘
```

---

## Phase 1: Data & Rendering

**Duration:** Get this right first

### 1.1 OutlineNode Model

```swift
@Observable
final class OutlineNode: Identifiable {
    let id: UUID
    var title: String
    var body: String
    var isCollapsed: Bool
    var children: [OutlineNode]
    weak var parent: OutlineNode?

    // Computed
    var hasChildren: Bool { !children.isEmpty }
    var hasBody: Bool { !body.isEmpty }
    var depth: Int { parent?.depth ?? -1 + 1 }
}
```

### 1.2 OutlineDocument

```swift
@Observable
final class OutlineDocument {
    var root: OutlineNode           // Invisible root, children are top-level
    var focusedNode: OutlineNode?   // Currently selected
    var zoomedNode: OutlineNode?    // Current zoom root (nil = document root)

    // File
    var fileURL: URL?
    var isDirty: Bool
}
```

### 1.3 Markdown Codec

```swift
struct MarkdownCodec {
    static func parse(_ markdown: String) -> OutlineNode
    static func serialize(_ root: OutlineNode) -> String
}
```

**Format:**
```markdown
- Title here

  Body paragraph here.
  Can be multiple lines.

    - Child 1
    - Child 2
        - Grandchild
```

### 1.4 Recursive OutlineView

```swift
struct OutlineView: View {
    @Bindable var document: OutlineDocument

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleNodes) { node in
                    NodeRow(node: node, document: document)
                }
            }
        }
    }

    var visibleNodes: [OutlineNode] {
        // Flatten tree respecting collapse state and zoom
    }
}
```

### 1.5 NodeRow View

```swift
struct NodeRow: View {
    @Bindable var node: OutlineNode
    let document: OutlineDocument
    let depth: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Indent
            Spacer().frame(width: CGFloat(depth) * 24)

            // Bullet / Disclosure
            BulletView(node: node)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                TitleView(node: node)
                if !node.isCollapsed && node.hasBody {
                    BodyView(node: node)
                }
            }
        }
    }
}
```

### Phase 1 Deliverables

- [ ] `OutlineNode` model with parent/child relationships
- [ ] `OutlineDocument` managing tree state
- [ ] `MarkdownCodec` parse and serialize
- [ ] `OutlineView` with LazyVStack virtualization
- [ ] `NodeRow` with proper indentation
- [ ] Tap to select node
- [ ] Tap bullet to collapse/expand
- [ ] Renders 10,000 nodes smoothly

---

## Phase 2: Keyboard Navigation

### 2.1 Focus Management

```swift
extension OutlineDocument {
    func moveFocusUp()      // Previous visible node
    func moveFocusDown()    // Next visible node
    func focusParent()      // Go to parent
    func focusFirstChild()  // Go to first child (expand if needed)
}
```

### 2.2 Key Bindings

| Key | Action |
|-----|--------|
| `↑` | `moveFocusUp()` |
| `↓` | `moveFocusDown()` |
| `←` | Collapse or `focusParent()` |
| `→` | Expand or `focusFirstChild()` |

### 2.3 Platform Handling

```swift
// macOS: .onKeyPress modifier
// iOS: External keyboard via .keyboardShortcut + UIKeyCommand
```

### Phase 2 Deliverables

- [ ] Arrow key navigation (↑↓←→)
- [ ] Visual focus indicator (highlight row)
- [ ] Collapse with ← when expanded
- [ ] Expand with → when collapsed
- [ ] Works on macOS with keyboard
- [ ] Works on iPad with external keyboard

---

## Phase 3: Editing

### 3.1 Node Operations

```swift
extension OutlineDocument {
    func createSiblingBelow()     // Enter
    func createSiblingAbove()     // Shift+Enter
    func createChild()            // ⌘+Enter
    func deleteNode()             // ⌘+Backspace
    func indent()                 // Tab
    func outdent()                // Shift+Tab
}
```

### 3.2 Inline Editing

```swift
struct TitleView: View {
    @Bindable var node: OutlineNode
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("", text: $node.title)
            .focused($isEditing)
            .onSubmit { createSiblingBelow() }
    }
}
```

### 3.3 Undo/Redo

```swift
@Observable
final class OutlineDocument {
    private var undoStack: [OutlineState] = []
    private var redoStack: [OutlineState] = []

    func snapshot()    // Before each operation
    func undo()        // ⌘+Z
    func redo()        // ⌘+Shift+Z
}
```

### Phase 3 Deliverables

- [ ] Enter → new sibling below
- [ ] Shift+Enter → new sibling above
- [ ] ⌘+Enter → new child
- [ ] ⌘+Backspace → delete node
- [ ] Tab → indent
- [ ] Shift+Tab → outdent
- [ ] Inline title editing
- [ ] Undo/Redo stack
- [ ] Auto-save on changes

---

## Phase 4: Movement

### 4.1 Keyboard Movement

```swift
extension OutlineDocument {
    func moveUp()       // ⌘+↑ - swap with previous sibling
    func moveDown()     // ⌘+↓ - swap with next sibling
}
```

### 4.2 Drag & Drop

```swift
struct NodeRow: View {
    var body: some View {
        content
            .draggable(node.id)
            .dropDestination(for: UUID.self) { ids, location in
                handleDrop(ids: ids, location: location)
            }
    }
}
```

### 4.3 Drop Zones

```
┌────────────────────────┐
│ ░░░░░ ABOVE ░░░░░░░░░░ │  ← Top 25%: sibling above
├────────────────────────┤
│                        │
│      AS CHILD          │  ← Middle 50%: first child
│                        │
├────────────────────────┤
│ ░░░░░ BELOW ░░░░░░░░░░ │  ← Bottom 25%: sibling below
└────────────────────────┘
```

### Phase 4 Deliverables

- [ ] ⌘+↑ → move node up
- [ ] ⌘+↓ → move node down
- [ ] Drag by bullet handle
- [ ] Drop indicators (line above/below, indent for child)
- [ ] Drop to reorder siblings
- [ ] Drop to reparent
- [ ] Movement animation (150ms)
- [ ] Cut/Copy/Paste (⌘+X/C/V)

---

## Phase 5: Zoom

### 5.1 Zoom State

```swift
extension OutlineDocument {
    var zoomedNode: OutlineNode?   // nil = root
    var breadcrumbs: [OutlineNode] // Path from root to zoom

    func zoomIn()       // ⌘+. - zoom to focused node
    func zoomOut()      // ⌘+, - zoom to parent
    func zoomToRoot()   // Escape - back to document root
    func zoomTo(_ node: OutlineNode)
}
```

### 5.2 Breadcrumb UI

```
┌─────────────────────────────────────────────────────┐
│  📄 My Outline  ›  Projects  ›  App Redesign  ›     │
└─────────────────────────────────────────────────────┘
```

Tap any breadcrumb → zoom to that level

### 5.3 Zoomed View

When zoomed:
- Only show children of zoomed node
- Zoomed node's title appears as header
- Zoomed node's body appears below header

### Phase 5 Deliverables

- [ ] ⌘+. → zoom into focused node
- [ ] ⌘+, → zoom out one level
- [ ] Escape → zoom to root
- [ ] Breadcrumb trail (clickable)
- [ ] Zoomed node as header
- [ ] Persist zoom state per document

---

## Phase 6: File & iCloud

### 6.1 Document-Based App

```swift
@main
struct LineoutApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: OutlineDocument()) { file in
            OutlineView(document: file.document)
        }
    }
}
```

### 6.2 FileDocument Conformance

```swift
extension OutlineDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown] }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents!
        let markdown = String(data: data, encoding: .utf8)!
        self.root = MarkdownCodec.parse(markdown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let markdown = MarkdownCodec.serialize(root)
        let data = markdown.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}
```

### 6.3 iCloud Container

```
~/Library/Mobile Documents/iCloud~ly~lineout~app/Documents/
└── *.md files
```

- Files visible in Files app (iOS) and Finder (macOS)
- Automatic sync via iCloud Drive
- Open with any markdown editor

### Phase 6 Deliverables

- [ ] DocumentGroup scene
- [ ] FileDocument conformance
- [ ] Save as .md
- [ ] Open .md files
- [ ] iCloud container setup
- [ ] Auto-save
- [ ] Recent documents

---

## Phase 7: Polish

### 7.1 Global Shortcut (macOS)

```swift
// Register ⌘+Shift+O to summon app
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    if event.modifierFlags.contains([.command, .shift]) && event.keyCode == kVK_ANSI_O {
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

### 7.2 Touch Gestures (iOS)

- Swipe right on node → indent
- Swipe left on node → outdent
- Long press → drag mode
- Pinch → zoom in/out? (experimental)

### 7.3 Design Polish

- Typography: SF Pro, weight hierarchy
- Spacing: 8pt grid
- Animation: 150ms spring
- Selection: subtle blue highlight
- Dark mode support

### Phase 7 Deliverables

- [ ] Global shortcut (macOS)
- [ ] Touch gestures (iOS)
- [ ] Dark mode
- [ ] Typography polish
- [ ] Animation polish
- [ ] App icon

---

## File Structure

```
Lineout-ly/
├── App/
│   └── LineoutApp.swift
├── Models/
│   ├── OutlineNode.swift
│   └── OutlineDocument.swift
├── Views/
│   ├── OutlineView.swift
│   ├── NodeRow.swift
│   ├── BulletView.swift
│   ├── TitleView.swift
│   ├── BodyView.swift
│   └── BreadcrumbView.swift
├── Services/
│   ├── MarkdownCodec.swift
│   └── KeyboardHandler.swift
└── Extensions/
    └── View+Focus.swift
```

---

## Success Criteria

| Metric | Target |
|--------|--------|
| Cold launch to typing | < 500ms |
| Node render (10k nodes) | 60fps |
| Keyboard response | < 16ms |
| File save | < 100ms |
| Memory (10k nodes) | < 50MB |

---

## Start Here

**Week 1:** Phase 1 (Data & Rendering)
1. OutlineNode model
2. MarkdownCodec (parse/serialize)
3. Basic OutlineView
4. NodeRow with indentation
5. Collapse/expand

This gives us a working outline viewer. Then we iterate.

---

Ready to build?
