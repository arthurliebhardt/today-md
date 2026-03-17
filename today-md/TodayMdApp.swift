import AppKit
import SwiftUI

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NSApp.setActivationPolicy(.regular)
            window.minSize = NSSize(width: 1200, height: 720)
            window.setContentSize(NSSize(width: 1500, height: 920))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
    @State private var store = TodayMdStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environmentObject(undoController)
                .background(MainWindowConfigurator())
                .onAppear {
                    store.configureUndoManager(undoController.manager)
                }
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Import...") {
                    TodayMdTransferService.importData(into: store)
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])

                Button("Export...") {
                    TodayMdTransferService.exportData(from: store)
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
}

@MainActor
@Observable
final class TodayMdStore {
    private let database: TodayMdDatabase
    private(set) var lists: [TaskList] = []
    private(set) var unassignedTasks: [TaskItem] = []
    private(set) var dataRevision = 0
    private(set) var persistedSearchIDs: [UUID] = []
    var searchText = "" {
        didSet { refreshSearch() }
    }

    @ObservationIgnored
    private var undoManager: UndoManager?

    init() {
        do {
            database = try TodayMdDatabase(url: Self.defaultDatabaseURL())
            let archive = try database.loadArchive()
            applyArchive(archive, refreshSearch: false)
            if removeLegacySubtasksIfNeeded() {
                persist()
            }

            if allTasks.isEmpty {
                seedShowcaseDataIfNeeded()
            } else {
                refreshSearch()
            }
        } catch {
            fatalError("Failed to initialize store: \(error.localizedDescription)")
        }
    }

    var allTasks: [TaskItem] {
        (lists.flatMap(\.items) + unassignedTasks)
            .sorted(by: taskSort)
    }

    var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func configureUndoManager(_ manager: UndoManager) {
        undoManager = manager
    }

    func list(id: UUID) -> TaskList? {
        lists.first(where: { $0.id == id })
    }

    func task(id: UUID) -> TaskItem? {
        allTasks.first(where: { $0.id == id })
    }

