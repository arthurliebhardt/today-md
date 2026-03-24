import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case list(UUID)
}

private enum AuxiliaryPanelMode: String, CaseIterable, Identifiable {
    case details
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details:
            return "Details"
        case .week:
            return "Week"
        }
    }
}

private enum WorkspaceMode: String, CaseIterable, Identifiable {
    case board
    case planner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board:
            return "Board"
        case .planner:
            return "Planner"
        }
    }
}

private struct MarkdownArchiveSnapshot: Equatable {
    let id: UUID
    let title: String
    let listName: String
    let blockRaw: String
    let noteContent: String
    let noteLastModified: Date
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case interface
    case calendar
    case dataBackup
    case sync
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interface:
            return "Interface"
        case .calendar:
            return "Calendar"
        case .dataBackup:
            return "Data"
        case .sync:
            return "Sync"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .interface:
            return "Appearance and quick capture"
        case .calendar:
            return "Availability and time blocking"
        case .dataBackup:
            return "Import, export, and archive"
        case .sync:
            return "Cloud folder and sync status"
        case .shortcuts:
            return "App commands and cheatsheet"
        }
    }

    var systemImage: String {
        switch self {
        case .interface:
            return "paintbrush.pointed.fill"
        case .calendar:
            return "calendar.badge.clock"
        case .dataBackup:
            return "internaldrive"
        case .sync:
            return "arrow.triangle.2.circlepath.icloud"
        case .shortcuts:
            return "command"
        }
    }

    var tint: Color {
        switch self {
        case .interface:
            return .indigo
        case .calendar:
            return .orange
        case .dataBackup:
            return .orange
        case .sync:
            return .teal
        case .shortcuts:
            return .purple
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

@MainActor
private struct WindowChromeInsetReader: NSViewRepresentable {
    let onTopInsetChange: (CGFloat) -> Void

    final class TrackingView: NSView {
        var onTopInsetChange: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportTopInset()
        }

        override func layout() {
            super.layout()
            reportTopInset()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            reportTopInset()
        }

        private func reportTopInset() {
            guard let window else { return }
            let topInset = max(0, window.frame.height - window.contentLayoutRect.maxY)
            onTopInsetChange?(topInset)
        }
    }

    @MainActor
    final class Coordinator {
        private var lastReportedInset: CGFloat = -1

        func update(topInset: CGFloat, onTopInsetChange: @escaping (CGFloat) -> Void) {
            guard abs(topInset - lastReportedInset) > 0.5 else { return }
            lastReportedInset = topInset

            DispatchQueue.main.async {
                onTopInsetChange(topInset)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onTopInsetChange = { topInset in
            context.coordinator.update(topInset: topInset, onTopInsetChange: onTopInsetChange)
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onTopInsetChange = { topInset in
            context.coordinator.update(topInset: topInset, onTopInsetChange: onTopInsetChange)
        }
        nsView.layoutSubtreeIfNeeded()
    }
}

struct ContentView: View {
    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var calendarService: TodayMdCalendarService
    @EnvironmentObject private var syncService: TodayMdSyncService
    @EnvironmentObject private var undoController: AppUndoController
    @EnvironmentObject private var presentationState: AppPresentationState
    @EnvironmentObject private var dynamicIslandController: GlobalDynamicIslandController
    @AppStorage(TodayMdPreferenceKey.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(TodayMdPreferenceKey.workspaceMode) private var workspaceModeRawValue = WorkspaceMode.board.rawValue
    @AppStorage(TodayMdPreferenceKey.calendarDefaultDurationMinutes) private var calendarDefaultDurationMinutes = 60
    @AppStorage(TodayMdPreferenceKey.calendarDefaultIdentifier) private var calendarDefaultIdentifier = ""

    @State private var selection: SidebarSelection = .all
    @State private var selectedTaskID: UUID?
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var selectionAnchorTaskID: UUID?
    @State private var focusedBlock: TimeBlock?
    @State private var expandedDoneBlocks: Set<TimeBlock> = []
    @State private var allTasksDoneSectionExpanded = false
    @State private var auxiliaryPanelMode: AuxiliaryPanelMode = .details
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowIsNarrow = false
    @State private var windowChromeTopInset: CGFloat = 0
    @State private var showOverlaySidebar = false
    @State private var showingSettingsSheet = false
    @State private var selectedSettingsSection: SettingsSection = .interface
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
        workspaceMode == .board && !store.hasActiveSearch
    }

    private var isListBoardSelectionActive: Bool {
        !store.hasActiveSearch && selectedList != nil
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    private var workspaceMode: WorkspaceMode {
        WorkspaceMode(rawValue: workspaceModeRawValue) ?? .board
    }

    private var appearanceModeSelection: Binding<AppAppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { appearanceModeRawValue = $0.rawValue }
        )
    }

    private var workspaceModeSelection: Binding<WorkspaceMode> {
        Binding(
            get: { workspaceMode },
            set: { workspaceModeRawValue = $0.rawValue }
        )
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else {
            return false
        }

        if flags.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            guard !currentSelectionTaskIDs.isEmpty else { return false }
            deleteSelectedTasks()
            return true
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

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

    private func requestCalendarAccessFromSettings() {
        calendarService.requestFullAccess()
    }

    private func refreshCalendarFromSettings() {
        calendarService.refreshIfNeeded()
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

    private var calendarPreferredIdentifier: String? {
        calendarDefaultIdentifier.isEmpty ? nil : calendarDefaultIdentifier
    }

    private var calendarDefaultDurationSelection: Binding<Int> {
        Binding(
            get: {
                [30, 60, 90, 120].contains(calendarDefaultDurationMinutes) ? calendarDefaultDurationMinutes : 60
            },
            set: { calendarDefaultDurationMinutes = $0 }
        )
    }

    private var calendarStatusColor: Color {
        switch calendarService.authorizationStatus {
        case .notDetermined:
            return .secondary
        case .denied, .restricted:
            return .red
        case .writeOnly:
            return .orange
        case .fullAccess:
            return .green
        }
    }

    private var calendarDestinationSummary: String {
        if let selectedCalendar = calendarService.selectedDestinationCalendar(preferredIdentifier: calendarPreferredIdentifier) {
            return selectedCalendar.displayTitle
        }

        return "No writable calendar found"
    }

    private var plannerShelfPhaseKey: String {
        if !calendarService.authorizationStatus.canReadEvents {
            return "authorization-\(calendarService.authorizationStatus.label)"
        }

        if calendarService.selectedDestinationCalendar(preferredIdentifier: calendarPreferredIdentifier) == nil {
            return "no-writable-calendar"
        }

        return "calendar-ready"
    }

    private var plannerShowsTaskColumns: Bool {
        calendarService.authorizationStatus.canReadEvents
    }

    private func calendarSuggestedSlotText(durationMinutes: Int) -> String {
        guard let interval = calendarService.suggestedBlockInterval(durationMinutes: durationMinutes) else {
            return "No open slot found in the next two weeks."
        }

        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: interval.start, to: interval.end)
    }

    private func calendarEventTimeText(_ event: TodayMdCalendarEventSummary) -> String {
        if event.isAllDay {
            return "All day"
        }

        let intervalFormatter = DateIntervalFormatter()
        intervalFormatter.dateStyle = Calendar.current.isDate(event.startDate, inSameDayAs: Date()) ? .none : .medium
        intervalFormatter.timeStyle = .short
        return intervalFormatter.string(from: event.startDate, to: event.endDate)
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

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
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
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 54, height: 54)
                        .shadow(color: Color.orange.opacity(0.18), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Settings")
                                .font(.system(size: 28, weight: .bold))

                            Text("Keep the utility actions grouped instead of stacking the whole workspace into one long sheet.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Workspace")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(SettingsSection.allCases) { section in
                            settingsSectionButton(section)
                        }
                    }

                    Spacer()

                    Text("The actions stay the same, but only one group is visible at a time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 230, alignment: .topLeading)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsSectionHeader(
                            selectedSettingsSection.title,
                            subtitle: selectedSettingsSection.subtitle,
                            tint: selectedSettingsSection.tint
                        )

                        settingsSectionContent
                    }
                    .padding(.trailing, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showingSettingsSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Close settings")
                .keyboardShortcut(.cancelAction)
                .padding(22)
            }
            .padding(28)
            .frame(width: 760, height: 680)
        }
    }

    private var settingsSectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedSettingsSection {
            case .interface:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Appearance and quick capture")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.indigo.opacity(0.14))

                                Image(systemName: appearanceMode.systemImage)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.indigo)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("App appearance")
                                    .font(.headline)

                                Text("Choose whether today-md follows macOS or stays in a fixed light or dark theme.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)
                        }

                        Picker("Appearance", selection: appearanceModeSelection) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(appearanceMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.indigo.opacity(0.14), lineWidth: 1)
                    )

                    settingsToggleCard(
                        title: "Top Screen Notch",
                        subtitle: "Show the floating notch when the pointer reaches the top-center edge of the screen, even outside the app window.",
                        systemImage: "rectangle.topthird.inset.filled",
                        tint: .indigo,
                        isOn: $dynamicIslandController.isEnabled
                    )

                    HStack(spacing: 8) {
                        Circle()
                            .fill(dynamicIslandController.isEnabled ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 10, height: 10)

                        Text(dynamicIslandController.isEnabled ? "The notch is active and can appear from the screen edge." : "The notch is off and will stay hidden until you enable it again.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.indigo.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.indigo.opacity(0.12), lineWidth: 1)
                    )
                }

            case .calendar:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Calendar blocking")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(calendarStatusColor)
                                .frame(width: 10, height: 10)

                            Text("Status: \(calendarService.authorizationStatus.label)")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(calendarService.authorizationStatus.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Calendars shown here come from macOS Calendar. Outlook / Exchange calendars appear here when the account is added to Calendar on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let lastError = calendarService.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.orange.opacity(0.14), lineWidth: 1)
                    )

                    VStack(spacing: 12) {
                        settingsActionCard(
                            title: calendarService.authorizationStatus.canReadEvents ? "Refresh Calendar" : "Connect Calendar",
                            subtitle: calendarService.authorizationStatus.canReadEvents
                                ? "Refresh available calendars and upcoming events from macOS Calendar."
                                : "Grant full access so today-md can read availability and create focus blocks.",
                            systemImage: calendarService.authorizationStatus.canReadEvents ? "arrow.clockwise" : "calendar.badge.plus",
                            tint: .orange,
                            action: calendarService.authorizationStatus.canReadEvents ? refreshCalendarFromSettings : requestCalendarAccessFromSettings
                        )
                    }

                    if calendarService.authorizationStatus.canReadEvents {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Destination calendar")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Picker("Destination calendar", selection: $calendarDefaultIdentifier) {
                                    Text("Auto (prefer Outlook / Exchange)")
                                        .tag("")

                                    ForEach(calendarService.writableCalendars) { calendar in
                                        Text(calendar.displayTitle)
                                            .tag(calendar.id)
                                    }
                                }
                                .pickerStyle(.menu)

                                Text("Current target: \(calendarDestinationSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Default block length")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Picker("Default block length", selection: calendarDefaultDurationSelection) {
                                    Text("30m").tag(30)
                                    Text("60m").tag(60)
                                    Text("90m").tag(90)
                                    Text("120m").tag(120)
                                }
                                .pickerStyle(.segmented)

                                Text("Next open \(calendarDefaultDurationSelection.wrappedValue)m slot: \(calendarSuggestedSlotText(durationMinutes: calendarDefaultDurationSelection.wrappedValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Upcoming events")
                                .font(.headline)

                            if calendarService.upcomingEvents.isEmpty {
                                Text("No events found in the next seven days.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(calendarService.upcomingEvents.prefix(6)), id: \.id) { event in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: event.isAllDay ? "sun.max" : "calendar")
                                            .foregroundStyle(.orange)
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(calendarEventTimeText(event))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(event.calendarTitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
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
                }

            case .dataBackup:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Backups and note exports")
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Archive location")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(markdownArchivePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

            case .sync:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Cloud sync")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sync folder")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(folderPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let lastError = syncService.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.teal.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.teal.opacity(0.14), lineWidth: 1)
                    )

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
                }

            case .shortcuts:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Keyboard shortcuts")
                        .font(.headline)

                    settingsActionCard(
                        title: "Open Shortcut Cheatsheet",
                        subtitle: "See the current selection, editor, board, and app shortcuts in one place.",
                        systemImage: "command",
                        tint: .purple,
                        action: openShortcutCheatsheetFromSettings
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick access")
                            .font(.subheadline.weight(.semibold))

                        shortcutPreviewRow(title: "Open shortcuts", shortcut: "Cmd-/")
                        shortcutPreviewRow(title: "Open settings", shortcut: "Toolbar")
                        shortcutPreviewRow(title: "New task", shortcut: "Cmd-N")
                        shortcutPreviewRow(title: "Mark done", shortcut: "Cmd-Shift-D")
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.purple.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.purple.opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.bottom, 56)
    }

    private func settingsSectionButton(_ section: SettingsSection) -> some View {
        let isSelected = selectedSettingsSection == section

        return Button {
            selectedSettingsSection = section
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(section.tint.opacity(isSelected ? 0.16 : 0.08))

                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? section.tint : .secondary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.92) : Color.white.opacity(0.001))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? section.tint.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsSectionHeader(_ title: String, subtitle: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))

                Image(systemName: selectedSettingsSection.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func shortcutPreviewRow(title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            ShortcutSequenceView(shortcut: shortcut, tone: .secondary)
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

    private var plannerWorkspaceView: some View {
        HStack(alignment: .top, spacing: 0) {
            if plannerShowsTaskColumns {
                plannerTaskShelf
                    .id(plannerShelfPhaseKey)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380, maxHeight: .infinity, alignment: .top)

                Divider()
            }

            WeekCalendarPanelView(displayMode: .week)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            if plannerShowsTaskColumns && !windowIsNarrow && hasDetailContent {
                Divider()

                plannerInspectorColumn
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 520, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.bottom, 8)
    }

    private var plannerTaskShelf: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tasks")
                                .font(.title3.weight(.semibold))

                            Text(plannerShelfSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Button {
                            addTask(title: "New Task", block: plannerDefaultNewTaskBlock)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .help("Create a new task")
                    }

                    if currentSelectionTaskIDs.count > 1 {
                        selectionActionBar
                    }

                    if plannerTaskSections.isEmpty {
                        ContentUnavailableView(
                            "No Active Tasks",
                            systemImage: "checkmark.circle",
                            description: Text("Change the current list or search to surface tasks you can drag onto the calendar.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    } else {
                        ForEach(plannerTaskSections, id: \.block.id) { section in
                            plannerTaskSection(block: section.block, tasks: section.tasks)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
    }

    private var plannerInspectorColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(hasMultipleSelectedTasks ? "Selection" : "Inspector")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(plannerInspectorSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if hasDetailContent {
                detailPanel
            } else {
                ContentUnavailableView(
                    "Select a Task",
                    systemImage: "checkmark.circle",
                    description: Text("Choose a task from the shelf, then drag it into the calendar or edit it here.")
                )
            }
        }
    }

    private var plannerShelfSubtitle: String {
        if store.hasActiveSearch {
            return "Filtered tasks stay beside the calendar so you can schedule them without switching back."
        }

        if let selectedList {
            return "Drag tasks from \(selectedList.name) directly into the calendar."
        }

        return "Keep the task shelf open while you block time on the calendar."
    }

    private var plannerInspectorSubtitle: String {
        if hasMultipleSelectedTasks {
            return "Review the current selection while the calendar stays centered."
        }

        return "The selected task stays editable without taking the calendar off screen."
    }

    private var plannerDefaultNewTaskBlock: TimeBlock {
        selectedTask?.block ?? .today
    }

    private var plannerTaskSections: [(block: TimeBlock, tasks: [TaskItem])] {
        TimeBlock.allCases.compactMap { block in
            let tasks = preferredVisibleTasks.filter { !$0.isDone && $0.block == block }
            return tasks.isEmpty ? nil : (block, tasks)
        }
    }

    private func plannerTaskSection(block: TimeBlock, tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(block.label, systemImage: block.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.10))
                    )
            }

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    plannerTaskRow(task)
                }
            }
        }
    }

    private func plannerTaskRow(_ task: TaskItem) -> some View {
        let isSelected = selectedTaskIDs.contains(task.id)

        return HStack(alignment: .top, spacing: 12) {
            Button(action: { toggleTask(task) }) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    let extendingRange = NSEvent.modifierFlags.contains(.shift)
                    selectTask(task, extendingRange: extendingRange)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 10) {
                            if let list = task.list {
                                Label(list.name, systemImage: list.icon)
                                    .font(.caption)
                                    .foregroundStyle(list.listColor.color)
                            }

                            if task.checkboxTotal > 0 {
                                Label("\(task.checkboxDone)/\(task.checkboxTotal)", systemImage: "checklist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if task.note != nil {
                                Image(systemName: "note.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSelected
                        ? Color.orange.opacity(0.12)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.84)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.orange.opacity(0.42)
                        : Color(nsColor: .separatorColor).opacity(0.24),
                    lineWidth: 1.2
                )
        )
        .draggable(TaskItemTransfer(id: task.id))
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

    private func settingsToggleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(isOn.wrappedValue ? 0.14 : 0.08))

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : .secondary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(isOn.wrappedValue ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isOn.wrappedValue ? tint.opacity(0.14) : Color.secondary.opacity(0.12))
                    )

                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(tint)
            }
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

    private var hasDetailContent: Bool {
        selectedTask != nil || hasMultipleSelectedTasks
    }

    @ViewBuilder
    private var detailPanel: some View {
        if hasMultipleSelectedTasks {
            multiSelectionDetailView
        } else if let task = selectedTask {
            TaskDetailView(
                task: task,
                onToggle: toggleTask,
                onDelete: deleteTask
            )
        }
    }

    private var inlineContentWithDetail: some View {
        HStack(spacing: 0) {
            contentColumn
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            if !windowIsNarrow {
                Divider()
                inlineDetailColumn
                    .frame(minWidth: 500, idealWidth: 640, maxWidth: 760)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private var inlineDetailColumn: some View {
        VStack(spacing: 0) {
            Picker("Workspace", selection: $auxiliaryPanelMode) {
                ForEach(AuxiliaryPanelMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if auxiliaryPanelMode == .week {
                WeekCalendarPanelView(displayMode: .todayAndTomorrow)
            } else if hasDetailContent {
                detailPanel
            } else {
                ContentUnavailableView(
                    "Select a Task",
                    systemImage: "checkmark.circle",
                    description: Text("Click a task to view details.")
                )
            }
        }
    }

    @ViewBuilder
    private var mainWorkspaceSurface: some View {
        if workspaceMode == .planner {
            plannerWorkspaceView
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $selection)
            } detail: {
                inlineContentWithDetail
            }
            .navigationSplitViewStyle(.prominentDetail)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainWorkspaceSurface
            .frame(minWidth: 900, minHeight: 500)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.width, initial: true) { _, newWidth in
                            let narrow = newWidth < 1200
                            if narrow != windowIsNarrow {
                                windowIsNarrow = narrow
                            }

                            withAnimation(.easeInOut(duration: 0.2)) {
                                columnVisibility = resolvedColumnVisibility(forNarrowWindow: narrow)
                                if workspaceMode == .planner || !narrow {
                                    showOverlaySidebar = false
                                }
                            }
                        }
                }
            )
            .background(
                KeyboardShortcutMonitor(handler: handleKeyboardShortcut)
                    .allowsHitTesting(false)
            )
            .background(
                WindowTitleSyncView(title: boardTitle)
                    .allowsHitTesting(false)
            )
            .background(
                WindowChromeInsetReader { topInset in
                    windowChromeTopInset = max(windowChromeTopInset, topInset)
                }
                .allowsHitTesting(false)
            )

            // Floating sidebar overlay for narrow windows
            if workspaceMode == .board && showOverlaySidebar {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showOverlaySidebar = false
                        }
                    }

                SidebarView(selection: $selection)
                    .frame(width: 260)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 6)
                    .transition(.move(edge: .leading))
            }

            // Floating detail overlay for narrow windows
            if workspaceMode == .board && windowIsNarrow && hasDetailContent {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTaskID = nil
                            selectedTaskIDs.removeAll()
                        }
                    }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    detailPanel
                        .frame(width: 520)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(.ultraThickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, x: -4)
                        .padding(.vertical, 8)
                        .padding(.trailing, 6)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarSearchField
            }

            ToolbarItem {
                Picker("View", selection: workspaceModeSelection) {
                    Text("Board")
                        .tag(WorkspaceMode.board)
                    Text("Planner")
                        .tag(WorkspaceMode.planner)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
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
                    selectedSettingsSection = .interface
                    showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings and app actions")
            }
        }
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
            if showOverlaySidebar {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOverlaySidebar = false
                }
            }
        }
        .onChange(of: markdownArchiveSnapshots, initial: true) { _, _ in
            syncMarkdownArchive()
        }
        .onChange(of: store.dataRevision, initial: true) { _, _ in
            validateSelection()
            syncSelectedTask()
        }
        .onChange(of: presentationState.taskNavigationRequest) { _, request in
            guard let request else { return }
            openTaskFromMenuBar(request.taskID)
        }
        .onDeleteCommand {
            deleteSelectedTasks()
        }
        .onChange(of: columnVisibility) { _, newValue in
            if workspaceMode == .board && windowIsNarrow && newValue != .detailOnly {
                columnVisibility = .detailOnly
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOverlaySidebar.toggle()
                }
            }
        }
        .onChange(of: workspaceMode) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = resolvedColumnVisibility(forNarrowWindow: windowIsNarrow)
                if workspaceMode == .planner {
                    showOverlaySidebar = false
                }
            }
        }
    }

    private func resolvedColumnVisibility(forNarrowWindow narrow: Bool) -> NavigationSplitViewVisibility {
        if narrow || workspaceMode == .planner {
            return .detailOnly
        }

        return .all
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

    private func openTaskFromMenuBar(_ taskID: UUID) {
        guard let task = store.task(id: taskID) else { return }

        store.searchText = ""
        selection = .all
        allTasksDoneSectionExpanded = false
        focusedBlock = task.block
        setSingleSelection(task.id, focusedBlock: task.block)
        NSApp.activate(ignoringOtherApps: true)
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
        let selectedIDs = currentSelectionTaskIDs
        if selectedIDs.count > 1, selectedIDs.contains(task.id) {
            deleteSelectedTasks()
            return
        }

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
