# today-md — Product Requirements Document

**Version:** 1.6.1
**Platform:** macOS 14.0+
**Tech Stack:** Swift 6, SwiftUI, SQLite with FTS5
**License:** MIT
**Repository:** github.com/arthurliebhardt/today-md

---

## 1. Product Overview

today-md is a native macOS task planner built around a Kanban board with three time-based lanes: **Today**, **This Week**, and **Backlog**. It is local-first, stores all data in a SQLite database on disk, and optionally syncs via a user-chosen cloud folder (iCloud Drive, OneDrive, etc.).

The app targets individuals who want a lightweight, keyboard-driven planning tool with Markdown notes and no account or subscription requirement.

---

## 2. Data Model

### 2.1 Entities

**TaskList**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| name | String | Custom list name |
| icon | String | SF Symbol name |
| colorName | String | One of: blue, purple, pink, red, orange, yellow, green, teal |
| sortOrder | Int | Display order in sidebar |
| items | [TaskItem] | Contained tasks |

**TaskItem**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| title | String | Task title |
| isDone | Bool | Completion status |
| blockRaw | String | TimeBlock value: "today", "thisWeek", "backlog" |
| sortOrder | Int | Display order within block/list |
| creationDate | Date | ISO8601 timestamp |
| subtasks | [SubTask] | Nested subtasks (1:N) |
| note | TaskNote? | Optional Markdown note |
| list | TaskList? | Parent list (nil = unassigned) |

**SubTask**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| title | String | Subtask name |
| isCompleted | Bool | Completion flag |
| sortOrder | Int | Display order |

Subtasks are bidirectionally mapped to Markdown checklist items (`- [ ]` / `- [x]`) by normalized title matching (case/diacritic insensitive).

**TaskNote**

| Field | Type | Description |
|-------|------|-------------|
| content | String | Markdown text |
| lastModified | Date | ISO8601 timestamp |

### 2.2 Database Schema

```sql
task_lists     (id, name, icon, color_name, sort_order)
tasks          (id, list_id, title, is_done, block_raw, sort_order, creation_date)
task_notes     (task_id, content, last_modified)
subtasks       (id, task_id, title, is_completed, sort_order)
tasks_fts      (task_id UNINDEXED, title, note_markdown, subtask_text)  -- FTS5 virtual table
```

Foreign keys use `ON DELETE CASCADE`. Indexes exist on sort order and list/block combinations.

---

## 3. Core Features

### 3.1 Kanban Board

Three lanes corresponding to the `TimeBlock` enum:

- **Today** — work for the current day
- **This Week** — work for the current week
- **Backlog** — unscheduled work

Each lane has an active section and a collapsible done section. Tasks are ordered by `sortOrder` within each lane.

**Focus Today** collapses This Week and Backlog to show only the Today lane.

### 3.2 Task Operations

| Operation | Trigger | Behavior |
|-----------|---------|----------|
| Create | Cmd+N, menu bar quick-add, Dynamic Island | Creates task with sortOrder=0, shifts others down |
| Edit title | Inline text field | Debounced save |
| Move lane | Drag to another lane | Updates blockRaw, normalizes sort order |
| Complete | Checkbox, Cmd+Shift+D | Toggles isDone |
| Delete | Delete key, trash button | Cascades to subtasks and notes |
| Reorder | Drag within lane | Normalizes sort order to 0, 1, 2, ... |

### 3.3 Multi-Select

- Click to select, Shift+Click for range select, Cmd+A to select all visible.
- Dragging any selected task moves the entire selection.
- Delete key and Cmd+Shift+D operate on the full selection.

### 3.4 Custom Lists

Users create lists with a name, SF Symbol icon (20+ options), and one of 8 color themes. Lists appear in the sidebar with task counts. Deleting a list orphans its tasks (moves to unassigned).

### 3.5 Subtasks

- Add via checklist UI or inline entry field.
- Toggle completion via checkbox — updates both the subtask and the mapped Markdown checklist item.
- Delete removes from both subtask list and note checklist.

---

## 4. Markdown Editor

### 4.1 Toolbar Actions

