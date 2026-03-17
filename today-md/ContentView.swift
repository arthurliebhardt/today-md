import AppKit
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

private struct KeyboardShortcutMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handler(event) ? nil : event
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            stop()
        }
    }
}

@MainActor
private struct WindowTitleSyncView: NSViewRepresentable {
    let title: String

    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        weak var window: NSWindow?
        var title = ""

        func applyTitle() {
            guard let window else { return }
            window.titleVisibility = .visible
            if window.title != title {
                window.title = title
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindowChange = { [coordinator = context.coordinator] window in
            coordinator.window = window
            coordinator.applyTitle()
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.title = title
        context.coordinator.window = nsView.window
        context.coordinator.applyTitle()
        nsView.onWindowChange = { [coordinator = context.coordinator] window in
            coordinator.window = window
            coordinator.applyTitle()
        }
    }
}

struct ShortcutSequenceView: View {
    enum Tone {
        case accent
        case secondary
    }

    let shortcut: String
    var tone: Tone = .accent
    var font: Font = .system(.subheadline, design: .monospaced, weight: .semibold)

    private var tokens: [String] {
        shortcut
            .components(separatedBy: CharacterSet(charactersIn: "-+"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent:
            return .blue
        case .secondary:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent:
            return Color.blue.opacity(0.10)
        case .secondary:
            return Color.secondary.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .accent:
            return Color.blue.opacity(0.18)
        case .secondary:
            return Color.secondary.opacity(0.18)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                shortcutToken(token)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func shortcutToken(_ token: String) -> some View {
        Group {
            if token.caseInsensitiveCompare("cmd") == .orderedSame || token.caseInsensitiveCompare("command") == .orderedSame {
                Image(systemName: "command")
            } else {
                Text(token)
            }
        }
        .font(font)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .foregroundStyle(foregroundColor)
    }
}

struct ContentView: View {
    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var undoController: AppUndoController
    @EnvironmentObject private var presentationState: AppPresentationState

    @State private var selection: SidebarSelection = .all
    @State private var selectedTaskID: UUID?
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var selectionAnchorTaskID: UUID?
    @State private var focusedBlock: TimeBlock?
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

    private var isBoardSelectionActive: Bool {
        !store.hasActiveSearch && selectedList != nil
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
        let visibleTasks = preferredVisibleTasks
        let visibleIDs = Set(visibleTasks.map(\.id))
        var retainedIDs = selectedTaskIDs.intersection(visibleIDs)

        if let selectedTaskID, visibleIDs.contains(selectedTaskID) {
            retainedIDs.insert(selectedTaskID)
        }

        if let selectedTaskID, !retainedIDs.contains(selectedTaskID) {
            self.selectedTaskID = visibleTasks.first(where: { retainedIDs.contains($0.id) })?.id
        } else if selectedTaskID == nil {
            self.selectedTaskID = visibleTasks.first(where: { retainedIDs.contains($0.id) })?.id
        }

        selectedTaskIDs = retainedIDs
        if let selectionAnchorTaskID, !visibleIDs.contains(selectionAnchorTaskID) {
            self.selectionAnchorTaskID = nil
        }
        syncFocusedBlock()
    }

    private func validateSelection() {
        guard case .list(let id) = selection else { return }
        if store.list(id: id) == nil {
            selection = .all
        }
    }

    private func syncFocusedBlock() {
        guard isBoardSelectionActive else {
            focusedBlock = nil
            return
        }

        if let selectedTask, selectedTask.list?.id == selectedList?.id {
            focusedBlock = selectedTask.block
        } else if focusedBlock == nil {
            focusedBlock = .today
        }
    }

    private var orderedSelectedTaskIDs: [UUID] {
        preferredVisibleTasks.map(\.id).filter { selectedTaskIDs.contains($0) }
    }

    private func orderedTaskIDsForLane(_ block: TimeBlock) -> [UUID] {
        let laneTasks = listTasks(for: block)
        let activeTaskIDs = laneTasks.filter { !$0.isDone }.map(\.id)
        let doneTaskIDs = laneTasks.filter(\.isDone).map(\.id)
        return activeTaskIDs + doneTaskIDs
    }

    private var canCreateTaskInFocusedLane: Bool {
        isBoardSelectionActive && effectiveFocusedBlock != nil && !isModalUIActive
    }

    private var canSelectAllVisibleTasks: Bool {
        !preferredVisibleTasks.isEmpty && !isModalUIActive
    }

    private var currentSelectionTaskIDs: [UUID] {
        let orderedIDs = orderedSelectedTaskIDs
        if !orderedIDs.isEmpty {
            return orderedIDs
        }

        if let selectedTaskID {
            return [selectedTaskID]
        }

        return []
    }

    private var canMarkSelectedTasksDone: Bool {
        !isModalUIActive && currentSelectionTaskIDs.contains { taskID in
            store.task(id: taskID)?.isDone == false
        }
    }

    private var orderedSelectedTasks: [TaskItem] {
        currentSelectionTaskIDs.compactMap(store.task(id:))
    }

    private var hasMultipleSelectedTasks: Bool {
        orderedSelectedTasks.count > 1
    }

    private var isModalUIActive: Bool {
        showingSettingsSheet || showingImportPicker || showingExportPicker || showingImportModeDialog || presentationState.showingKeyboardShortcuts
    }

    private var effectiveFocusedBlock: TimeBlock? {
        if let focusedBlock {
            return focusedBlock
        }

        if isBoardSelectionActive {
            return selectedTask?.block ?? .today
        }

        return nil
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        guard !isModalUIActive else { return false }
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else {
            return false
        }

        switch (flags, characters) {
        case ([.command], "a"):
            guard canSelectAllVisibleTasks else { return false }
            selectAllTasksInCurrentContext()
            return true
        case ([.command], "n"):
            guard canCreateTaskInFocusedLane else { return false }
            createTaskInFocusedLane()
            return true
        case ([.command, .shift], "d"):
            guard canMarkSelectedTasksDone else { return false }
            markSelectedTasksDone()
            return true
        default:
            return false
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

    private func openShortcutCheatsheet() {
        presentationState.presentKeyboardShortcuts()
    }

    private func openShortcutCheatsheetFromSettings() {
        showingSettingsSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            presentationState.presentKeyboardShortcuts()
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

                        Text("Manage backups, keyboard shortcuts, and note archives without coupling the app to Xcode-only persistence.")
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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)

                    settingsActionCard(
                        title: "Open Shortcut Cheatsheet",
                        subtitle: "See the current selection, board, and app shortcuts in one place.",
                        systemImage: "command",
                        tint: .purple,
                        action: openShortcutCheatsheetFromSettings
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

    private var shortcutsSheetView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.08),
                    Color.blue.opacity(0.06),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.92), Color.teal.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(systemName: "command.square.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.blue.opacity(0.18), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Shortcuts")
                            .font(.system(size: 28, weight: .bold))

                        Text("Selection, board, and app shortcuts that are currently available in today-md.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(ShortcutCheatsheet.sections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.headline)

                                VStack(spacing: 10) {
                                    ForEach(section.items) { item in
                                        shortcutRow(item)
                                    }
                                }
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
                    }
                    .padding(.trailing, 4)
                }

                HStack(spacing: 6) {
                    Text("Open from the menu with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ShortcutSequenceView(
                        shortcut: "Cmd-/",
                        tone: .secondary,
                        font: .system(size: 11, weight: .semibold, design: .rounded)
                    )
                    Spacer()
                    Button("Close") {
                        presentationState.showingKeyboardShortcuts = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
            .frame(width: 620, height: 640)
        }
    }

    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            ShortcutSequenceView(shortcut: item.shortcut)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
    }

    @ViewBuilder
    private var contentColumn: some View {
        if store.hasActiveSearch || selection == .all {
            AllTasksView(
                tasks: preferredVisibleTasks,
                selectedTaskID: $selectedTaskID,
                selectedTaskIDs: $selectedTaskIDs,
                onSelect: selectTask,
                onMove: moveTask,
                onMarkDone: markDraggedSelectionDone,
                onDelete: deleteTask,
                onToggle: toggleTask,
                onReorderActive: reorderActiveTask
            )
        } else {
            BoardView(
                tasks: listTasks,
                selectedTaskID: $selectedTaskID,
                selectedTaskIDs: $selectedTaskIDs,
                focusedBlock: $focusedBlock,
                onSelect: selectTask,
                onAdd: addTask,
                onMove: moveTask,
                onMoveToDone: moveTaskToDone,
                onReorderInBlock: reorderTaskInCurrentListBlock,
                onDelete: deleteTask,
                onToggle: toggleTask
            )
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Text(selectionSummaryText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                markSelectedTasksDone()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canMarkSelectedTasksDone ? Color.green : Color.secondary.opacity(0.5))
            .background(
                Capsule()
                    .fill(Color.green.opacity(canMarkSelectedTasksDone ? 0.14 : 0.06))
            )
            .disabled(!canMarkSelectedTasksDone)

            Button(role: .destructive) {
                deleteSelectedTasks()
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.12))
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        )
    }

    private var selectionSummaryText: String {
        let count = currentSelectionTaskIDs.count
        if count == 1 {
            return "1 selected"
        }
        return "\(count) selected"
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
            contentColumn
            .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            if hasMultipleSelectedTasks {
                multiSelectionDetailView
            } else if let task = selectedTask {
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
                toolbarSearchField
            }

            ToolbarItemGroup {
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

                Button {
                    openShortcutCheatsheet()
                } label: {
                    Label("Keyboard Shortcuts", systemImage: "command")
                }
                .help("Open the keyboard shortcuts cheatsheet")

                Button {
                    showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings and app actions")
            }
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 800, minHeight: 500)
        .background(
            KeyboardShortcutMonitor(handler: handleKeyboardShortcut)
                .allowsHitTesting(false)
        )
        .background(
            WindowTitleSyncView(title: boardTitle)
                .allowsHitTesting(false)
        )
        .sheet(isPresented: $showingSettingsSheet) {
            settingsSheetView
        }
        .sheet(isPresented: $presentationState.showingKeyboardShortcuts) {
            shortcutsSheetView
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
            deleteSelectedTasks()
        }
    }

    private var toolbarSearchField: some View {
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

        setSingleSelection(task.id, focusedBlock: block)
    }

    private func createTaskInFocusedLane() {
        guard let block = effectiveFocusedBlock else { return }
        guard case .list(let listID) = selection,
              let task = store.addTask(title: "New Task", block: block, listID: listID)
        else {
            return
        }

        setSingleSelection(task.id, focusedBlock: block)
    }

    private func selectAllTasksInCurrentContext() {
        if isBoardSelectionActive {
            selectAllTasksInFocusedLane()
        } else {
            selectAllVisibleTasks()
        }
    }

    private func selectAllTasksInFocusedLane() {
        guard let block = effectiveFocusedBlock else { return }
        let laneTaskIDs = orderedTaskIDsForLane(block)
        guard !laneTaskIDs.isEmpty else { return }

        selectedTaskIDs = Set(laneTaskIDs)

        if let selectedTaskID, selectedTaskIDs.contains(selectedTaskID) {
            self.selectedTaskID = selectedTaskID
        } else {
            self.selectedTaskID = laneTaskIDs.first
        }

        selectionAnchorTaskID = self.selectedTaskID
        focusedBlock = block
    }

    private func selectAllVisibleTasks() {
        let visibleTaskIDs = preferredVisibleTasks.map(\.id)
        guard !visibleTaskIDs.isEmpty else { return }

        selectedTaskIDs = Set(visibleTaskIDs)

        if let selectedTaskID, selectedTaskIDs.contains(selectedTaskID) {
            self.selectedTaskID = selectedTaskID
        } else {
            self.selectedTaskID = visibleTaskIDs.first
        }

        selectionAnchorTaskID = self.selectedTaskID
    }

    private func setSingleSelection(_ taskID: UUID, focusedBlock: TimeBlock? = nil) {
        selectedTaskID = taskID
        selectedTaskIDs = [taskID]
        selectionAnchorTaskID = taskID

        if let focusedBlock {
            self.focusedBlock = focusedBlock
        }
    }

    private func selectTask(_ task: TaskItem, extendingRange: Bool) {
        if let selectedList, task.list?.id == selectedList.id {
            selectTask(task.id, in: orderedTaskIDsForLane(task.block), focusedBlock: task.block, extendingRange: extendingRange)
        } else {
            selectTask(task.id, in: preferredVisibleTasks.map(\.id), extendingRange: extendingRange)
        }
    }

    private func selectTask(_ taskID: UUID, in orderedIDs: [UUID], focusedBlock: TimeBlock? = nil, extendingRange: Bool) {
        if let focusedBlock {
            self.focusedBlock = focusedBlock
        }

        guard extendingRange,
              let anchorID = selectionAnchorTaskID ?? selectedTaskID,
              let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let selectedIndex = orderedIDs.firstIndex(of: taskID)
        else {
            setSingleSelection(taskID, focusedBlock: focusedBlock)
            return
        }

        let lowerBound = min(anchorIndex, selectedIndex)
        let upperBound = max(anchorIndex, selectedIndex)
        selectedTaskIDs = Set(orderedIDs[lowerBound...upperBound])
        selectedTaskID = taskID
    }

    private func moveTask(id: UUID, to block: TimeBlock) {
        let taskIDs = draggedSelectionTaskIDs(for: id)

        if taskIDs.count == 1, let taskID = taskIDs.first {
            store.moveTask(id: taskID, to: block, markDone: false)
        } else {
            store.moveTasks(ids: taskIDs, to: block, markDone: false)
        }

        if taskIDs.contains(where: { selectedTaskIDs.contains($0) }) {
            focusedBlock = block
        }
    }

    private func moveTaskToDone(id: UUID, in block: TimeBlock) {
        let taskIDs = draggedSelectionTaskIDs(for: id)
        if taskIDs.count == 1, let taskID = taskIDs.first {
            store.moveTask(id: taskID, to: block, markDone: true)
        } else {
            store.moveTasks(ids: taskIDs, to: block, markDone: true)
        }

        if taskIDs.contains(where: { selectedTaskIDs.contains($0) }) {
            focusedBlock = block
        }
    }

    private func deleteTask(_ task: TaskItem) {
        deleteTask(id: task.id)
    }

    private func deleteTask(id: UUID) {
        selectedTaskIDs.remove(id)
        if selectedTaskID == id {
            selectedTaskID = nil
        }
        if selectionAnchorTaskID == id {
            selectionAnchorTaskID = nil
        }
        store.deleteTask(id: id)
    }

    private func deleteSelectedTasks() {
        let taskIDs = orderedSelectedTaskIDs

        guard !taskIDs.isEmpty else {
            if let selectedTaskID {
                deleteTask(id: selectedTaskID)
            }
            return
        }

        selectedTaskIDs.removeAll()
        if let selectedTaskID, taskIDs.contains(selectedTaskID) {
            self.selectedTaskID = nil
        }
        if let selectionAnchorTaskID, taskIDs.contains(selectionAnchorTaskID) {
            self.selectionAnchorTaskID = nil
        }

        if taskIDs.count == 1, let taskID = taskIDs.first {
            store.deleteTask(id: taskID)
        } else {
            store.deleteTasks(ids: taskIDs)
        }
    }

    private func toggleTask(_ task: TaskItem) {
        toggleTask(id: task.id)
    }

    private func toggleTask(id: UUID) {
        store.toggleTask(id: id)
    }

    private func markDraggedSelectionDone(id: UUID) {
        let taskIDs = draggedSelectionTaskIDs(for: id).filter { taskID in
            store.task(id: taskID)?.isDone == false
        }

        guard !taskIDs.isEmpty else { return }

        if taskIDs.count == 1, let taskID = taskIDs.first {
            store.setTaskCompletion(id: taskID, isDone: true)
        } else {
            store.setTasksCompletion(ids: taskIDs, isDone: true)
        }
    }

    private func markSelectedTasksDone() {
        let taskIDs = currentSelectionTaskIDs.filter { taskID in
            store.task(id: taskID)?.isDone == false
        }

        guard !taskIDs.isEmpty else { return }

        if taskIDs.count == 1, let taskID = taskIDs.first {
            store.setTaskCompletion(id: taskID, isDone: true)
        } else {
            store.setTasksCompletion(ids: taskIDs, isDone: true)
        }
    }

    private func draggedSelectionTaskIDs(for draggedTaskID: UUID) -> [UUID] {
        let selectedTaskIDs = currentSelectionTaskIDs
        guard selectedTaskIDs.count > 1, selectedTaskIDs.contains(draggedTaskID) else {
            return [draggedTaskID]
        }

        return selectedTaskIDs
    }

    private var multiSelectionDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                selectionActionBar

                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Tasks")
                        .font(.headline)

                    ForEach(orderedSelectedTasks) { task in
                        multiSelectionTaskRow(task)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func multiSelectionTaskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.isDone ? .green : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .strikethrough(task.isDone)

                HStack(spacing: 10) {
                    if let list = task.list {
                        Label(list.name, systemImage: list.icon)
                            .font(.caption)
                            .foregroundStyle(list.listColor.color)
                    }

                    Label(task.block.label, systemImage: task.block.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.16), lineWidth: 1)
        )
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
