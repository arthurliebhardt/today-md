import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum TodayMdTransferService {
    private static var activePanel: NSOpenPanel?

    static func exportData(from context: ModelContext) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Export Tasks"
        panel.message = "Choose a folder for the JSON backup."
        panel.prompt = "Export Here"

        present(panel) { folderURL in
            guard let folderURL else { return }

            do {
                try exportData(from: context, to: folderURL)
            } catch {
                presentError(title: "Export Failed", error: error)
            }
        }
    }

    static func exportData(from context: ModelContext, to folderURL: URL) throws {
        try withSecurityScopedAccess(to: folderURL) {
            let exportURL = folderURL.appendingPathComponent(defaultExportFilename())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(makeArchive(from: context))
            try data.write(to: exportURL, options: .atomic)
        }
    }

    static func importData(into context: ModelContext) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Import Tasks"
        panel.message = "Choose the JSON backup file to import."
        panel.prompt = "Import File"

        present(panel) { url in
            guard let url else { return }

            do {
                guard let mode = chooseImportMode() else { return }
                try importData(into: context, from: url, mode: mode)
            } catch {
                presentError(title: "Import Failed", error: error)
            }
        }
    }

    static func importData(into context: ModelContext, from url: URL, mode: ImportMode) throws {
        try withSecurityScopedAccess(to: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try Data(contentsOf: url)
            let archive = try decoder.decode(TodayMdArchive.self, from: data)
            try applyImport(archive, into: context, mode: mode)
        }
    }

    private static func present(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
        activePanel = panel

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let url = response == .OK ? panel.url : nil
            activePanel = nil
            completion(url)
        }

        if let window = presentingWindow() {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: finish)
            return
        }

        finish(panel.runModal())
    }

    private static func presentingWindow() -> NSWindow? {
        NSApp.orderedWindows.first { window in
            window.isVisible && !(window is NSPanel)
        }
    }

    private static func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private static func makeArchive(from context: ModelContext) throws -> TodayMdArchive {
        let lists = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortOrder)]))
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())

        return TodayMdArchive(
            version: 1,
            exportedAt: Date(),
            lists: lists.map { list in
                TodayMdArchive.ListArchive(
                    name: list.name,
                    icon: list.icon,
                    colorName: list.colorName,
                    sortOrder: list.sortOrder,
                    tasks: list.items
                        .sorted(by: taskSort)
                        .map(makeTaskArchive)
                )
            },
            unassignedTasks: tasks
                .filter { $0.list == nil }
                .sorted(by: taskSort)
                .map(makeTaskArchive)
        )
    }

    private static func makeTaskArchive(_ task: TaskItem) -> TodayMdArchive.TaskArchive {
        TodayMdArchive.TaskArchive(
            title: task.title,
            isDone: task.isDone,
            blockRaw: task.blockRaw,
            sortOrder: task.sortOrder,
            creationDate: task.creationDate,
            note: task.note.map {
                TodayMdArchive.NoteArchive(
                    content: $0.content,
                    lastModified: $0.lastModified
                )
            },
            subtasks: task.subtasks
                .sorted { $0.sortOrder < $1.sortOrder }
                .map {
                    TodayMdArchive.SubTaskArchive(
                        title: $0.title,
                        isCompleted: $0.isCompleted,
                        sortOrder: $0.sortOrder
                    )
                }
        )
    }

    private static func applyImport(_ archive: TodayMdArchive, into context: ModelContext, mode: ImportMode) throws {
        if mode == .replaceExisting {
            try clearExistingData(in: context)
        }

        let existingLists = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortOrder)]))
        let existingTasks = try context.fetch(FetchDescriptor<TaskItem>())

        let listSortBase = ((existingLists.map(\.sortOrder).max() ?? -1) + 1)
        let taskSortBase = ((existingTasks.filter { $0.list == nil }.map(\.sortOrder).max() ?? -1) + 1)

        for (index, listArchive) in archive.lists.enumerated() {
            let list = TaskList(
                name: listArchive.name,
                icon: listArchive.icon,
                color: ListColor(rawValue: listArchive.colorName) ?? .blue,
                sortOrder: mode == .replaceExisting ? listArchive.sortOrder : listSortBase + index
            )
            context.insert(list)

            for taskArchive in listArchive.tasks {
                insertTask(from: taskArchive, into: context, list: list, sortOrder: taskArchive.sortOrder)
            }
        }

        for (index, taskArchive) in archive.unassignedTasks.enumerated() {
            let sortOrder = mode == .replaceExisting ? taskArchive.sortOrder : taskSortBase + index
            insertTask(from: taskArchive, into: context, list: nil, sortOrder: sortOrder)
        }

        try context.save()
    }

    private static func insertTask(
        from archive: TodayMdArchive.TaskArchive,
        into context: ModelContext,
        list: TaskList?,
        sortOrder: Int
    ) {
        let task = TaskItem(
            title: archive.title,
            block: TimeBlock(rawValue: archive.blockRaw) ?? .backlog,
            sortOrder: sortOrder
        )
        task.isDone = archive.isDone
        task.creationDate = archive.creationDate
        task.list = list
        context.insert(task)

        if let noteArchive = archive.note {
            let note = TaskNote(content: noteArchive.content)
            note.lastModified = noteArchive.lastModified
            note.parentTask = task
            context.insert(note)
        }

        for subtaskArchive in archive.subtasks {
            let subtask = SubTask(
                title: subtaskArchive.title,
                isCompleted: subtaskArchive.isCompleted,
                sortOrder: subtaskArchive.sortOrder
            )
            subtask.parentTask = task
            context.insert(subtask)
        }
    }

    private static func clearExistingData(in context: ModelContext) throws {
        let allTasks = try context.fetch(FetchDescriptor<TaskItem>())
        let allLists = try context.fetch(FetchDescriptor<TaskList>())

        for task in allTasks where task.list == nil {
            context.delete(task)
        }

        for list in allLists {
            context.delete(list)
        }
    }

    private static func chooseImportMode() -> ImportMode? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Import Tasks"
        alert.informativeText = "Choose whether to merge the imported data into your existing lists or replace everything currently in the app."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace Existing")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .replaceExisting
        default:
            return nil
        }
    }

    private static func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.runModal()
    }

    private static func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "today-md-backup-\(formatter.string(from: Date())).json"
    }

    private static func taskSort(lhs: TaskItem, rhs: TaskItem) -> Bool {
        let lhsTuple = (blockRank(lhs.block), lhs.sortOrder, lhs.creationDate)
        let rhsTuple = (blockRank(rhs.block), rhs.sortOrder, rhs.creationDate)
        return lhsTuple < rhsTuple
    }

    private static func blockRank(_ block: TimeBlock) -> Int {
        switch block {
        case .today:
            return 0
        case .thisWeek:
            return 1
        case .backlog:
            return 2
        }
    }
}

enum ImportMode {
    case merge
    case replaceExisting
}

private struct TodayMdArchive: Codable {
    let version: Int
    let exportedAt: Date
    let lists: [ListArchive]
    let unassignedTasks: [TaskArchive]

    struct ListArchive: Codable {
        let name: String
        let icon: String
        let colorName: String
        let sortOrder: Int
        let tasks: [TaskArchive]
    }

    struct TaskArchive: Codable {
        let title: String
        let isDone: Bool
        let blockRaw: String
        let sortOrder: Int
        let creationDate: Date
        let note: NoteArchive?
        let subtasks: [SubTaskArchive]
    }

    struct NoteArchive: Codable {
        let content: String
        let lastModified: Date
    }

    struct SubTaskArchive: Codable {
        let title: String
        let isCompleted: Bool
        let sortOrder: Int
    }
}
