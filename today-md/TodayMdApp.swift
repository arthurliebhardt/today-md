import AppKit
import SwiftUI
import SwiftData

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.minSize = NSSize(width: 1200, height: 720)
            window.setContentSize(NSSize(width: 1500, height: 920))
            window.center()
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.minSize = NSSize(width: 1200, height: 720)
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

@main
struct TodayMdApp: App {
    @StateObject private var undoController = AppUndoController()
    let container: ModelContainer

    init() {
        let schema = Schema([TaskList.self, TaskItem.self, SubTask.self, TaskNote.self])
        let config = ModelConfiguration("TodayMdStore", schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-wal"))
            container = try! ModelContainer(for: schema, configurations: [config])
        }

        seedShowcaseDataIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(undoController)
                .background(MainWindowConfigurator())
        }
        .defaultSize(width: 1500, height: 920)
        .modelContainer(container)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Import...") {
                    TodayMdTransferService.importData(into: container.mainContext)
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])

                Button("Export...") {
                    TodayMdTransferService.exportData(from: container.mainContext)
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    undoController.undo()
                }
                .keyboardShortcut("z")

                Button("Redo") {
                    undoController.redo()
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            }
        }
    }

    private func seedShowcaseDataIfNeeded() {
        let context = ModelContext(container)
        let existingTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        guard existingTasks.isEmpty else { return }

        let existingLists = (try? context.fetch(FetchDescriptor<TaskList>())) ?? []

        let privateList: TaskList
        if let existingPrivate = existingLists.first(where: { $0.name.localizedCaseInsensitiveCompare("Private") == .orderedSame }) {
            privateList = existingPrivate
        } else {
            privateList = TaskList(name: "Private", icon: "person", color: .blue, sortOrder: 0)
            context.insert(privateList)
        }

        let workList: TaskList
        if let existingWork = existingLists.first(where: { $0.name.localizedCaseInsensitiveCompare("Work") == .orderedSame }) {
            workList = existingWork
        } else {
            workList = TaskList(name: "Work", icon: "briefcase", color: .purple, sortOrder: max(existingLists.count, 1))
            context.insert(workList)
        }

        seedPrivateTasks(in: context, list: privateList)
        seedWorkTasks(in: context, list: workList)

        try? context.save()
    }

    private func seedPrivateTasks(in context: ModelContext, list: TaskList) {
        makeTask(
            in: context,
            list: list,
            title: "Book dentist appointment",
            block: .today,
            sortOrder: 0,
            note: """
            Call the clinic and lock in a morning slot.

            - [x] Check insurance card
            - [ ] Call dentist office
            - [ ] Add appointment to calendar
            """,
            subtasks: [
                ("Find last checkup date", true),
                ("Ask about cleaning availability", false)
            ]
        )

        makeTask(
            in: context,
            list: list,
            title: "Buy groceries for dinner party",
            block: .today,
            sortOrder: 1,
            subtasks: [
                ("Fresh herbs", false),
                ("Dessert ingredients", false),
                ("Sparkling water", true)
            ]
        )

        makeTask(
            in: context,
            list: list,
            title: "Plan weekend trip to Hamburg",
            block: .thisWeek,
            sortOrder: 0,
            note: """
            Keep this lightweight and easy to book.

            - [x] Pick travel dates
            - [ ] Compare train options
            - [ ] Reserve hotel near the center
            """,
            subtasks: [
                ("Shortlist neighborhoods", true),
                ("Save restaurants to maps", false)
            ]
        )

        makeTask(
            in: context,
            list: list,
            title: "Declutter photo library",
            block: .backlog,
            sortOrder: 0
        )
    }

    private func seedWorkTasks(in context: ModelContext, list: TaskList) {
        makeTask(
            in: context,
            list: list,
            title: "Review onboarding polish PR",
            block: .today,
            sortOrder: 0,
            note: """
            Focus on final UX details before merge.

            - [x] Verify empty states
            - [ ] Check keyboard shortcuts
            - [ ] Confirm analytics events
            """,
            subtasks: [
                ("Leave review comments", false),
                ("Sync with design", true)
            ]
        )

        makeTask(
            in: context,
            list: list,
            title: "Prepare sprint planning notes",
            block: .today,
            sortOrder: 1,
            subtasks: [
                ("Summarize blocked work", false),
                ("Update capacity estimate", false)
            ]
        )

        makeTask(
            in: context,
            list: list,
            title: "Draft Q2 roadmap outline",
            block: .thisWeek,
            sortOrder: 0,
            note: """
            Keep the storyline clear for leadership review.

            - [x] Gather product inputs
            - [ ] Add milestone proposals
            - [ ] Flag team dependencies
            """
        )

        makeTask(
            in: context,
            list: list,
            title: "Clean up analytics backlog",
            block: .backlog,
            sortOrder: 0,
            subtasks: [
                ("Archive stale dashboard requests", false),
                ("Tag events needing owners", false)
            ]
        )
    }

    private func makeTask(
        in context: ModelContext,
        list: TaskList,
        title: String,
        block: TimeBlock,
        sortOrder: Int,
        note: String? = nil,
        subtasks: [(title: String, done: Bool)] = []
    ) {
        let task = TaskItem(title: title, block: block, sortOrder: sortOrder)
        task.list = list
        context.insert(task)

        if let note {
            let taskNote = TaskNote(content: note)
            taskNote.parentTask = task
            context.insert(taskNote)
        }

        for (index, subtask) in subtasks.enumerated() {
            let item = SubTask(title: subtask.title, isCompleted: subtask.done, sortOrder: index)
            item.parentTask = task
            context.insert(item)
        }
    }
}