    func filteredTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        guard hasActiveSearch else { return tasks }
        let matchingIDs = Set(persistedSearchIDs)
        return tasks.filter { matchingIDs.contains($0.id) }
    }

    func rankedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        guard hasActiveSearch else { return tasks }
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        return persistedSearchIDs.compactMap { tasksByID[$0] }
    }

    func addList(name: String, icon: String, color: ListColor) -> TaskList {
        let list = TaskList(name: name, icon: icon, color: color, sortOrder: lists.count)
        performMutation(actionName: "Add List") {
            lists.append(list)
        }
        return list
    }

    func updateList(id: UUID, name: String, icon: String, color: ListColor) {
        guard let list = list(id: id) else { return }
        performMutation(actionName: "Edit List") {
            list.name = name
            list.icon = icon
            list.listColor = color
        }
    }

    func deleteList(id: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        performMutation(actionName: "Delete List") {
            lists.remove(at: index)
            normalizeListSortOrder()
        }
    }

    func addTask(title: String, block: TimeBlock, listID: UUID) -> TaskItem? {
        guard let list = list(id: listID) else { return nil }
        let task = TaskItem(title: title, block: block, sortOrder: nextSortOrder(for: list, in: block))
        task.list = list

        performMutation(actionName: "Add Task") {
            list.items.append(task)
        }

        return task
    }

    func moveTask(id: UUID, to block: TimeBlock) {
        guard let task = task(id: id) else { return }
        let previousBlock = task.block
        guard previousBlock != block else { return }

        performMutation(actionName: "Move Task") {
            task.block = block
            task.sortOrder = nextSortOrder(for: task.list, in: block)
            normalizeSortOrder(for: task.list, in: previousBlock)
            normalizeSortOrder(for: task.list, in: block)
        }
    }

    func deleteTask(id: UUID) {
        guard let task = task(id: id) else { return }

        performMutation(actionName: "Delete Task") {
            if let list = task.list {
                list.items.removeAll { $0.id == id }
                normalizeSortOrder(for: list, in: task.block)
            } else {
                unassignedTasks.removeAll { $0.id == id }
                normalizeSortOrder(for: nil, in: task.block)
            }
        }
    }

    func toggleTask(id: UUID) {
        guard let task = task(id: id) else { return }
        performMutation(actionName: task.isDone ? "Mark Task Incomplete" : "Complete Task") {
            task.isDone.toggle()
        }
    }

    func reorderAllActiveTask(_ draggedID: UUID, before beforeID: UUID?) {
        if beforeID == draggedID { return }

        performMutation(actionName: "Reorder Tasks") {
            var active = allTasks.filter { !$0.isDone }.sorted(by: taskSort)
            let done = allTasks.filter(\.isDone).sorted(by: taskSort)

            guard let draggedIndex = active.firstIndex(where: { $0.id == draggedID }) else { return }
            let draggedTask = active.remove(at: draggedIndex)

            let insertIndex: Int
            if let beforeID,
               let targetIndex = active.firstIndex(where: { $0.id == beforeID }) {
                insertIndex = targetIndex
            } else {
                insertIndex = active.count
            }

            active.insert(draggedTask, at: insertIndex)
            applyGlobalSortOrder(active + done)
        }
    }

    func reorderTaskInListBlock(listID: UUID, draggedID: UUID, block: TimeBlock, before beforeID: UUID?) {
        if beforeID == draggedID { return }
        guard let list = list(id: listID),
              let draggedTask = list.items.first(where: { $0.id == draggedID }),
              !draggedTask.isDone
        else {
            return
        }

        performMutation(actionName: "Move Task") {
            let previousBlock = draggedTask.block

            if draggedTask.block != block {
                draggedTask.block = block
                draggedTask.sortOrder = nextSortOrder(for: list, in: block)
            }

            var active = list.items
                .filter { $0.block == block && !$0.isDone }
                .sorted { $0.sortOrder < $1.sortOrder }

            guard let draggedIndex = active.firstIndex(where: { $0.id == draggedID }) else { return }
            let moving = active.remove(at: draggedIndex)

            let insertIndex: Int
            if let beforeID,
               let targetIndex = active.firstIndex(where: { $0.id == beforeID }) {
                insertIndex = targetIndex
            } else {
                insertIndex = active.count
            }

            active.insert(moving, at: insertIndex)

            let done = list.items
                .filter { $0.block == block && $0.isDone }
                .sorted { $0.sortOrder < $1.sortOrder }

            applySortOrder(active + done)

            if previousBlock != block {
                normalizeSortOrder(for: list, in: previousBlock)
            }
        }
    }

    func updateTaskTitle(id: UUID, title: String, registersUndo: Bool = false) {
        guard let task = task(id: id), task.title != title else { return }
        performMutation(actionName: "Edit Task", registersUndo: registersUndo) {
            task.title = title
        }
    }

    func updateTaskNote(id: UUID, content: String, registersUndo: Bool = false) {
        guard let task = task(id: id) else { return }
        let normalized = content

        performMutation(actionName: "Edit Note", registersUndo: registersUndo) {
            if normalized.isEmpty {
                task.note = nil
            } else if let note = task.note {
                note.content = normalized
                note.lastModified = Date()
            } else {
                task.note = TaskNote(content: normalized)
            }
        }
    }

    func toggleChecklistItem(taskID: UUID, lineIndex: Int) {
        guard let task = task(id: taskID),
              let item = task.checklistItems.first(where: { $0.lineIndex == lineIndex })
        else {
            return
        }

        let mappedSubtaskID = task.mappedSubtaskID(forChecklistLineIndex: lineIndex)
        let nextCheckedState = !item.isChecked

        performMutation(actionName: nextCheckedState ? "Complete Checklist Item" : "Mark Checklist Item Incomplete") {
            setChecklistItem(in: task, lineIndex: lineIndex, isChecked: nextCheckedState)

            if let mappedSubtaskID,
               let subtask = task.subtasks.first(where: { $0.id == mappedSubtaskID }) {
                subtask.isCompleted = nextCheckedState
            }
        }
    }

    func removeChecklistItem(taskID: UUID, lineIndex: Int) {
        guard let task = task(id: taskID) else { return }
        let mappedSubtaskID = task.mappedSubtaskID(forChecklistLineIndex: lineIndex)

        performMutation(actionName: "Delete Checklist Item") {
            removeChecklistLine(in: task, lineIndex: lineIndex)

            if let mappedSubtaskID {
                task.subtasks.removeAll { $0.id == mappedSubtaskID }
                normalizeSubtaskSortOrder(in: task)
            }
        }
    }

    func addChecklistItem(taskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let task = task(id: taskID) else { return }

        performMutation(actionName: "Add Checklist Item") {
            appendChecklistLine(to: task, title: trimmed)
            task.subtasks.append(
                SubTask(title: trimmed, sortOrder: task.subtasks.count)
            )
        }
    }

    func addSubtask(taskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let task = task(id: taskID) else { return }

        performMutation(actionName: "Add Subtask") {
            task.subtasks.append(
                SubTask(title: trimmed, sortOrder: task.subtasks.count)
            )
            appendChecklistLine(to: task, title: trimmed)
        }
    }

    func toggleSubtask(taskID: UUID, subtaskID: UUID) {
        guard let task = task(id: taskID),
              let subtask = task.subtasks.first(where: { $0.id == subtaskID })
        else {
            return
        }

        let mappedLineIndex = task.mappedChecklistLineIndex(for: subtaskID)
        let nextCompletedState = !subtask.isCompleted

        performMutation(actionName: nextCompletedState ? "Complete Subtask" : "Mark Subtask Incomplete") {
            subtask.isCompleted = nextCompletedState

            if let mappedLineIndex {
                setChecklistItem(in: task, lineIndex: mappedLineIndex, isChecked: nextCompletedState)
            }
        }
    }

    func deleteSubtask(taskID: UUID, subtaskID: UUID) {
        guard let task = task(id: taskID) else { return }
        let mappedLineIndex = task.mappedChecklistLineIndex(for: subtaskID)

        performMutation(actionName: "Delete Subtask") {
            task.subtasks.removeAll { $0.id == subtaskID }

            if let mappedLineIndex {
                removeChecklistLine(in: task, lineIndex: mappedLineIndex)
            }

            normalizeSubtaskSortOrder(in: task)
        }
    }

    func applyImport(_ archive: TodayMdArchive, mode: ImportMode) {
        performMutation(actionName: mode == .merge ? "Import Tasks" : "Replace Tasks") {
            if mode == .replaceExisting {
                let hydrated = archive.instantiate()
                lists = hydrated.lists
                unassignedTasks = hydrated.unassignedTasks
                return
            }

            let hydrated = archive.instantiate()
            let listSortBase = (lists.map(\.sortOrder).max() ?? -1) + 1
            for (index, list) in hydrated.lists.enumerated() {
                list.sortOrder = listSortBase + index
                lists.append(list)
            }

            let taskSortBase = (unassignedTasks.map(\.sortOrder).max() ?? -1) + 1
            for (index, task) in hydrated.unassignedTasks.enumerated() {
                task.sortOrder = taskSortBase + index
                unassignedTasks.append(task)
            }
        }
    }

    func makeArchive() -> TodayMdArchive {
        TodayMdArchive(lists: lists, unassignedTasks: unassignedTasks)
    }

    private func seedShowcaseDataIfNeeded() {
        let privateList = TaskList(name: "Private", icon: "person", color: .blue, sortOrder: 0)
        let workList = TaskList(name: "Work", icon: "briefcase", color: .purple, sortOrder: 1)

        lists = [privateList, workList]

        seedPrivateTasks(in: privateList)
        seedWorkTasks(in: workList)
        persist()
        refreshSearch()
        dataRevision += 1
    }

    private func seedPrivateTasks(in list: TaskList) {
        makeTask(
            list: list,
            title: "Book dentist appointment",
            block: .today,
            sortOrder: 0,
            note: """
            Call the clinic and lock in a morning slot.

            - [x] Check insurance card
            - [ ] Call dentist office
            - [ ] Add appointment to calendar
            """
        )

        makeTask(
            list: list,
            title: "Buy groceries for dinner party",
            block: .today,
            sortOrder: 1
        )

        makeTask(
            list: list,
            title: "Plan weekend trip to Hamburg",
            block: .thisWeek,
            sortOrder: 0,
            note: """
            Keep this lightweight and easy to book.

            - [x] Pick travel dates
            - [ ] Compare train options
            - [ ] Reserve hotel near the center
            """
        )

        makeTask(
            list: list,
            title: "Declutter photo library",
            block: .backlog,
            sortOrder: 0
        )
    }

    private func seedWorkTasks(in list: TaskList) {
        makeTask(
            list: list,
            title: "Review onboarding polish PR",
            block: .today,
            sortOrder: 0,
            note: """
            Focus on final UX details before merge.

            - [x] Verify empty states
            - [ ] Check keyboard shortcuts
            - [ ] Confirm analytics events
            """
        )

        makeTask(
            list: list,
            title: "Draft release notes for v1.2",
            block: .today,
            sortOrder: 1
        )

        makeTask(
            list: list,
            title: "Prepare Q2 roadmap outline",
            block: .thisWeek,
            sortOrder: 0,
            note: """
            Keep this at a theme level before turning it into a slide deck.

            - [ ] Gather feedback from sales
            - [ ] Summarize open platform bets
            - [ ] Draft rough milestones
            """
        )

        makeTask(
            list: list,
            title: "Evaluate new analytics vendor",
            block: .backlog,
            sortOrder: 0
        )
    }

    private func makeTask(
        list: TaskList,
        title: String,
        block: TimeBlock,
        sortOrder: Int,
        note: String? = nil
    ) {
        let task = TaskItem(
            title: title,
            block: block,
            sortOrder: sortOrder,
            note: note.map { TaskNote(content: $0) }
        )
        task.list = list
        list.items.append(task)
    }

    private func removeLegacySubtasksIfNeeded() -> Bool {
        var didChange = false

        for task in allTasks where !task.subtasks.isEmpty {
            let mappedLineIndices = task.subtasks
                .compactMap { task.mappedChecklistLineIndex(for: $0.id) }
                .sorted(by: >)

            if let note = task.note, !mappedLineIndices.isEmpty {
                var lines = note.content.components(separatedBy: "\n")

                for lineIndex in mappedLineIndices where lineIndex < lines.count {
                    lines.remove(at: lineIndex)
                }

                if lines.isEmpty {
                    task.note = nil
                } else {
                    note.content = lines.joined(separator: "\n")
                    note.lastModified = Date()
                }

                didChange = true
            }

            task.subtasks.removeAll()
            didChange = true
        }

        return didChange
    }

    private func performMutation(actionName: String, registersUndo: Bool = true, _ change: () -> Void) {
        let previous = registersUndo ? makeArchive() : nil
        change()
        persist()
        refreshSearch()
        dataRevision += 1

        guard registersUndo, let previous else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(from: previous, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func restore(from archive: TodayMdArchive, actionName: String) {
        let current = makeArchive()
        applyArchive(archive, refreshSearch: true)
        persist()
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(from: current, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func applyArchive(_ archive: TodayMdArchive, refreshSearch shouldRefreshSearch: Bool) {
        let hydrated = archive.instantiate()
        lists = hydrated.lists
        unassignedTasks = hydrated.unassignedTasks
        dataRevision += 1

        if shouldRefreshSearch {
            refreshSearch()
        }
    }

    private func persist() {
        do {
            try database.replaceAll(with: makeArchive())
        } catch {
            assertionFailure("Failed to persist store: \(error.localizedDescription)")
        }
    }

    private func appendChecklistLine(to task: TaskItem, title: String) {
        let entry = "- [ ] \(title)"

        if let note = task.note {
            note.content = note.content.isEmpty ? entry : "\(note.content)\n\(entry)"
            note.lastModified = Date()
        } else {
            task.note = TaskNote(content: entry)
        }
    }

    private func setChecklistItem(in task: TaskItem, lineIndex: Int, isChecked: Bool) {
        guard let note = task.note else { return }
        var lines = note.content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }

        let title = task.checklistItems.first(where: { $0.lineIndex == lineIndex })?.title
            ?? lines[lineIndex]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "- [ ] ", with: "")
                .replacingOccurrences(of: "- [x] ", with: "")
                .replacingOccurrences(of: "- [X] ", with: "")

        lines[lineIndex] = isChecked ? "- [x] \(title)" : "- [ ] \(title)"
        note.content = lines.joined(separator: "\n")
        note.lastModified = Date()
    }

    private func removeChecklistLine(in task: TaskItem, lineIndex: Int) {
        guard let note = task.note else { return }
        var lines = note.content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }

        lines.remove(at: lineIndex)

        if lines.isEmpty {
            task.note = nil
        } else {
            note.content = lines.joined(separator: "\n")
            note.lastModified = Date()
        }
    }

    private func refreshSearch() {
        guard hasActiveSearch else {
            persistedSearchIDs = []
            return
        }

        do {
            persistedSearchIDs = try database.searchTaskIDs(matching: searchText)
        } catch {
            persistedSearchIDs = []
            assertionFailure("Search failed: \(error.localizedDescription)")
        }
    }

    private func normalizeListSortOrder() {
        for (index, list) in lists.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            list.sortOrder = index
        }
    }

    private func normalizeSubtaskSortOrder(in task: TaskItem) {
        for (index, subtask) in task.subtasks.enumerated() {
            subtask.sortOrder = index
        }
    }

    private func nextSortOrder(for list: TaskList?, in block: TimeBlock) -> Int {
        let tasks = list?.items ?? unassignedTasks
        return tasks
            .filter { $0.block == block }
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
    }

    private func normalizeSortOrder(for list: TaskList?, in block: TimeBlock) {
        let tasks = (list?.items ?? unassignedTasks)
            .filter { $0.block == block }
            .sorted { $0.sortOrder < $1.sortOrder }
        applySortOrder(tasks)
    }

    private func applySortOrder(_ tasks: [TaskItem]) {
        for (index, task) in tasks.enumerated() where task.sortOrder != index {
            task.sortOrder = index
        }
    }

    private func applyGlobalSortOrder(_ tasks: [TaskItem]) {
        for (index, task) in tasks.enumerated() {
            task.sortOrder = index
        }
    }

    private static func defaultDatabaseURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.applicationSupportUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent("today-md", isDirectory: true)
            .appendingPathComponent("today-md.sqlite", isDirectory: false)
    }
}

private enum StoreError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The Application Support folder is unavailable."
        }
    }
}
