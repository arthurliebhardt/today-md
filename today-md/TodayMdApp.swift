import AppKit
import SwiftUI

enum TodayMdSceneID {
    static let mainWindow = "today-md-main-window"
}

enum TodayMdPreferenceKey {
    static let appearanceMode = "TodayMdAppearanceMode"
    static let workspaceMode = "TodayMdWorkspaceMode"
    static let calendarDefaultDurationMinutes = "TodayMdCalendarDefaultDurationMinutes"
    static let calendarDefaultIdentifier = "TodayMdCalendarDefaultIdentifier"
    static let calendarVisibleIdentifiers = "TodayMdCalendarVisibleIdentifiers"
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            return "Follow the current macOS appearance automatically."
        case .light:
            return "Keep the workspace in light mode."
        case .dark:
            return "Keep the workspace in dark mode."
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct KeyboardShortcutMonitor: NSViewRepresentable {
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

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NSApp.setActivationPolicy(.regular)
            window.minSize = NSSize(width: 900, height: 600)
            window.title = ""
            window.titleVisibility = .visible
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
            window.minSize = NSSize(width: 900, height: 600)
            window.titleVisibility = .visible
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

struct ShortcutItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let shortcut: String
    let detail: String
}

struct ShortcutSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [ShortcutItem]
}

enum ShortcutCheatsheet {
    static let sections: [ShortcutSection] = [
        ShortcutSection(
            title: "Selection",
            items: [
                ShortcutItem(
                    title: "Select task",
                    shortcut: "Click",
                    detail: "Select a single task and make it the active anchor."
                ),
                ShortcutItem(
                    title: "Extend selection",
                    shortcut: "Shift-Click",
                    detail: "Select the range from the current anchor to the clicked task."
                ),
                ShortcutItem(
                    title: "Select all visible tasks",
                    shortcut: "Cmd-A",
                    detail: "Select every task in the focused lane on the board, or every visible task in All Tasks and search."
                ),
                ShortcutItem(
                    title: "Delete selection",
                    shortcut: "Delete",
                    detail: "Delete the selected task or the whole selected set."
                ),
                ShortcutItem(
                    title: "Mark selection done",
                    shortcut: "Cmd-Shift-D",
                    detail: "Mark the selected task or selected tasks as done."
                )
            ]
        ),
        ShortcutSection(
            title: "Board",
            items: [
                ShortcutItem(
                    title: "Create task in selected lane",
                    shortcut: "Cmd-N",
                    detail: "Create a new task in the focused lane. In All Tasks, it is created without a list."
                ),
                ShortcutItem(
                    title: "Focus lane",
                    shortcut: "Click lane",
                    detail: "Click inside a lane to make it the target for lane-wide shortcuts."
                )
            ]
        ),
        ShortcutSection(
            title: "Editor",
            items: [
                ShortcutItem(
                    title: "Heading levels",
                    shortcut: "Cmd-1 / 2 / 3",
                    detail: "Turn the current line or selected lines into H1, H2, or H3 headings."
                ),
                ShortcutItem(
                    title: "Bold",
                    shortcut: "Cmd-B",
                    detail: "Wrap the current selection in Markdown bold markers."
                ),
                ShortcutItem(
                    title: "Italic",
                    shortcut: "Cmd-I",
                    detail: "Wrap the current selection in Markdown italic markers."
                ),
                ShortcutItem(
                    title: "Strikethrough",
                    shortcut: "Cmd-Shift-S",
                    detail: "Wrap the current selection in Markdown strikethrough markers."
                ),
                ShortcutItem(
                    title: "Code block",
                    shortcut: "Cmd-`",
                    detail: "Insert a fenced Markdown code block at the cursor."
                ),
                ShortcutItem(
                    title: "Bullet list",
                    shortcut: "Cmd-Shift-L",
                    detail: "Prefix the current line or selected lines with a bullet marker."
                ),
                ShortcutItem(
                    title: "Numbered list",
                    shortcut: "Cmd-Shift-O",
                    detail: "Prefix the current line or selected lines with numbered list markers."
                ),
                ShortcutItem(
                    title: "Checklist todo",
                    shortcut: "Cmd-Shift-T",
                    detail: "Insert Markdown checklist items for the current line or selection."
                ),
                ShortcutItem(
                    title: "Indent list level",
                    shortcut: "Tab",
                    detail: "Indent the current list item or the selected list items, up to three levels deep."
                ),
                ShortcutItem(
                    title: "Outdent list level",
                    shortcut: "Shift-Tab",
                    detail: "Move the current list item or selected list items back toward the left margin."
                ),
                ShortcutItem(
                    title: "Divider",
                    shortcut: "Cmd-Shift-D",
                    detail: "Insert a Markdown divider at the cursor."
                )
            ]
        ),
        ShortcutSection(
            title: "App",
            items: [
                ShortcutItem(
                    title: "Open shortcuts",
                    shortcut: "Cmd-/",
                    detail: "Open this keyboard shortcuts cheatsheet."
                ),
                ShortcutItem(
                    title: "Undo",
                    shortcut: "Cmd-Z",
                    detail: "Undo the last change."
                ),
                ShortcutItem(
                    title: "Redo",
                    shortcut: "Cmd-Shift-Z",
                    detail: "Redo the last undone change."
                )
            ]
        )
    ]
}

