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
    @EnvironmentObject private var syncService: TodayMdSyncService
    @EnvironmentObject private var undoController: AppUndoController
    @EnvironmentObject private var presentationState: AppPresentationState

    @State private var selection: SidebarSelection = .all
    @State private var selectedTaskID: UUID?
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var selectionAnchorTaskID: UUID?
    @State private var focusedBlock: TimeBlock?
    @State private var expandedDoneBlocks: Set<TimeBlock> = []
    @State private var allTasksDoneSectionExpanded = false
    @State private var showingSettingsSheet = false
    @State private var transferAlert: TransferAlert?

    private var selectedList: TaskList? {
        guard case .list(let id) = selection else { return nil }
        return store.list(id: id)
    }

    private var selectedTask: TaskItem? {
        guard let selectedTaskID else { return nil }
        return store.task(id: selectedTaskID)
    }

    private var isBoardLayoutActive: Bool {
        !store.hasActiveSearch
    }

    private var isListBoardSelectionActive: Bool {
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

    private func boardTasks(for block: TimeBlock) -> [TaskItem] {
        if selectedList != nil {
            return listTasks(for: block)
        }

        return store.allTasks
            .filter { $0.block == block }
            .sorted(by: taskSort)
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

    private var visibleFlatTasks: [TaskItem] {
        let activeTasks = preferredVisibleTasks.filter { !$0.isDone }
        guard allTasksDoneSectionExpanded else { return activeTasks }
        let doneTasks = preferredVisibleTasks.filter(\.isDone)
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
        guard isBoardLayoutActive else {
            focusedBlock = nil
            return
        }

        if let selectedTask, isTaskVisibleOnCurrentBoard(selectedTask) {
            focusedBlock = selectedTask.block
        } else if focusedBlock == nil {
            focusedBlock = .today
        }
    }

    private var orderedSelectedTaskIDs: [UUID] {
        preferredVisibleTasks.map(\.id).filter { selectedTaskIDs.contains($0) }
    }

    private func orderedTaskIDsForLane(_ block: TimeBlock) -> [UUID] {
        let laneTasks = boardTasks(for: block)
        let activeTaskIDs = laneTasks.filter { !$0.isDone }.map(\.id)
        guard isDoneSectionExpanded(for: block) else { return activeTaskIDs }
        let doneTaskIDs = laneTasks.filter(\.isDone).map(\.id)
        return activeTaskIDs + doneTaskIDs
    }

    private var canCreateTaskInFocusedLane: Bool {
        isBoardLayoutActive && effectiveFocusedBlock != nil && !isModalUIActive
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
        showingSettingsSheet || presentationState.showingKeyboardShortcuts
    }

    private var effectiveFocusedBlock: TimeBlock? {
        if let focusedBlock {
            return focusedBlock
        }

        if isBoardLayoutActive {
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
            TodayMdTransferService.importData(into: store)
        }
    }

    private func startExport() {
        showingSettingsSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            TodayMdTransferService.exportData(from: store)
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

    private func startSyncFolderSelection() {
        showingSettingsSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            syncService.promptForFolderSelection()
        }
    }

    private func syncNowFromSettings() {
        syncService.syncNow()
    }

    private func disableSyncFromSettings() {
        syncService.disableSync()
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

    private func openSyncFolder() {
        syncService.openSyncFolder()
    }

    private var syncConflictIsPresented: Binding<Bool> {
        Binding(
            get: { syncService.conflict != nil },
            set: { _ in }
        )
    }

    private var syncStatusColor: Color {
        switch syncService.status {
        case .disabled:
            return .secondary
        case .idle:
            return .green
        case .syncing:
            return .blue
        case .conflict:
            return .orange
        case .error:
            return .red
        }
    }

    private var syncFolderActionTitle: String {
        syncService.syncEnabled ? "Choose Sync Folder" : "Enable Sync"
    }

    private var syncFolderActionSubtitle: String {
        if syncService.syncEnabled {
            return "Switch the iCloud Drive or OneDrive folder that stores the shared sync snapshot."
        }

        return "Choose a synced cloud folder and keep this Mac in sync through a single shared JSON snapshot."
    }

    private var syncLastSyncText: String {
        guard let lastSyncAt = syncService.lastSyncAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    private func syncConflictMessage(_ conflict: SyncConflict) -> String {
        var fragments: [String] = [
            "The cloud folder contains changes that do not match this Mac's unsynced edits."
        ]

        if let remoteUpdatedAt = conflict.remoteUpdatedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            fragments.append("Cloud update: \(formatter.string(from: remoteUpdatedAt)).")
        }

        if let remoteUpdatedByDeviceID = conflict.remoteUpdatedByDeviceID {
            fragments.append("Cloud device: \(remoteUpdatedByDeviceID).")
        }

        fragments.append("Choose which version should win. The discarded version will be saved in Conflict Backups.")
        return fragments.joined(separator: " ")
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
                    Text("Sync")
                        .font(.headline)

                    VStack(spacing: 12) {
                        settingsActionCard(
                            title: syncFolderActionTitle,
                            subtitle: syncFolderActionSubtitle,
                            systemImage: "icloud",
                            tint: .teal,
                            action: startSyncFolderSelection
                        )

                        settingsActionCard(
                            title: "Sync Now",
                            subtitle: "Re-read the cloud snapshot, pull if needed, or push this Mac's pending changes.",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .blue,
                            isEnabled: syncService.syncEnabled,
                            action: syncNowFromSettings
                        )

                        settingsActionCard(
                            title: "Open Sync Folder",
                            subtitle: "Reveal the chosen sync folder so you can inspect the JSON snapshot and markdown archive.",
                            systemImage: "folder",
                            tint: .green,
                            isEnabled: syncService.hasFolderSelection,
                            action: openSyncFolder
                        )

                        settingsActionCard(
                            title: "Disable Sync",
                            subtitle: "Keep local data on this Mac, but stop reading from and writing to the shared sync folder.",
                            systemImage: "xmark.icloud",
                            tint: .red,
                            isEnabled: syncService.syncEnabled,
                            action: disableSyncFromSettings
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(syncStatusColor)
                                .frame(width: 10, height: 10)

                            Text("Status: \(syncService.statusLabel)")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text("Last successful sync: \(syncLastSyncText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let folderPath = syncService.folderPath {
                            Text("Sync folder: \(folderPath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let lastError = syncService.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)

                    settingsActionCard(
                        title: "Open Shortcut Cheatsheet",
                        subtitle: "See the current selection, editor, board, and app shortcuts in one place.",
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

                        Text("Selection, editor, board, and app shortcuts that are currently available in today-md.")
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
        if store.hasActiveSearch {
            AllTasksView(
                tasks: preferredVisibleTasks,
                selectedTaskID: $selectedTaskID,
                selectedTaskIDs: $selectedTaskIDs,
                doneSectionExpanded: $allTasksDoneSectionExpanded,
                onSelect: selectTask,
                onMove: moveTask,
                onMarkDone: markDraggedSelectionDone,
                onDelete: deleteTask,
                onToggle: toggleTask,
                onReorderActive: reorderActiveTask
            )
        } else {
            BoardView(
                tasks: boardTasks,
                doneSectionExpanded: doneSectionExpandedBinding,
                selectedTaskID: $selectedTaskID,
                selectedTaskIDs: $selectedTaskIDs,
                focusedBlock: $focusedBlock,
                onSelect: selectTask,
                onAdd: addTask,
                onMove: moveTask,
                onMoveToDone: moveTaskToDone,
                onReorderInBlock: reorderTaskInVisibleBoard,
                onDelete: deleteTask,
                onToggle: toggleTask,
                allowsAdding: selection == .all || selectedList != nil,
                showsListBadge: selection == .all
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
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(isEnabled ? 0.14 : 0.08))

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isEnabled ? tint : .secondary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isEnabled ? .primary : .secondary)

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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 480, ideal: 680)
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
        .navigationSplitViewColumnWidth(min: 360, ideal: 460)
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
        .navigationSplitViewStyle(.balanced)
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
        .alert(item: $transferAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message)
            )
        }
        .alert("Sync Conflict", isPresented: syncConflictIsPresented, presenting: syncService.conflict) { _ in
            Button("Use Cloud Version") {
                syncService.resolveConflict(.useRemote)
            }

            Button("Keep This Mac's Version") {
                syncService.resolveConflict(.keepLocal)
            }
        } message: { conflict in
            Text(syncConflictMessage(conflict))
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
        let task: TaskItem?

        switch selection {
        case .all:
            task = store.addUnassignedTask(title: title, block: block)
        case .list(let listID):
            task = store.addTask(title: title, block: block, listID: listID)
        }

        guard let task else { return }
        setSingleSelection(task.id, focusedBlock: block)
    }

    private func createTaskInFocusedLane() {
        guard let block = effectiveFocusedBlock else { return }
        addTask(title: "New Task", block: block)
    }

    private func selectAllTasksInCurrentContext() {
        if isBoardLayoutActive {
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
        let visibleTaskIDs = visibleFlatTasks.map(\.id)
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
        if isBoardLayoutActive && isTaskVisibleOnCurrentBoard(task) {
            selectTask(task.id, in: orderedTaskIDsForLane(task.block), focusedBlock: task.block, extendingRange: extendingRange)
        } else {
            selectTask(task.id, in: visibleFlatTasks.map(\.id), extendingRange: extendingRange)
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

    private func reorderTaskInVisibleBoard(_ draggedID: UUID, _ block: TimeBlock, _ beforeID: UUID?) {
        if case .list = selection {
            reorderTaskInCurrentListBlock(draggedID, block, beforeID)
        } else {
            reorderActiveTask(draggedID, beforeID)
        }
    }

    private func reorderTaskInCurrentListBlock(_ draggedID: UUID, _ block: TimeBlock, _ beforeID: UUID?) {
        guard case .list(let listID) = selection else { return }
        store.reorderTaskInListBlock(listID: listID, draggedID: draggedID, block: block, before: beforeID)
    }

    private func isTaskVisibleOnCurrentBoard(_ task: TaskItem) -> Bool {
        switch selection {
        case .all:
            return true
        case .list(let listID):
            return task.list?.id == listID
        }
    }

    private func isDoneSectionExpanded(for block: TimeBlock) -> Bool {
        expandedDoneBlocks.contains(block)
    }

    private func doneSectionExpandedBinding(for block: TimeBlock) -> Binding<Bool> {
        Binding(
            get: { isDoneSectionExpanded(for: block) },
            set: { isExpanded in
                if isExpanded {
                    expandedDoneBlocks.insert(block)
                } else {
                    expandedDoneBlocks.remove(block)
                }
            }
        )
    }
}

private struct TransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
