import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case list(UUID)
}

private struct MarkdownArchiveSnapshot: Equatable {
    let id: UUID
    let title: String
    let listName: String
    let blockRaw: String
    let noteContent: String
    let noteLastModified: Date
}

struct ContentView: View {
    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var undoController: AppUndoController

    @State private var selection: SidebarSelection = .all
    @State private var selectedTaskID: UUID?
    @State private var showingSettingsSheet = false
    @State private var showingImportPicker = false
    @State private var showingExportPicker = false
    @State private var pendingImportURL: URL?
    @State private var showingImportModeDialog = false
    @State private var transferAlert: TransferAlert?

    private var selectedList: TaskList? {
        guard case .list(let id) = selection else { return nil }
        return store.list(id: id)
    }

    private var selectedTask: TaskItem? {
        guard let selectedTaskID else { return nil }
        return store.task(id: selectedTaskID)
    }

    private func listTasks(for block: TimeBlock) -> [TaskItem] {
        guard let list = selectedList else { return [] }
        return store.filteredTasks(
            list.items
                .filter { $0.block == block }
                .sorted { $0.sortOrder < $1.sortOrder }
        )
    }

    private var preferredVisibleTasks: [TaskItem] {
        if store.hasActiveSearch {
            return store.rankedTasks(store.allTasks)
        }

        let tasks: [TaskItem]

        switch selection {
        case .all:
            tasks = store.allTasks
        case .list:
            tasks = TimeBlock.allCases.flatMap(listTasks)
        }

        let activeTasks = tasks.filter { !$0.isDone }
        let doneTasks = tasks.filter(\.isDone)
        return activeTasks + doneTasks
    }

    private func syncSelectedTask() {
        guard let selectedTaskID else { return }
        guard preferredVisibleTasks.contains(where: { $0.id == selectedTaskID }) else {
            self.selectedTaskID = nil
            return
        }
    }

    private func validateSelection() {
        guard case .list(let id) = selection else { return }
        if store.list(id: id) == nil {
            selection = .all
        }
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
                try TodayMdTransferService.exportData(from: store, to: folderURL)
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
            try TodayMdTransferService.importData(into: store, from: url, mode: mode)
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

    private var markdownArchivePath: String? {
        try? TodayMdMarkdownArchiveService.archivePath()
    }

    private var markdownArchiveSnapshots: [MarkdownArchiveSnapshot] {
        store.allTasks
            .compactMap { task -> MarkdownArchiveSnapshot? in
                guard let note = task.note else { return nil }

                return MarkdownArchiveSnapshot(
                    id: task.id,
                    title: task.title,
                    listName: task.list?.name ?? "Unassigned",
                    blockRaw: task.blockRaw,
                    noteContent: note.content,
                    noteLastModified: note.lastModified
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func syncMarkdownArchive() {
        do {
            try TodayMdMarkdownArchiveService.syncNotes(for: store.allTasks)
        } catch {
            presentTransferError(title: "Markdown Archive Sync Failed", error: error)
        }
    }

    private func openMarkdownArchive() {
        do {
            try TodayMdMarkdownArchiveService.revealArchiveFolder()
        } catch {
            presentTransferError(title: "Open Markdown Archive Failed", error: error)
        }
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

                        Text("Manage backups, local search, and note archives without coupling the app to Xcode-only persistence.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Workspace")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
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
                            subtitle: "Choose a folder and create a timestamped JSON backup plus separate markdown note files.",
                            systemImage: "square.and.arrow.up",
                            tint: .orange,
                            action: startExport
                        )

                        settingsActionCard(
                            title: "Open Markdown Archive",
                            subtitle: "Open the folder where task notes are mirrored as reusable .md files.",
                            systemImage: "doc.text",
                            tint: .green,
                            action: openMarkdownArchive
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

                    if let markdownArchivePath {
                        Text("Markdown archive: \(markdownArchivePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Search")
                        .font(.headline)

                    Text("Task title, note content, and checklist items are indexed in the local SQLite database using full-text search.")
                        .foregroundStyle(.secondary)

                    TextField("Search tasks", text: Binding(
                        get: { store.searchText },
                        set: { store.searchText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
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

                HStack {
                    Text("Future settings can build on top of the current local-first store without changing the app architecture again.")
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

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            Group {
                if store.hasActiveSearch || selection == .all {
                    AllTasksView(
                        tasks: preferredVisibleTasks,
                        selectedTaskID: $selectedTaskID,
                        onMove: moveTask,
                        onDelete: deleteTask,
                        onToggle: toggleTask,
                        onReorderActive: reorderActiveTask
                    )
                } else {
                    BoardView(
                        tasks: listTasks,
                        selectedTaskID: $selectedTaskID,
                        onAdd: addTask,
                        onMove: moveTask,
                        onReorderInBlock: reorderTaskInCurrentListBlock,
                        onDelete: deleteTask,
                        onToggle: toggleTask
                    )
                }
            }
            .navigationTitle(boardTitle)
            .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            if let task = selectedTask {
                TaskDetailView(
                    task: task,
                    onToggle: toggleTask,
                    onDelete: deleteTask
                )
            } else {
                ContentUnavailableView(
                    "Select a Task",
                    systemImage: "checkmark.circle",
                    description: Text("Click a task to view details.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 460, ideal: 560)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(
                        "Search tasks, notes, and checklist items",
                        text: Binding(
                            get: { store.searchText },
                            set: { store.searchText = $0 }
                        )
                    )
                    .textFieldStyle(.plain)

                    if store.hasActiveSearch {
                        Button {
                            store.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

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
            syncSelectedTask()
        }
        .onChange(of: selection, initial: true) { _, _ in
            syncSelectedTask()
        }
        .onChange(of: markdownArchiveSnapshots, initial: true) { _, _ in
            syncMarkdownArchive()
        }
        .onChange(of: store.dataRevision, initial: true) { _, _ in
            validateSelection()
            syncSelectedTask()
        }
        .onDeleteCommand {
            if let selectedTaskID {
                deleteTask(id: selectedTaskID)
            }
        }
    }

    private var boardTitle: String {
        if store.hasActiveSearch {
            return store.hasActiveSearch ? "Search Results" : "All Tasks"
        }

        switch selection {
        case .all:
            return "All Tasks"
        case .list(let id):
            return store.list(id: id)?.name ?? "Tasks"
        }
    }

    private func addTask(title: String, block: TimeBlock) {
        guard case .list(let listID) = selection,
              let task = store.addTask(title: title, block: block, listID: listID)
        else {
            return
        }

        selectedTaskID = task.id
    }

    private func moveTask(id: UUID, to block: TimeBlock) {
        store.moveTask(id: id, to: block)
    }

    private func deleteTask(_ task: TaskItem) {
        deleteTask(id: task.id)
    }

    private func deleteTask(id: UUID) {
        if selectedTaskID == id {
            selectedTaskID = nil
        }
        store.deleteTask(id: id)
    }

    private func toggleTask(_ task: TaskItem) {
        toggleTask(id: task.id)
    }

    private func toggleTask(id: UUID) {
        store.toggleTask(id: id)
    }

    private func reorderActiveTask(_ draggedID: UUID, _ beforeID: UUID?) {
        store.reorderAllActiveTask(draggedID, before: beforeID)
    }

    private func reorderTaskInCurrentListBlock(_ draggedID: UUID, _ block: TimeBlock, _ beforeID: UUID?) {
        guard case .list(let listID) = selection else { return }
        store.reorderTaskInListBlock(listID: listID, draggedID: draggedID, block: block, before: beforeID)
    }
}

private struct TransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