@MainActor
struct TaskNavigationRequest: Equatable {
    let id = UUID()
    let taskID: UUID
}

@MainActor
final class AppPresentationState: ObservableObject {
    @Published var showingKeyboardShortcuts = false
    @Published var taskNavigationRequest: TaskNavigationRequest?

    func presentKeyboardShortcuts() {
        showingKeyboardShortcuts = true
    }

    func openTask(_ taskID: UUID) {
        taskNavigationRequest = TaskNavigationRequest(taskID: taskID)
    }
}

@main
struct TodayMdApp: App {
    struct LaunchConfiguration {
        let databaseURL: URL?
        let shouldSeedShowcaseData: Bool
        let shouldResetShowcaseData: Bool
        let shouldRunSyncLifecycle: Bool
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TodayMdPreferenceKey.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @StateObject private var undoController = AppUndoController()
    @StateObject private var presentationState = AppPresentationState()
    @StateObject private var syncService: TodayMdSyncService
    @StateObject private var calendarService = TodayMdCalendarService()
    @StateObject private var dynamicIslandController = GlobalDynamicIslandController()
    @State private var store: TodayMdStore
    private let shouldRunSyncLifecycle: Bool
    static let hasLaunchedBeforeDefaultsKey = "TodayMdHasLaunchedBefore"

    init() {
        let syncService = TodayMdSyncService()
        let userDefaults = UserDefaults.standard
        let launchConfiguration = Self.makeLaunchConfiguration(
            syncEnabled: syncService.syncEnabled,
            userDefaults: userDefaults,
            bundleURL: Bundle.main.bundleURL,
            executableURL: Bundle.main.executableURL
        )
        shouldRunSyncLifecycle = launchConfiguration.shouldRunSyncLifecycle
        Self.markHasLaunchedBefore(userDefaults: userDefaults)
        _syncService = StateObject(wrappedValue: syncService)
        _store = State(
            initialValue: TodayMdStore(
                databaseURL: launchConfiguration.databaseURL,
                shouldSeedShowcaseData: launchConfiguration.shouldSeedShowcaseData,
                shouldResetShowcaseData: launchConfiguration.shouldResetShowcaseData
            )
        )
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some Scene {
        Window("today-md", id: TodayMdSceneID.mainWindow) {
            ContentView()
                .environment(store)
                .environmentObject(syncService)
                .environmentObject(calendarService)
                .environmentObject(undoController)
                .environmentObject(presentationState)
                .environmentObject(dynamicIslandController)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .background(MainWindowConfigurator())
                .onAppear {
                    store.configureUndoManager(undoController.manager)
                    dynamicIslandController.attach(store: store)
                    calendarService.refreshIfNeeded()

                    guard shouldRunSyncLifecycle else { return }
                    syncService.attach(store: store)
                    syncService.handleAppLaunchIfNeeded()
                }
        }
        .defaultSize(width: 1500, height: 920)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                calendarService.refreshIfNeeded()

                guard shouldRunSyncLifecycle else { return }
                syncService.handleAppDidBecomeActive()
            case .inactive, .background:
                store.flushPendingPersistence()
            @unknown default:
                break
            }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Import...") {
                    TodayMdTransferService.importData(into: store)
                }

