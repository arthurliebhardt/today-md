import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case all
    case list(TaskList)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.sortOrder) private var allTasks: [TaskItem]
    @State private var selection: SidebarSelection = .all
    @State private var selectedTask: TaskItem?

    private func listTasks(for block: TimeBlock) -> [TaskItem] {
        guard case .list(let list) = selection else { return [] }
        return list.items.filter { $0.block == block }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            Group {
                if case .all = selection {
                    AllTasksView(
                        selectedTask: $selectedTask,
                        onDelete: deleteTask,
                        onToggle: toggleTask,
                        onReorderActive: reorderActiveTask
                    )
                } else {
                    BoardView(
                        tasks: listTasks,
                        selectedTask: $selectedTask,
                        onAdd: addTask,
                        onMove: moveTask,
                        onReorderInBlock: reorderTaskInCurrentListBlock,
                        onDelete: deleteTask,
                        onToggle: toggleTask
                    )
                }
            }
            .navigationTitle(boardTitle)
        } detail: {
            if let task = selectedTask {
                TaskDetailView(task: task, onDelete: deleteTask)
            } else {
                ContentUnavailableView("Select a Task", systemImage: "checkmark.circle", description: Text("Click a task to view details."))
            }
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 800, minHeight: 500)
        .onDeleteCommand {
            if let task = selectedTask { deleteTask(task) }
        }
    }

    private var boardTitle: String {
        switch selection {
        case .all: return "All Tasks"
        case .list(let l): return l.name
        }
    }

    private func addTask(title: String, block: TimeBlock) {
        guard case .list(let list) = selection else { return }
        let task = TaskItem(title: title, block: block, sortOrder: listTasks(for: block).count)
        task.list = list
        modelContext.insert(task)
        selectedTask = task
    }

    private func moveTask(id: UUID, to block: TimeBlock) {
        guard let task = allTasks.first(where: { $0.id == id }) else { return }
        if task.block == block { return }
        let previousBlock = task.block
        task.block = block

        guard case .list(let list) = selection else { return }

        normalizeSortOrder(for: list, in: previousBlock)
        normalizeSortOrder(for: list, in: block)
    }

    private func deleteTask(_ task: TaskItem) {
        if selectedTask == task { selectedTask = nil }
        modelContext.delete(task)
    }

    private func toggleTask(_ task: TaskItem) {
        task.isDone.toggle()
    }

    private func reorderActiveTask(_ draggedID: UUID, _ beforeID: UUID?) {
        if beforeID == draggedID { return }

        var active = allTasks
            .filter { !$0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let draggedIndex = active.firstIndex(where: { $0.id == draggedID }) else { return }
        let draggedTask = active.remove(at: draggedIndex)

        let insertIndex: Int
        if let beforeID,
           let idx = active.firstIndex(where: { $0.id == beforeID }) {
            insertIndex = idx
        } else {
            insertIndex = active.count
        }

        active.insert(draggedTask, at: insertIndex)

        let done = allTasks
            .filter { $0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }

        let reordered = active + done
        for (index, task) in reordered.enumerated() {
            task.sortOrder = index
        }
    }

    private func reorderTaskInCurrentListBlock(_ draggedID: UUID, _ block: TimeBlock, _ beforeID: UUID?) {
        if beforeID == draggedID { return }
        guard case .list(let list) = selection else { return }
        guard let draggedTask = list.items.first(where: { $0.id == draggedID }) else { return }
        guard !draggedTask.isDone else { return }

        let previousBlock = draggedTask.block
        if draggedTask.block != block {
            draggedTask.block = block
        }

        var active = list.items
            .filter { $0.block == block && !$0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let draggedIndex = active.firstIndex(where: { $0.id == draggedID }) else { return }
        let moving = active.remove(at: draggedIndex)

        let insertIndex: Int
        if let beforeID,
           let idx = active.firstIndex(where: { $0.id == beforeID }) {
            insertIndex = idx
        } else {
            insertIndex = active.count
        }

        active.insert(moving, at: insertIndex)

        let done = list.items
            .filter { $0.block == block && $0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }

        let reordered = active + done
        for (index, task) in reordered.enumerated() {
            task.sortOrder = index
        }

        if previousBlock != block {
            normalizeSortOrder(for: list, in: previousBlock)
        }
    }

    private func normalizeSortOrder(for list: TaskList, in block: TimeBlock) {
        let ordered = list.items
            .filter { $0.block == block }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, task) in ordered.enumerated() {
            task.sortOrder = index
        }
    }
}
