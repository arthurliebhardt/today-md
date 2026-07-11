import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var calendarService: TodayMdCalendarService
    @EnvironmentObject private var syncService: TodayMdSyncService
    @EnvironmentObject private var undoController: AppUndoController
    @EnvironmentObject private var presentationState: AppPresentationState
    @EnvironmentObject private var dynamicIslandController: GlobalDynamicIslandController
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
    @State private var plannerShowsSidebar = true
    @State private var showingCalendarDestinationDialog = false
    @State private var shouldPromptForCalendarDestinationAfterConnect = false
    @State private var transferAlert: TransferAlert?
    @State private var plannerThisWeekCollapsed = false
    @State private var plannerBacklogCollapsed = false
    @State private var showingPlannerTaskCreationSheet = false
    @State private var plannerTaskDraftTitle = ""
    @State private var plannerTaskDraftListID: UUID?
    @State private var plannerTaskDraftBlock: TimeBlock = .today

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

    private var workspaceMode: WorkspaceMode {
        WorkspaceMode(rawValue: workspaceModeRawValue) ?? .board
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

        let tasks = TaskVisibilityScope.tasks(for: selection, store: store)

        let activeTasks = tasks.filter { !$0.isDone }
        let doneTasks = tasks.filter(\.isDone)
        return activeTasks + doneTasks
    }

    private var plannerVisibleTasks: [TaskItem] {
        let tasks: [TaskItem]

        if store.hasActiveSearch {
            tasks = store.rankedTasks(store.allTasks)
        } else {
            tasks = TaskVisibilityScope.tasks(for: selection, store: store)
        }

        let activeTasks = tasks.filter { !$0.isDone }
        let doneTasks = tasks.filter(\.isDone)
        return activeTasks + doneTasks
    }

    private var currentVisibleTasks: [TaskItem] {
        workspaceMode == .planner ? plannerVisibleTasks : preferredVisibleTasks
    }

    private var visibleFlatTasks: [TaskItem] {
        let activeTasks = currentVisibleTasks.filter { !$0.isDone }
        guard allTasksDoneSectionExpanded else { return activeTasks }
        let doneTasks = currentVisibleTasks.filter(\.isDone)
        return activeTasks + doneTasks
    }

    private func syncSelectedTask() {
        let visibleTasks = currentVisibleTasks
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
        currentVisibleTasks.map(\.id).filter { selectedTaskIDs.contains($0) }
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
        !currentVisibleTasks.isEmpty && !isModalUIActive
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
        presentationState.showingKeyboardShortcuts
    }

    private var workspaceCommandActions: WorkspaceCommandActions {
        WorkspaceCommandActions(
            canCreateTask: !isModalUIActive && canCreateTaskInFocusedLane,
            canMarkTasksDone: !isModalUIActive && canMarkSelectedTasksDone,
            createTask: performCreateTaskCommand,
            markTasksDone: performMarkTasksDoneCommand
        )
    }

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
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

    private func performCreateTaskCommand() {
        guard !isModalUIActive, !isEditingText, canCreateTaskInFocusedLane else { return }
        createTaskInFocusedLane()
    }

    private func performMarkTasksDoneCommand() {
        guard !isModalUIActive, !isEditingText, canMarkSelectedTasksDone else { return }
        markSelectedTasksDone()
    }

    private func performSelectAllCommand() {
        guard !isModalUIActive, !isEditingText, canSelectAllVisibleTasks else { return }
        selectAllTasksInCurrentContext()
    }

    private func performDeleteCommand() {
        guard !isModalUIActive, !isEditingText, !currentSelectionTaskIDs.isEmpty else { return }
        deleteSelectedTasks()
    }



    private func openShortcutCheatsheet() {
        presentationState.presentKeyboardShortcuts()
    }






    private func syncScheduledTasksIntoToday() {
        let scheduledTaskIDs = calendarService.managedTaskIDs(forDay: Date())
        store.promoteScheduledTasksToToday(ids: scheduledTaskIDs)
    }

    private func presentPlannerTaskCreationSheet() {
        plannerTaskDraftTitle = ""
        plannerTaskDraftBlock = plannerDefaultNewTaskBlock

        if let selectedList {
            plannerTaskDraftListID = selectedList.id
        } else {
            plannerTaskDraftListID = selectedTask?.list?.id
        }

        showingPlannerTaskCreationSheet = true
    }

    private func expandPlannerSection(for block: TimeBlock) {
        switch block {
        case .today:
            break
        case .thisWeek:
            plannerThisWeekCollapsed = false
        case .backlog:
            plannerBacklogCollapsed = false
        }
    }

    private func createTaskFromPlannerSheet() {
        let normalizedTitle = plannerTaskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        guard let task = store.quickAddTask(
            title: normalizedTitle,
            to: plannerTaskDraftBlock,
            listID: plannerTaskDraftListID
        ) else {
            return
        }

        expandPlannerSection(for: plannerTaskDraftBlock)
        showingPlannerTaskCreationSheet = false
        setSingleSelection(task.id, focusedBlock: plannerTaskDraftBlock)
    }

    private func presentTransferError(title: String, error: Error) {
        transferAlert = TransferAlert(
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }


    private func syncMarkdownArchive() {
        guard !syncService.syncEnabled else { return }

        do {
            try TodayMdMarkdownArchiveService.reconcileArchive(with: store)
        } catch {
            presentTransferError(title: "Markdown Archive Sync Failed", error: error)
        }
    }

    private func writeMarkdownArchive() {
        guard !syncService.syncEnabled else { return }

        do {
            try TodayMdMarkdownArchiveService.syncNotes(for: store.allTasks)
        } catch {
            presentTransferError(title: "Markdown Archive Sync Failed", error: error)
        }
    }

    private func handleApplicationDidBecomeActive() {
        if syncService.syncEnabled {
            syncService.handleAppDidBecomeActive()
            return
        }

        do {
            try TodayMdMarkdownArchiveService.syncArchiveAfterApplicationDidBecomeActive(with: store)
        } catch {
            presentTransferError(title: "Markdown Archive Sync Failed", error: error)
        }
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

    private var writableCalendars: [TodayMdCalendarSummary] {
        calendarService.writableCalendars
    }

    private var hasExplicitCalendarDestinationSelection: Bool {
        writableCalendars.contains { $0.id == calendarDefaultIdentifier }
    }

    private var resolvedCalendarDestinationIdentifier: String {
        if hasExplicitCalendarDestinationSelection {
            return calendarDefaultIdentifier
        }

        return calendarService.selectedDestinationCalendar(preferredIdentifier: nil)?.id
            ?? writableCalendars.first?.id
            ?? ""
    }

    private var needsCalendarDestinationSelection: Bool {
        calendarService.authorizationStatus.canReadEvents
            && !writableCalendars.isEmpty
            && !hasExplicitCalendarDestinationSelection
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
        true
    }



    private func presentCalendarDestinationSelectionIfNeeded() {
        if shouldPromptForCalendarDestinationAfterConnect {
            guard !writableCalendars.isEmpty else { return }
            showingCalendarDestinationDialog = true
            shouldPromptForCalendarDestinationAfterConnect = false
            return
        }

        guard needsCalendarDestinationSelection else {
            showingCalendarDestinationDialog = false
            return
        }

        showingCalendarDestinationDialog = true
    }

    private func selectCalendarDestination(_ calendarID: String) {
        guard writableCalendars.contains(where: { $0.id == calendarID }) else { return }
        calendarDefaultIdentifier = calendarID
        showingCalendarDestinationDialog = false
        shouldPromptForCalendarDestinationAfterConnect = false
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


    private var calendarDestinationDialogOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose Calendar for Entries")
                        .font(.system(size: 22, weight: .bold))

                    Text("Select the calendar where today-md should create task blockers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(writableCalendars) { calendar in
                        Button {
                            selectCalendarDestination(calendar.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(nsColor: calendar.nsColor))
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(calendar.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(calendar.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(nsColor: calendar.nsColor).opacity(0.26), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !needsCalendarDestinationSelection {
                    HStack {
                        Spacer()

                        Button("Cancel") {
                            showingCalendarDestinationDialog = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
            .padding(24)
        }
        .transition(.opacity)
        .zIndex(2)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .padding(.horizontal, 8)
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
                            presentPlannerTaskCreationSheet()
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
                            description: Text(store.hasActiveSearch
                                ? "Adjust the search to surface tasks you can drag onto the calendar."
                                : "Add a task, then drag it into the calendar to place a time block.")
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

    private var plannerShelfSubtitle: String {
        if store.hasActiveSearch {
            return "Filtered tasks stay beside the calendar so you can schedule them without switching back."
        }

        if selectedList != nil {
            return "This list stays beside the calendar so you can schedule it without switching back."
        }

        return "Keep the task shelf open while you block time on the calendar."
    }

    private var plannerDefaultNewTaskBlock: TimeBlock {
        selectedTask?.block ?? .today
    }

    private var plannerSortedLists: [TaskList] {
        store.lists.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var plannerTaskSections: [(block: TimeBlock, tasks: [TaskItem])] {
        TimeBlock.allCases.compactMap { block in
            let tasks = plannerVisibleTasks.filter { !$0.isDone && $0.block == block }
            return tasks.isEmpty ? nil : (block, tasks)
        }
    }

    private var plannerTaskCreationSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Task")
                    .font(.title3.weight(.semibold))

                Text("Choose the title, list, and lane before placing the task on the calendar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Task title", text: $plannerTaskDraftTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        createTaskFromPlannerSheet()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("List")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("List", selection: $plannerTaskDraftListID) {
                    Text("Unassigned")
                        .tag(nil as UUID?)

                    ForEach(plannerSortedLists) { list in
                        Label(list.name, systemImage: list.icon)
                            .tag(Optional(list.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Lane")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Lane", selection: $plannerTaskDraftBlock) {
                    ForEach(TimeBlock.allCases) { block in
                        Text(block.label)
                            .tag(block)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer(minLength: 0)

                Button("Cancel") {
                    showingPlannerTaskCreationSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Task") {
                    createTaskFromPlannerSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plannerTaskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func plannerTaskSection(block: TimeBlock, tasks: [TaskItem]) -> some View {
        let isCollapsible = block == .thisWeek || block == .backlog
        let isCollapsed = switch block {
        case .today:
            false
        case .thisWeek:
            plannerThisWeekCollapsed
        case .backlog:
            plannerBacklogCollapsed
        }

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                guard isCollapsible else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    switch block {
                    case .today:
                        break
                    case .thisWeek:
                        plannerThisWeekCollapsed.toggle()
                    case .backlog:
                        plannerBacklogCollapsed.toggle()
                    }
                }
            } label: {
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

                    if isCollapsible {
                        Spacer(minLength: 8)

                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isCollapsible)

            if !isCollapsed {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        plannerTaskRow(task)
                    }
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
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 10) {
                    if task.isScheduled {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            let extendingRange = NSEvent.modifierFlags.contains(.shift)
            selectTask(task, extendingRange: extendingRange)
        }
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

    private var plannerContentWithDetail: some View {
        plannerWorkspaceView
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
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
                WeekCalendarPanelView(displayMode: .upcomingWeek)
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
            HStack(spacing: 0) {
                if plannerShowsSidebar && !windowIsNarrow {
                    SidebarView(
                        selection: $selection,
                        workspaceMode: workspaceModeSelection
                    )
                        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)

                    Divider()
                }

                plannerContentWithDetail
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(
                    selection: $selection,
                    workspaceMode: workspaceModeSelection
                )
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
                                if !narrow {
                                    showOverlaySidebar = false
                                }
                            }
                        }
                }
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
            if showOverlaySidebar {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showOverlaySidebar = false
                        }
                    }

                SidebarView(
                    selection: $selection,
                    workspaceMode: workspaceModeSelection
                )
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
            if windowIsNarrow && hasDetailContent {
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

            if showingCalendarDestinationDialog, !writableCalendars.isEmpty {
                calendarDestinationDialogOverlay
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if workspaceMode == .planner {
                    Button(action: togglePlannerSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Show or hide the sidebar")
                }
            }

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

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings and app actions")
            }
        }
        .focusedSceneValue(\.workspaceCommandActions, workspaceCommandActions)
        .onCommand(#selector(NSText.selectAll(_:)), perform: performSelectAllCommand)
        .onDeleteCommand(perform: performDeleteCommand)
        .sheet(isPresented: $showingPlannerTaskCreationSheet) {
            plannerTaskCreationSheet
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
            store.configureMarkdownArchiveSyncHandler {
                writeMarkdownArchive()
            }
            syncSelectedTask()
            syncScheduledTasksIntoToday()
            syncMarkdownArchive()
            presentCalendarDestinationSelectionIfNeeded()
        }
        .onChange(of: selection, initial: true) { _, _ in
            syncSelectedTask()
            if showOverlaySidebar {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOverlaySidebar = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            handleApplicationDidBecomeActive()
        }
        .onChange(of: store.dataRevision, initial: true) { _, _ in
            validateSelection()
            syncSelectedTask()
        }
        .onChange(of: calendarService.refreshRevision, initial: true) { _, _ in
            syncScheduledTasksIntoToday()
            presentCalendarDestinationSelectionIfNeeded()
        }
        .onChange(of: calendarService.authorizationStatus, initial: true) { oldValue, newValue in
            if !oldValue.canReadEvents && newValue.canReadEvents {
                shouldPromptForCalendarDestinationAfterConnect = true
            }
            presentCalendarDestinationSelectionIfNeeded()
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
                if !windowIsNarrow {
                    showOverlaySidebar = false
                }
                if workspaceMode == .planner && !windowIsNarrow {
                    plannerShowsSidebar = true
                }
            }
            syncSelectedTask()
        }
    }

    private func togglePlannerSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if windowIsNarrow {
                showOverlaySidebar.toggle()
            } else {
                plannerShowsSidebar.toggle()
            }
        }
    }

    private func resolvedColumnVisibility(forNarrowWindow narrow: Bool) -> NavigationSplitViewVisibility {
        if narrow {
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
        clearManagedCalendarBlocksForTasksMovingAcrossLanes(taskIDs, to: block)

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

    private func clearManagedCalendarBlocksForTasksMovingAcrossLanes(_ taskIDs: [UUID], to targetBlock: TimeBlock) {
        let scheduledTaskIDs = Set(taskIDs.compactMap { taskID -> UUID? in
            guard let task = store.task(id: taskID),
                  task.isScheduled,
                  task.block != targetBlock else {
                return nil
            }

            return taskID
        })

        guard !scheduledTaskIDs.isEmpty else { return }
        try? calendarService.deleteManagedBlocks(forTaskIDs: scheduledTaskIDs)
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
            clearManagedCalendarBlocksForTasksMovingAcrossLanes([draggedID], to: block)
            store.moveActiveTaskOnBoard(draggedID, to: block, before: beforeID)
        }
    }

    private func reorderTaskInCurrentListBlock(_ draggedID: UUID, _ block: TimeBlock, _ beforeID: UUID?) {
        guard case .list(let listID) = selection else { return }
        clearManagedCalendarBlocksForTasksMovingAcrossLanes([draggedID], to: block)
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