                Button("Export...") {
                    TodayMdTransferService.exportData(from: store)
                }
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

            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts") {
                    presentationState.presentKeyboardShortcuts()
                }
                .keyboardShortcut("/", modifiers: [.command])
            }
        }

        MenuBarExtra {
            TodayMdMenuBarExtraView()
                .environment(store)
                .environmentObject(syncService)
                .environmentObject(presentationState)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
        } label: {
            Image(nsImage: TodayMdMenuBarIcon.image)
                .accessibilityLabel("today-md")
        }
        .menuBarExtraStyle(.window)
    }

    static func makeLaunchConfiguration(
        syncEnabled: Bool,
        userDefaults: UserDefaults,
        bundleURL: URL,
        executableURL: URL?
    ) -> LaunchConfiguration {
        if isRunningLocallyFromSwiftRun(bundleURL: bundleURL, executableURL: executableURL) {
            return LaunchConfiguration(
                databaseURL: localSwiftRunShowcaseDatabaseURL(executableURL: executableURL),
                shouldSeedShowcaseData: true,
                shouldResetShowcaseData: true,
                shouldRunSyncLifecycle: false
            )
        }

        return LaunchConfiguration(
            databaseURL: nil,
            shouldSeedShowcaseData: !syncEnabled && !userDefaults.bool(forKey: hasLaunchedBeforeDefaultsKey),
            shouldResetShowcaseData: false,
            shouldRunSyncLifecycle: true
        )
    }

    static func markHasLaunchedBefore(userDefaults: UserDefaults) {
        userDefaults.set(true, forKey: hasLaunchedBeforeDefaultsKey)
    }

    static func isRunningLocallyFromSwiftRun(bundleURL: URL, executableURL: URL?) -> Bool {
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") != .orderedSame else {
            return false
        }

        guard let executableURL else { return false }
        return executableURL.path.contains("/.build/")
    }

    static func localSwiftRunShowcaseDatabaseURL(executableURL: URL?) -> URL? {
        guard let executableURL else { return nil }
        return executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("today-md-showcase.sqlite", isDirectory: false)
    }
}

@MainActor
@Observable
final class TodayMdStore {
    private enum PersistenceMode {
        case immediate
        case deferred
    }

    private static let deferredPersistenceDelay: DispatchTimeInterval = .milliseconds(150)

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

    @ObservationIgnored
    private var syncHandler: (() -> Void)?

    @ObservationIgnored
    private let persistenceQueue = DispatchQueue(label: "com.todaymd.persistence", qos: .utility)

    @ObservationIgnored
    private var pendingPersistWorkItem: DispatchWorkItem?

    @ObservationIgnored
    private var pendingPersistToken = 0

    @ObservationIgnored
    private var hasPendingSyncNotification = false