| Action | Shortcut | Insertion |
|--------|----------|-----------|
| Heading 1 | Cmd+1 | `# ` at line start |
| Heading 2 | Cmd+2 | `## ` at line start |
| Heading 3 | Cmd+3 | `### ` at line start |
| Bold | Cmd+B | `**selection**` |
| Italic | Cmd+I | `_selection_` |
| Strikethrough | Cmd+Shift+S | `~~selection~~` |
| Code Block | Cmd+` | ` ```\n\n``` ` |
| Bullet List | Cmd+Shift+L | `- ` prefix |
| Numbered List | Cmd+Shift+O | `1. ` prefix (auto-increment) |
| Checklist | Cmd+Shift+T | `- [ ] ` prefix |
| Divider | Cmd+Shift+D | `\n---\n` |

### 4.2 Checklist Synchronization

Markdown checklist items (`- [ ] text` / `- [x] text`) are parsed and mapped to the task's subtask list by normalized title. Toggling either side updates the other. Each checklist item tracks its `lineIndex` for precise in-place edits.

### 4.3 Auto-Archive

Notes are automatically exported as `.md` files to `~/Library/Application Support/today-md/Markdown Archive/`. Each file includes YAML frontmatter (task_id, title, list, lane, created_at, updated_at).

---

## 5. Search

### 5.1 Full-Text Search (FTS5)

Indexes task titles, note content, and concatenated subtask titles. Queries are split into space-separated terms with wildcard suffix (`term*`), ranked by BM25.

### 5.2 Results Display

- Up to 3 matching excerpt lines per task, 72-char context window around first match.
- Yellow background highlighting on matched terms (case/diacritic insensitive).
- Board view switches to a flat ranked list when search is active.

---

## 6. Global Dynamic Island

A floating quick-capture panel at the top of the screen.

### 6.1 Appearance

- **Size:** 720x104pt panel, centered horizontally, 18pt from screen top.
- **Style:** Dark gradient background, orange accent, notch-shaped with pill bottom (28pt corner radius).

### 6.2 Behavior

| Trigger | Action |
|---------|--------|
| Mouse enters top-center 260x14pt zone | Panel fades in |
| Return key | Creates task in Today lane, dismisses |
| Escape key | Dismisses |
| Mouse leaves (draft empty) | Dismisses after 200ms |
| External click | Dismisses |

### 6.3 Controls

- Text field for task title (monospace semibold, auto-focused).
- List selector dropdown (defaults to last selected or Unassigned).
- Lane badge shows "Today" (hardcoded target).

Enabled by default. Toggle in Settings. UserDefaults key: `TodayMdGlobalDynamicIslandEnabled`.

---

## 7. Menu Bar

### 7.1 Menu Bar Extra

- Custom 18x18 checkmark icon (orange/brown palette).
- Window-style extra that can be docked or detached.

### 7.2 Content

- Shows up to 6 active Today tasks. Displays "X more" indicator if truncated.
- Quick-add text field with list selector dropdown.
- Sync status indicator (colored dot + relative time).

---

## 8. Sync

### 8.1 Architecture

Bidirectional sync via `TodayMdSyncService`. Writes a full JSON snapshot (`today-md-sync.json`) and a Markdown Archive folder to the chosen cloud folder.

### 8.2 Trigger Points

- App launch (if enabled)
- App becomes active
- Local changes (debounced 2 seconds)
- Manual "Sync Now" from settings

### 8.3 Sync Flow

1. Load remote archive from cloud folder.
2. Compare `syncRevisionID` against `lastSyncedRevision`.
3. If remote is newer AND local has unsynced changes → conflict state.
4. Otherwise, push local or pull remote as appropriate.

### 8.4 Conflict Resolution

When a conflict is detected, the user chooses:

- **Keep Local:** Backs up remote to `Conflict Backups/`, pushes local.
- **Use Remote:** Backs up local to `Conflict Backups/`, applies remote.

### 8.5 Sync States

| State | Indicator Color |
|-------|----------------|
| Idle | Green |
| Syncing | Blue |
| Conflict | Orange |
| Error | Red |

### 8.6 Error Handling

Stale bookmarks or missing folders auto-disable sync and surface an error message in settings.

---

## 9. Import & Export

### 9.1 Export

Creates a dated folder `today-md-export-{yyyy-MM-dd-HHmm}/` containing:

- `today-md-backup-{date}.json` — full `TodayMdArchive` (version, timestamp, lists, tasks, subtasks, notes).
- `today-md-backup-{date}-markdown/` — one `.md` file per task with YAML frontmatter.

### 9.2 Import

Opens a file dialog for JSON files. User chooses:

- **Merge:** Appends imported lists/tasks to existing data.
- **Replace Existing:** Clears database, loads imported archive.

Import sanitizes UUIDs, clears stale references, and normalizes sort orders.

### 9.3 Archive Format

```json
{
  "version": 1,
  "exportedAt": "2026-03-22T10:00:00Z",
  "syncRevisionID": "...",
  "lists": [...],
  "unassignedTasks": [...]
}
```

---

## 10. Settings

Accessible via modal sheet (760x680pt), divided into sections:

### 10.1 Interface

- Toggle Global Dynamic Island on/off.

### 10.2 Data Backup

- Import Backup (merge or replace).
- Export Backup.
- Open Markdown Archive folder.

### 10.3 Sync

- Status indicator with last sync time.
- Choose/change sync folder (security-scoped bookmark).
- Sync Now button.
- Open Sync Folder in Finder.
- Disable Sync.

### 10.4 Shortcuts

- Open keyboard shortcut cheatsheet.
- Preview of common shortcuts.

---

## 11. Keyboard Shortcuts

### Navigation & Selection

| Action | Shortcut |
|--------|----------|
| Select All Visible | Cmd+A |
| Delete Selection | Delete |
| Mark Done | Cmd+Shift+D |
| New Task in Lane | Cmd+N |
| Open Shortcuts Sheet | Cmd+/ |
| Undo | Cmd+Z |
| Redo | Cmd+Shift+Z |

### Markdown Editor

See Section 4.1 for full toolbar shortcut table. Tab/Shift+Tab for list indentation (up to 3 levels).

---

## 12. Window Management

| Window | Size | Behavior |
|--------|------|----------|
| Main | 1500x920 default, 900x600 min | Centered on first launch, NavigationSplitView |
| Settings | 760x680 | Modal sheet |
| Shortcuts | 620x640 | Modal sheet |
| Menu Bar | Status bar level | Floats above all windows, all spaces |

Sidebar uses overlay mode when window width is narrow.

---

## 13. Undo/Redo

- `AppUndoController` with 100-level undo stack.
- All store mutations register with descriptive action names ("Add Task", "Move Task", etc.).
- Prefers text view undo manager when editor is focused; falls back to app manager otherwise.

---

## 14. Onboarding

- First launch detected via `TodayMdHasLaunchedBefore` UserDefaults key.
- Seeds sample tasks across all time blocks and lists if sync is disabled and no data exists.
- Dev mode (`swift run`) resets to sample data on every launch.

---

## 15. Drag & Drop

- Tasks are transferable via custom UTType `com.today-md.app.taskitem` (codable UUID).
- Single or multi-select drag between lanes, within lanes, and into done sections.
- Cross-lane drops update the task's `blockRaw`. Drops into done section mark complete.
- Sort order normalized after every drop.
- All drops register with the undo manager.

---

## 16. Technical Architecture

### State Management

- `TodayMdStore` (@Observable) — main view model holding all lists and tasks.
- All model types (`TaskList`, `TaskItem`, `SubTask`, `TaskNote`) are @Observable.
- Services (`TodayMdSyncService`, `GlobalDynamicIslandController`) use ObservableObject for backward compatibility.

### Database

- Direct SQLite3 C API bindings, no ORM.
- Prepared statements with parameter binding.
- Transaction support for multi-statement operations.
- FTS5 virtual table updated on every task/note change.

### File I/O

- Security-scoped bookmarks for sandbox compliance.
- Atomic writes for all file operations.
- Localized error descriptions for all failure modes.

### Concurrency

- All UI updates on @MainActor.
- DispatchQueue for debounced sync and async file operations.
- Weak references in services to prevent retain cycles.

---

## 17. Error Handling

| Domain | Error Type | User Feedback |
|--------|-----------|---------------|
| Database | openFailed, executeFailed, prepareFailed, bindFailed, stepFailed | Propagated as throws |
| Sync | folderNotConfigured, folderRequiresReselection, storeUnavailable | Red text in settings, auto-disable |
| File I/O | NSError from FileManager | Alert dialog with error message |
