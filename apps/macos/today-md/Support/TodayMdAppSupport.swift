import AppKit
import SwiftUI

enum TodayMdSceneID {
    static let mainWindow = "today-md-main-window"
}

enum TodayMdPreferenceKey {
    static let appearanceMode = "TodayMdAppearanceMode"
    static let workspaceMode = "TodayMdWorkspaceMode"
    static let calendarDefaultDurationMinutes = "TodayMdCalendarDefaultDurationMinutes"
    static let calendarDefaultIdentifier = "TodayMdCalendarDefaultIdentifier"
    static let calendarVisibleIdentifiers = "TodayMdCalendarVisibleIdentifiers"
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            return "Follow the current macOS appearance automatically."
        case .light:
            return "Keep the workspace in light mode."
        case .dark:
            return "Keep the workspace in dark mode."
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@MainActor
final class AppUndoController: ObservableObject {
    let manager: UndoManager

    init() {
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        self.manager = manager
    }

    func undo() {
        preferredUndoManager(canPerform: \.canUndo)?.undo()
    }

    func redo() {
        preferredUndoManager(canPerform: \.canRedo)?.redo()
    }

    private func preferredUndoManager(canPerform capability: KeyPath<UndoManager, Bool>) -> UndoManager? {
        if let responderUndoManager = NSApp.keyWindow?.firstResponder?.undoManager,
           responderUndoManager !== manager,
           responderUndoManager[keyPath: capability] {
            return responderUndoManager
        }

        return manager[keyPath: capability] ? manager : nil
    }
}

struct ShortcutItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let shortcut: String
    let detail: String
}

struct ShortcutSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [ShortcutItem]
}

enum ShortcutCheatsheet {
    static let sections: [ShortcutSection] = [
        ShortcutSection(
            title: "Selection",
            items: [
                ShortcutItem(
                    title: "Select task",
                    shortcut: "Click",
                    detail: "Select a single task and make it the active anchor."
                ),
                ShortcutItem(
                    title: "Extend selection",
                    shortcut: "Shift-Click",
                    detail: "Select the range from the current anchor to the clicked task."
                ),
                ShortcutItem(
                    title: "Select all visible tasks",
                    shortcut: "Cmd-A",
                    detail: "Select every task in the focused lane on the board, or every visible task in All Tasks and search."
                ),
                ShortcutItem(
                    title: "Delete selection",
                    shortcut: "Delete",
                    detail: "Delete the selected task or the whole selected set."
                ),
                ShortcutItem(
                    title: "Mark selection done",
                    shortcut: "Cmd-Shift-D",
                    detail: "Mark the selected task or selected tasks as done."
                )
            ]
        ),
        ShortcutSection(
            title: "Board",
            items: [
                ShortcutItem(
                    title: "Create task in selected lane",
                    shortcut: "Cmd-N",
                    detail: "Create a new task in the focused lane. In All Tasks, it is created without a list."
                ),
                ShortcutItem(
                    title: "Focus lane",
                    shortcut: "Click lane",
                    detail: "Click inside a lane to make it the target for lane-wide shortcuts."
                )
            ]
        ),
        ShortcutSection(
            title: "Editor",
            items: [
                ShortcutItem(
                    title: "Heading levels",
                    shortcut: "Cmd-1 / 2 / 3",
                    detail: "Turn the current line or selected lines into H1, H2, or H3 headings."
                ),
                ShortcutItem(
                    title: "Bold",
                    shortcut: "Cmd-B",
                    detail: "Wrap the current selection in Markdown bold markers."
                ),
                ShortcutItem(
                    title: "Italic",
                    shortcut: "Cmd-I",
                    detail: "Wrap the current selection in Markdown italic markers."
                ),
                ShortcutItem(
                    title: "Strikethrough",
                    shortcut: "Cmd-Shift-S",
                    detail: "Wrap the current selection in Markdown strikethrough markers."
                ),
                ShortcutItem(
                    title: "Code block",
                    shortcut: "Cmd-`",
                    detail: "Insert a fenced Markdown code block at the cursor."
                ),
                ShortcutItem(
                    title: "Bullet list",
                    shortcut: "Cmd-Shift-L",
                    detail: "Prefix the current line or selected lines with a bullet marker."
                ),
                ShortcutItem(
                    title: "Numbered list",
                    shortcut: "Cmd-Shift-O",
                    detail: "Prefix the current line or selected lines with numbered list markers."
                ),
                ShortcutItem(
                    title: "Checklist todo",
                    shortcut: "Cmd-Shift-T",
                    detail: "Insert Markdown checklist items for the current line or selection."
                ),
                ShortcutItem(
                    title: "Indent list level",
                    shortcut: "Tab",
                    detail: "Indent the current list item or the selected list items, up to three levels deep."
                ),
                ShortcutItem(
                    title: "Outdent list level",
                    shortcut: "Shift-Tab",
                    detail: "Move the current list item or selected list items back toward the left margin."
                ),
                ShortcutItem(
                    title: "Divider",
                    shortcut: "Cmd-Shift-D",
                    detail: "Insert a Markdown divider at the cursor."
                )
            ]
        ),
        ShortcutSection(
            title: "App",
            items: [
                ShortcutItem(
                    title: "Quick add from anywhere",
                    shortcut: QuickAddShortcut.display,
                    detail: "Open the floating quick-add notch, focus the field, and start typing immediately."
                ),
                ShortcutItem(
                    title: "Open shortcuts",
                    shortcut: "Cmd-/",
                    detail: "Open this keyboard shortcuts cheatsheet."
                ),
                ShortcutItem(
                    title: "Undo",
                    shortcut: "Cmd-Z",
                    detail: "Undo the last change."
                ),
                ShortcutItem(
                    title: "Redo",
                    shortcut: "Cmd-Shift-Z",
                    detail: "Redo the last undone change."
                )
            ]
        )
    ]
}

@MainActor
struct TaskNavigationRequest: Equatable {
    let id = UUID()
    let taskID: UUID
}

@MainActor
final class AppPresentationState: ObservableObject {
    @Published var showingKeyboardShortcuts = false
    @Published var taskNavigationRequest: TaskNavigationRequest?

    func presentKeyboardShortcuts() {
        showingKeyboardShortcuts = true
    }

    func openTask(_ taskID: UUID) {
        taskNavigationRequest = TaskNavigationRequest(taskID: taskID)
    }
}