    init(
        databaseURL: URL? = nil,
        shouldSeedShowcaseData: Bool = true,
        shouldResetShowcaseData: Bool = false
    ) {
        do {
            database = try TodayMdDatabase(url: databaseURL ?? Self.defaultDatabaseURL())

            if shouldResetShowcaseData {
                loadShowcaseData()
                return
            }

            let archive = try database.loadArchive()
            if applyArchive(archive, refreshSearch: false) {
                persist()
            }

            if allTasks.isEmpty {
                if shouldSeedShowcaseData {
                    loadShowcaseData()
                } else {
                    refreshSearch()
                }
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

    var isEmpty: Bool {
        allTasks.isEmpty
    }

    func configureUndoManager(_ manager: UndoManager) {
        undoManager = manager
    }

    func configureSyncHandler(_ handler: @escaping () -> Void) {
        syncHandler = handler
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
        let task = TaskItem(title: title, block: block, sortOrder: 0)
        task.list = list

        performMutation(actionName: "Add Task") {
            shiftSortOrderForNewTask(atTopOf: list, in: block)
            list.items.append(task)
        }

        return task
    }

    func addUnassignedTask(title: String, block: TimeBlock) -> TaskItem {
        let task = TaskItem(title: title, block: block, sortOrder: 0)

        performMutation(actionName: "Add Task") {
            shiftSortOrderForNewTask(atTopOf: nil, in: block)
            unassignedTasks.append(task)
        }

        return task
    }

    func quickAddTask(title: String, to block: TimeBlock = .today, listID: UUID? = nil) -> TaskItem? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }

        if let listID {
            return addTask(title: normalizedTitle, block: block, listID: listID)
        }

        return addUnassignedTask(title: normalizedTitle, block: block)
    }

    func assignTask(id: UUID, toListID listID: UUID?) {
        guard let task = task(id: id) else { return }

        let sourceList = task.list
        let sourceListID = sourceList?.id
        guard sourceListID != listID else { return }

        let destinationList = listID.flatMap(list(id:))
        guard listID == nil || destinationList != nil else { return }

        let actionName: String
        if listID == nil {
            actionName = "Remove Task from List"
        } else if sourceList == nil {
            actionName = "Assign Task to List"
        } else {
            actionName = "Move Task to List"
        }

        performMutation(actionName: actionName) {
            let preservedSortOrder = task.sortOrder

            if let sourceList {
                sourceList.items.removeAll { $0.id == id }
            } else {
                unassignedTasks.removeAll { $0.id == id }
            }

            task.list = destinationList
            insertTask(task, into: destinationList, in: task.block, preferredSortOrder: preservedSortOrder)
        }
    }

    func moveTask(
        id: UUID,
        to block: TimeBlock,
        markDone: Bool? = nil,
        preserveSchedulingState: Bool = false
    ) {
        guard let task = task(id: id) else { return }
        let previousBlock = task.block
        let nextDoneState = markDone ?? task.isDone
        guard previousBlock != block || task.isDone != nextDoneState else { return }

        performMutation(actionName: "Move Task", persistenceMode: .deferred) {
            task.block = block
            task.isDone = nextDoneState
            if previousBlock != block, !preserveSchedulingState {
                task.schedulingState = .unscheduled
            }
            task.sortOrder = nextSortOrder(for: task.list, in: block)

            if previousBlock != block {
                normalizeSortOrder(for: task.list, in: previousBlock)
            }

            normalizeSortOrder(for: task.list, in: block)
        }
    }

    func moveTasks(
        ids: [UUID],
        to block: TimeBlock,
        markDone: Bool? = nil,
        preserveSchedulingState: Bool = false
    ) {
        let uniqueIDs = Set(ids)
        guard !uniqueIDs.isEmpty else { return }

        let tasksToMove = allTasks.filter { task in
            guard uniqueIDs.contains(task.id) else { return false }
            let nextDoneState = markDone ?? task.isDone
            return task.block != block || task.isDone != nextDoneState
        }
        guard !tasksToMove.isEmpty else { return }

        struct SortScope: Hashable {
            let listID: UUID?
            let block: TimeBlock
        }

        let affectedScopes = Set(
            tasksToMove.flatMap { task -> [SortScope] in
                let listID = task.list?.id
                return [
                    SortScope(listID: listID, block: task.block),
                    SortScope(listID: listID, block: block)
                ]
            }
        )

        performMutation(
            actionName: tasksToMove.count == 1 ? "Move Task" : "Move Tasks",
            persistenceMode: .deferred
        ) {
            for task in tasksToMove {
                let previousBlock = task.block
                task.block = block
                task.isDone = markDone ?? task.isDone
                if previousBlock != block, !preserveSchedulingState {
                    task.schedulingState = .unscheduled
                }
                task.sortOrder = nextSortOrder(for: task.list, in: block)
            }

            for scope in affectedScopes {
                normalizeSortOrder(for: scope.listID.flatMap(list(id:)), in: scope.block)
            }
        }
    }

    func promoteScheduledTasksToToday(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let taskIDsToPromote = allTasks
            .filter { ids.contains($0.id) && !$0.isDone && $0.block != .today }
            .map(\.id)

        guard !taskIDsToPromote.isEmpty else { return }
        moveTasks(ids: taskIDsToPromote, to: .today, markDone: false, preserveSchedulingState: true)
    }

    func setTaskSchedulingState(id: UUID, isScheduled: Bool) {
        guard let task = task(id: id) else { return }

        let targetState: TaskSchedulingState = isScheduled ? .scheduled : .unscheduled
        guard task.schedulingState != targetState else { return }

        performMutation(
            actionName: isScheduled ? "Schedule Task" : "Unschedule Task",
            persistenceMode: .deferred
        ) {
            task.schedulingState = targetState
        }
    }

    func syncTaskBlockWithScheduledDate(
        id: UUID,
        scheduledDate: Date,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) {
        guard let task = task(id: id) else { return }

        let targetBlock: TimeBlock
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceStartOfDay)

        if calendar.isDate(scheduledDate, inSameDayAs: referenceStartOfDay) {
            targetBlock = .today
        } else if let tomorrow, calendar.isDate(scheduledDate, inSameDayAs: tomorrow) {
            targetBlock = .thisWeek
        } else if let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
                  scheduledDate >= currentWeek.start,
                  scheduledDate < currentWeek.end {
            targetBlock = .thisWeek
        } else {
            targetBlock = .backlog
        }

        let previousBlock = task.block
        let shouldUpdateBlock = previousBlock != targetBlock
        let shouldUpdateSchedulingState = !task.isScheduled

        guard shouldUpdateBlock || shouldUpdateSchedulingState else { return }

        performMutation(actionName: "Schedule Task", persistenceMode: .deferred) {
            task.schedulingState = .scheduled

            guard shouldUpdateBlock else { return }

            task.block = targetBlock
            task.sortOrder = nextSortOrder(for: task.list, in: targetBlock)
            normalizeSortOrder(for: task.list, in: previousBlock)
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

    func deleteTasks(ids: [UUID]) {
        let uniqueIDs = Set(ids)
        guard !uniqueIDs.isEmpty else { return }

        let tasksToDelete = allTasks.filter { uniqueIDs.contains($0.id) }
        guard !tasksToDelete.isEmpty else { return }

        struct SortScope: Hashable {
            let listID: UUID?
            let block: TimeBlock
        }

        let affectedScopes = Set(
            tasksToDelete.map { task in
                SortScope(listID: task.list?.id, block: task.block)
            }
        )

        performMutation(actionName: tasksToDelete.count == 1 ? "Delete Task" : "Delete Tasks") {
            for list in lists {
                list.items.removeAll { uniqueIDs.contains($0.id) }
            }

            unassignedTasks.removeAll { uniqueIDs.contains($0.id) }

            for scope in affectedScopes {
                normalizeSortOrder(for: scope.listID.flatMap(list(id:)), in: scope.block)
            }
        }
    }

    func setTaskCompletion(id: UUID, isDone: Bool) {
        guard let task = task(id: id) else { return }
        guard task.isDone != isDone else { return }

        performMutation(actionName: isDone ? "Complete Task" : "Mark Task Incomplete") {
            task.isDone = isDone
            task.sortOrder = nextSortOrder(for: task.list, in: task.block)
            normalizeSortOrder(for: task.list, in: task.block)
        }
    }

    func setTasksCompletion(ids: [UUID], isDone: Bool) {
        let uniqueIDs = Set(ids)
        guard !uniqueIDs.isEmpty else { return }

        let tasksToUpdate = allTasks.filter { uniqueIDs.contains($0.id) && $0.isDone != isDone }
        guard !tasksToUpdate.isEmpty else { return }

        struct SortScope: Hashable {
            let listID: UUID?
            let block: TimeBlock
        }

        let affectedScopes = Set(
            tasksToUpdate.map { task in
                SortScope(listID: task.list?.id, block: task.block)
            }
        )

        performMutation(
            actionName: isDone
                ? (tasksToUpdate.count == 1 ? "Complete Task" : "Complete Tasks")
                : (tasksToUpdate.count == 1 ? "Mark Task Incomplete" : "Mark Tasks Incomplete")
        ) {
            for task in tasksToUpdate {
                task.isDone = isDone
                task.sortOrder = nextSortOrder(for: task.list, in: task.block)
            }

            for scope in affectedScopes {
                normalizeSortOrder(for: scope.listID.flatMap(list(id:)), in: scope.block)
            }
        }
    }

    func toggleTask(id: UUID) {
        guard let task = task(id: id) else { return }
        setTaskCompletion(id: id, isDone: !task.isDone)
    }

    func reorderAllActiveTask(_ draggedID: UUID, before beforeID: UUID?) {
        if beforeID == draggedID { return }

        performMutation(actionName: "Reorder Tasks", persistenceMode: .deferred) {
            guard let draggedTask = task(id: draggedID) else { return }

            if draggedTask.isDone {
                draggedTask.isDone = false
            }

            var active = allTasks.filter { !$0.isDone }.sorted(by: taskSort)
            let done = allTasks.filter(\.isDone).sorted(by: taskSort)

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
            applyGlobalSortOrder(active + done)
        }
    }

    func moveActiveTaskOnBoard(
        _ draggedID: UUID,
        to block: TimeBlock,
        before beforeID: UUID?,
        preserveSchedulingState: Bool = false
    ) {
        guard let draggedTask = task(id: draggedID) else { return }
        if beforeID == draggedID, draggedTask.block == block, !draggedTask.isDone { return }

        performMutation(actionName: "Move Task", persistenceMode: .deferred) {
            let previousBlock = draggedTask.block

            if draggedTask.block != block {
                draggedTask.block = block
                if !preserveSchedulingState {
                    draggedTask.schedulingState = .unscheduled
                }
            }

            if draggedTask.isDone {
                draggedTask.isDone = false
            }

            var active = allTasks.filter { !$0.isDone }.sorted(by: taskSort)
            let done = allTasks.filter(\.isDone).sorted(by: taskSort)

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
            applyGlobalSortOrder(active + done)

            if previousBlock != block {
                normalizeSortOrder(for: draggedTask.list, in: previousBlock)
            }
        }
    }

    func reorderTaskInListBlock(
        listID: UUID,
        draggedID: UUID,
        block: TimeBlock,
        before beforeID: UUID?,
        preserveSchedulingState: Bool = false
    ) {
        if beforeID == draggedID { return }
        guard let list = list(id: listID),
              let draggedTask = list.items.first(where: { $0.id == draggedID })
        else {
            return
        }

        performMutation(actionName: "Move Task", persistenceMode: .deferred) {
            let previousBlock = draggedTask.block

            if draggedTask.block != block {
                draggedTask.block = block
                if !preserveSchedulingState {
                    draggedTask.schedulingState = .unscheduled
                }
                draggedTask.sortOrder = nextSortOrder(for: list, in: block)
            }

            if draggedTask.isDone {
                draggedTask.isDone = false
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
                _ = sanitizeHydratedDataIfNeeded()
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

            _ = sanitizeHydratedDataIfNeeded()
        }
    }

    func makeArchive() -> TodayMdArchive {
        makeArchive(syncRevisionID: nil, syncUpdatedAt: nil, syncUpdatedByDeviceID: nil)
    }

    func makeArchive(
        syncRevisionID: String?,
        syncUpdatedAt: Date?,
        syncUpdatedByDeviceID: String?
    ) -> TodayMdArchive {
        TodayMdArchive(
            lists: lists,
            unassignedTasks: unassignedTasks,
            syncRevisionID: syncRevisionID,
            syncUpdatedAt: syncUpdatedAt,
            syncUpdatedByDeviceID: syncUpdatedByDeviceID
        )
    }

    func applyRemoteArchive(_ archive: TodayMdArchive) {
        applyArchive(archive, refreshSearch: true)
        persist(notifySync: false)
    }

    func applyMarkdownArchive(_ archive: TodayMdArchive) {
        applyArchive(archive, refreshSearch: true)
        persist(notifySync: true)
    }

    private func loadShowcaseData() {
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

    private func normalizeLegacyNotesIfNeeded() -> Bool {
        var didChange = false

        for task in allTasks {
            guard let note = task.note else { continue }
            let canonical = MarkdownInlineDisplay.canonicalMarkdown(from: note.content)
            guard canonical != note.content else { continue }

            note.content = canonical
            note.lastModified = Date()
            didChange = true
        }

        return didChange
    }

    private func sanitizeHydratedDataIfNeeded() -> Bool {
        let removedLegacySubtasks = removeLegacySubtasksIfNeeded()
        let normalizedLegacyNotes = normalizeLegacyNotesIfNeeded()
        return removedLegacySubtasks || normalizedLegacyNotes
    }

    private func performMutation(
        actionName: String,
        registersUndo: Bool = true,
        persistenceMode: PersistenceMode = .immediate,
        _ change: () -> Void
    ) {
        let previous = registersUndo ? makeArchive() : nil
        change()
        persist(using: persistenceMode)
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
        persist(using: .immediate)
        undoManager?.registerUndo(withTarget: self) { target in
            target.restore(from: current, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    @discardableResult
    private func applyArchive(_ archive: TodayMdArchive, refreshSearch shouldRefreshSearch: Bool) -> Bool {
        let hydrated = archive.instantiate()
        lists = hydrated.lists
        unassignedTasks = hydrated.unassignedTasks
        let didSanitize = sanitizeHydratedDataIfNeeded()
        dataRevision += 1

        if shouldRefreshSearch {
            refreshSearch()
        }

        return didSanitize
    }

    func flushPendingPersistence() {
        pendingPersistToken += 1
        let shouldNotifySync = hasPendingSyncNotification
        hasPendingSyncNotification = false
        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = nil
        persistArchive(makeArchive(), notifySync: shouldNotifySync)
    }

    private func persist(notifySync: Bool = true) {
        persist(using: .immediate, notifySync: notifySync)
    }

    private func persist(using mode: PersistenceMode, notifySync: Bool = true) {
        let archive = makeArchive()

        switch mode {
        case .immediate:
            pendingPersistToken += 1
            hasPendingSyncNotification = false
            pendingPersistWorkItem?.cancel()
            pendingPersistWorkItem = nil
            persistArchive(archive, notifySync: notifySync)
        case .deferred:
            scheduleDeferredPersist(archive, notifySync: notifySync)
        }
    }

    private func persistArchive(_ archive: TodayMdArchive, notifySync: Bool) {
        do {
            try database.replaceAll(with: archive)
            if notifySync {
                syncHandler?()
            }
        } catch {
            assertionFailure("Failed to persist store: \(error.localizedDescription)")
        }
    }

    private func scheduleDeferredPersist(_ archive: TodayMdArchive, notifySync: Bool) {
        hasPendingSyncNotification = hasPendingSyncNotification || notifySync
        pendingPersistToken += 1
        let token = pendingPersistToken

        pendingPersistWorkItem?.cancel()

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [database] in
            guard let workItem, !workItem.isCancelled else { return }

            do {
                try database.replaceAll(with: archive)
                Task { @MainActor [weak self] in
                    self?.completeDeferredPersistence(token: token, error: nil)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.completeDeferredPersistence(token: token, error: error)
                }
            }
        }

        pendingPersistWorkItem = workItem
        persistenceQueue.asyncAfter(deadline: .now() + Self.deferredPersistenceDelay, execute: workItem!)
    }

    private func completeDeferredPersistence(token: Int, error: Error?) {
        guard token == pendingPersistToken else { return }

        pendingPersistWorkItem = nil
        let shouldNotifySync = hasPendingSyncNotification
        hasPendingSyncNotification = false

        if let error {
            assertionFailure("Failed to persist store: \(error.localizedDescription)")
            return
        }

        if shouldNotifySync {
            syncHandler?()
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

    private func insertTask(
        _ task: TaskItem,
        into list: TaskList?,
        in block: TimeBlock,
        preferredSortOrder: Int
    ) {
        let tasks = list?.items ?? unassignedTasks
        let blockTasks = tasks.filter { $0.block == block }
        let insertionSortOrder = max(0, min(preferredSortOrder, blockTasks.count))

        for existingTask in blockTasks where existingTask.sortOrder >= insertionSortOrder {
            existingTask.sortOrder += 1
        }

        task.sortOrder = insertionSortOrder

        if let list {
            list.items.append(task)
        } else {
            unassignedTasks.append(task)
        }
    }

    private func shiftSortOrderForNewTask(atTopOf list: TaskList?, in block: TimeBlock) {
        let tasks = list?.items ?? unassignedTasks
        for task in tasks where task.block == block {
            task.sortOrder += 1
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
