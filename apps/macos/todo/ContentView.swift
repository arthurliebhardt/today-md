import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case list(TaskList)
}

private struct TaskPlacementSnapshot: Equatable {
    let id: UUID
    let block: TimeBlock
    let sortOrder: Int
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var undoController: AppUndoController
    @Query(sort: \TaskItem.sortOrder) private var allTasks: [TaskItem]
    @Query(sort: \TaskList.sortOrder) private var allLists: [TaskList]
    @State private var selection: SidebarSelection = .all
    @State private var selectedTask: TaskItem?
    @State private var showingSettingsSheet = false
    @State private var showingImportPicker = false
    @State private var showingExportPicker = false
    @State private var pendingImportURL: URL?
    @State private var showingImportModeDialog = false
    @State private var transferAlert: TransferAlert?

    private func listTasks(for block: TimeBlock) -> [TaskItem] {
        guard case .list(let list) = selection else { return [] }
        return list.items.filter { $0.block == block }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func startImport() {
        showingSettingsSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingImportPicker = true
        }
    }

    private func startExport() {
        showingSettingsSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingExportPicker = true
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingImportURL = url
            showingImportModeDialog = true
        case .failure(let error):
            presentTransferError(title: "Import Failed", error: error)
        }
    }

    private func handleExportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let folderURL):
            do {
                try TodoTransferService.exportData(from: modelContext, to: folderURL)
            } catch {
                presentTransferError(title: "Export Failed", error: error)
            }
        case .failure(let error):
            presentTransferError(title: "Export Failed", error: error)
        }
    }

    private func confirmImport(mode: ImportMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil

        do {
            try TodoTransferService.importData(into: modelContext, from: url, mode: mode)
        } catch {
            presentTransferError(title: "Import Failed", error: error)
        }
    }

    private func presentTransferError(title: String, error: Error) {
        transferAlert = TransferAlert(
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }

    private var settingsSheetView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.09),
                    Color.blue.opacity(0.06),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.95), Color.orange.opacity(0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.orange.opacity(0.18), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold))

                        Text("Manage backups now and leave room for app preferences, shortcuts, and workflow options later.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Workspace")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Data & Backup")
                        .font(.headline)

                    VStack(spacing: 12) {
                        settingsActionCard(
                            title: "Import Backup",
                            subtitle: "Select a JSON backup file and merge it or replace the current data.",
                            systemImage: "square.and.arrow.down",
                            tint: .blue,
                            action: startImport
                        )

                        settingsActionCard(
                            title: "Export Backup",
                            subtitle: "Choose a folder and create a timestamped JSON backup of everything in the app.",
                            systemImage: "square.and.arrow.up",
                            tint: .orange,
                            action: startExport
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Coming Next")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        settingsFutureRow(
                            title: "Appearance",
                            subtitle: "Theme, density, and board presentation."
                        )
                        settingsFutureRow(
                            title: "Behavior",
                            subtitle: "Default task placement, archive rules, and import preferences."
                        )
                        settingsFutureRow(
                            title: "Shortcuts",
                            subtitle: "Keyboard controls and quick actions."
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.16), lineWidth: 1)
                    )
                }

                HStack {
                    Text("More settings can slot into these sections without changing the layout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Close") {
                        showingSettingsSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
            .frame(width: 540)
        }
    }

    private func settingsActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.14))

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsFutureRow(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            Group {
                if case .all = selection {
                    AllTasksView(
                        selectedTask: $selectedTask,
                        onMove: moveTask,
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
                TaskDetailView(task: task, onToggle: toggleTask, onDelete: deleteTask)
            } else {
                ContentUnavailableView("Select a Task", systemImage: "checkmark.circle", description: Text("Click a task to view details."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings")

                Button {
                    undoController.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .help("Undo the last change")

                Button {
                    undoController.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .help("Redo the last undone change")
            }
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingSettingsSheet) {
            settingsSheetView
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json]
        ) { result in
            handleImportSelection(result)
        }
        .fileImporter(
            isPresented: $showingExportPicker,
            allowedContentTypes: [.folder]
        ) { result in
            handleExportSelection(result)
        }
        .confirmationDialog(
            "Import Tasks",
            isPresented: $showingImportModeDialog,
            titleVisibility: .visible
        ) {
            Button("Merge") {
                confirmImport(mode: .merge)
            }

            Button("Replace Existing") {
                confirmImport(mode: .replaceExisting)
            }

            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("Choose whether to merge the imported data into your existing lists or replace everything currently in the app.")
        }
        .alert(item: $transferAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message)
            )
        }
        .onAppear {
            modelContext.undoManager = undoController.manager
        }
        .onChange(of: allTasks.map(\.id), initial: true) { _, taskIDs in
            guard let selectedTask else { return }
            if !taskIDs.contains(selectedTask.id) {
                self.selectedTask = nil
            }
        }
        .onChange(of: allLists.map(\.persistentModelID), initial: false) { _, lists in
            guard case .list(let currentList) = selection else { return }
            if !lists.contains(currentList.persistentModelID) {
                selection = .all
            }
        }
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
        performModelChange(actionName: "Add Task") {
            modelContext.insert(task)
        }
        selectedTask = task
    }

    private func moveTask(id: UUID, to block: TimeBlock) {
        guard let task = allTasks.first(where: { $0.id == id }) else { return }
        let previousBlock = task.block
        guard previousBlock != block else { return }

        if let list = task.list {
            performPlacementChange(actionName: "Move Task", tasks: list.items) {
                task.block = block
                task.sortOrder = nextSortOrder(for: list, in: block)
                normalizeSortOrder(for: list, in: previousBlock)
            }
        } else {
            performPlacementChange(actionName: "Move Task", tasks: allTasks) {
                task.block = block
                task.sortOrder = nextGlobalSortOrder(in: block)
                normalizeGlobalSortOrder(in: previousBlock)
                normalizeGlobalSortOrder(in: block)
            }
        }
    }

    private func deleteTask(_ task: TaskItem) {
        if selectedTask == task { selectedTask = nil }
        performModelChange(actionName: "Delete Task") {
            modelContext.delete(task)
        }
    }

    private func toggleTask(_ task: TaskItem) {
        performModelChange(actionName: task.isDone ? "Mark Task Incomplete" : "Complete Task") {
            task.isDone.toggle()
        }
    }

    private func reorderActiveTask(_ draggedID: UUID, _ beforeID: UUID?) {
        if beforeID == draggedID { return }

        performPlacementChange(actionName: "Reorder Tasks", tasks: allTasks) {
            var active = allTasks
                .filter { !$0.isDone }
                .sorted { $0.sortOrder < $1.sortOrder }

            let done = allTasks
                .filter { $0.isDone }
                .sorted { $0.sortOrder < $1.sortOrder }
            let originalOrder = (active + done).map(\.id)

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

            let reordered = active + done
            guard reordered.map(\.id) != originalOrder else { return }

            applySortOrder(reordered)
        }
    }

    private func reorderTaskInCurrentListBlock(_ draggedID: UUID, _ block: TimeBlock, _ beforeID: UUID?) {
        if beforeID == draggedID { return }
        guard case .list(let list) = selection else { return }
        guard let draggedTask = list.items.first(where: { $0.id == draggedID }) else { return }
        guard !draggedTask.isDone else { return }

        performPlacementChange(actionName: "Move Task", tasks: list.items) {
            let previousBlock = draggedTask.block
            let originalOrder = list.items
                .filter { $0.block == block }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.id)

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
            if reordered.map(\.id) != originalOrder {
                applySortOrder(reordered)
            }

            if previousBlock != block {
                normalizeSortOrder(for: list, in: previousBlock)
            }
        }
    }

    private func normalizeSortOrder(for list: TaskList, in block: TimeBlock) {
        let ordered = list.items
            .filter { $0.block == block }
            .sorted { $0.sortOrder < $1.sortOrder }

        applySortOrder(ordered)
    }

    private func normalizeGlobalSortOrder(in block: TimeBlock) {
        let ordered = allTasks
            .filter { $0.list == nil && $0.block == block }
            .sorted { $0.sortOrder < $1.sortOrder }

        applySortOrder(ordered)
    }

    private func nextSortOrder(for list: TaskList, in block: TimeBlock) -> Int {
        list.items
            .filter { $0.block == block }
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
    }

    private func nextGlobalSortOrder(in block: TimeBlock) -> Int {
        allTasks
            .filter { $0.list == nil && $0.block == block }
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
    }

    private func applySortOrder(_ tasks: [TaskItem]) {
        for (index, task) in tasks.enumerated() where task.sortOrder != index {
            task.sortOrder = index
        }
    }

    private func performPlacementChange(actionName: String, tasks: [TaskItem], change: () -> Void) {
        let before = snapshot(for: tasks)
        let undoManager = undoController.manager
        let wasUndoRegistrationEnabled = undoManager.isUndoRegistrationEnabled

        if wasUndoRegistrationEnabled {
            undoManager.disableUndoRegistration()
        }

        change()

        if wasUndoRegistrationEnabled {
            undoManager.enableUndoRegistration()
        }

        let after = snapshot(for: tasks)
        guard after != before else { return }

        registerPlacementUndo(actionName: actionName, snapshots: before)
    }

    private func performModelChange(actionName: String, change: () -> Void) {
        change()
        undoController.manager.setActionName(actionName)
    }

    private func registerPlacementUndo(actionName: String, snapshots: [TaskPlacementSnapshot]) {
        undoController.manager.registerUndo(withTarget: modelContext) { context in
            Self.restorePlacements(in: context, snapshots: snapshots, actionName: actionName)
        }
        undoController.manager.setActionName(actionName)
    }

    private func snapshot(for tasks: [TaskItem]) -> [TaskPlacementSnapshot] {
        tasks
            .map { TaskPlacementSnapshot(id: $0.id, block: $0.block, sortOrder: $0.sortOrder) }
            .sorted { lhs, rhs in
                lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private static func restorePlacements(in context: ModelContext, snapshots: [TaskPlacementSnapshot], actionName: String) {
        let current = Self.snapshots(for: snapshots, in: context)
        let undoManager = context.undoManager
        let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled ?? false

        undoManager?.registerUndo(withTarget: context) { context in
            restorePlacements(in: context, snapshots: current, actionName: actionName)
        }
        undoManager?.setActionName(actionName)

        if wasUndoRegistrationEnabled {
            undoManager?.disableUndoRegistration()
        }

        applyPlacements(snapshots, in: context)

        if wasUndoRegistrationEnabled {
            undoManager?.enableUndoRegistration()
        }
    }

    private static func snapshots(for targetSnapshots: [TaskPlacementSnapshot], in context: ModelContext) -> [TaskPlacementSnapshot] {
        let ids = Set(targetSnapshots.map(\.id))
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []

        return tasks
            .filter { ids.contains($0.id) }
            .map { TaskPlacementSnapshot(id: $0.id, block: $0.block, sortOrder: $0.sortOrder) }
            .sorted { lhs, rhs in
                lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private static func applyPlacements(_ snapshots: [TaskPlacementSnapshot], in context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        for snapshot in snapshots {
            guard let task = tasksByID[snapshot.id] else { continue }
            task.block = snapshot.block
            task.sortOrder = snapshot.sortOrder
        }
    }
}

private struct TransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
