import AppKit
import EventKit
import Foundation

enum TodayMdRemindersAuthorizationState: Equatable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    var settingsActivationPath: String? {
        switch self {
        case .denied, .restricted, .writeOnly:
            return "System Settings > Privacy & Security > Reminders"
        case .notDetermined, .fullAccess:
            return nil
        }
    }

    var label: String {
        switch self {
        case .notDetermined:
            return "Not Connected"
        case .denied:
            return "Access Denied"
        case .restricted:
            return "Restricted"
        case .writeOnly:
            return "Write Only"
        case .fullAccess:
            return "Connected"
        }
    }

    var canReadReminders: Bool {
        self == .fullAccess
    }

    var guidance: String {
        switch self {
        case .notDetermined:
            return "Connect Apple Reminders so today-md can mirror tasks into a managed Reminders list and import edits back."
        case .denied:
            return "today-md cannot read Reminders until you allow access in \(settingsActivationPath ?? "System Settings")."
        case .restricted:
            return "Reminders access is restricted on this Mac. Review \(settingsActivationPath ?? "System Settings"), but device policies may still block changes."
        case .writeOnly:
            return "today-md can write reminders, but two-way sync requires full access. Change it in \(settingsActivationPath ?? "System Settings")."
        case .fullAccess:
            return "today-md can mirror tasks into Apple Reminders and pull reminder edits back into the app."
        }
    }

    var resolutionActionTitle: String {
        switch self {
        case .notDetermined:
            return "Connect Reminders"
        case .denied, .restricted, .writeOnly:
            return "Open Reminder Settings"
        case .fullAccess:
            return "Refresh Reminders"
        }
    }

    var resolutionActionSubtitle: String {
        switch self {
        case .notDetermined:
            return "Grant full access so today-md can read and write Apple Reminders."
        case .denied:
            return "Open \(settingsActivationPath ?? "System Settings") and allow today-md to access Reminders."
        case .restricted:
            return "Open \(settingsActivationPath ?? "System Settings") to review access. This Mac may still block changes."
        case .writeOnly:
            return "Open \(settingsActivationPath ?? "System Settings") and change today-md to Full Access."
        case .fullAccess:
            return "Refresh the managed Reminders list and import the latest reminder changes."
        }
    }

    var resolutionActionSystemImage: String {
        switch self {
        case .notDetermined:
            return "checklist.checked"
        case .denied, .restricted, .writeOnly:
            return "gearshape"
        case .fullAccess:
            return "arrow.clockwise"
        }
    }
}

struct TodayMdReminderSyncSnapshot: Codable {
    let taskID: UUID
    let reminderIdentifier: String
    let canonicalHash: String
    let blockRaw: String
    let listID: UUID?
    let scheduledDate: Date?

    init(
        taskID: UUID,
        reminderIdentifier: String,
        canonicalHash: String,
        blockRaw: String,
        listID: UUID?,
        scheduledDate: Date? = nil
    ) {
        self.taskID = taskID
        self.reminderIdentifier = reminderIdentifier
        self.canonicalHash = canonicalHash
        self.blockRaw = blockRaw
        self.listID = listID
        self.scheduledDate = scheduledDate
    }
}

private struct TodayMdReminderSyncPersistedState: Codable {
    var syncEnabled: Bool
    var managedCalendarIdentifier: String?
    var lastSyncAt: Date?
    var lastError: String?
    var status: SyncStatus
    var snapshots: [TodayMdReminderSyncSnapshot]

    static func initial() -> TodayMdReminderSyncPersistedState {
        TodayMdReminderSyncPersistedState(
            syncEnabled: false,
            managedCalendarIdentifier: nil,
            lastSyncAt: nil,
            lastError: nil,
            status: .disabled,
            snapshots: []
        )
    }
}

struct TodayMdReminderMetadata {
    struct ParsedNotes {
        let taskID: UUID?
        let block: TimeBlock?
        let scheduledDate: Date?
        let visibleNote: String?
        let needsMetadataRefresh: Bool
    }

    static func parse(
        url: URL?,
        notes rawNotes: String?,
        dueDateComponents: DateComponents?,
        fallback: TodayMdReminderSyncSnapshot?,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> ParsedNotes {
        let legacyNotes = parseLegacyNotes(rawNotes)
        let parsedTaskID = taskID(from: url) ?? legacyNotes.taskID ?? fallback?.taskID
        let parsedScheduledDate = scheduledDate(from: dueDateComponents, calendar: calendar)
        let parsedBlock = block(from: dueDateComponents, calendar: calendar, referenceDate: referenceDate)
            ?? legacyNotes.block
            ?? fallback.flatMap { TimeBlock(rawValue: $0.blockRaw) }
        let dueDateNeedsRefresh = dueDateNeedsRefresh(
            scheduledDate: parsedScheduledDate,
            for: parsedBlock ?? .backlog,
            current: dueDateComponents,
            calendar: calendar,
            referenceDate: referenceDate
        )

        return ParsedNotes(
            taskID: parsedTaskID,
            block: parsedBlock ?? .backlog,
            scheduledDate: parsedScheduledDate,
            visibleNote: legacyNotes.visibleNote,
            needsMetadataRefresh: taskID(from: url) == nil || legacyNotes.hadLegacyMetadata || dueDateNeedsRefresh
        )
    }

    static func notes(for task: TodayMdReminderTaskSnapshot) -> String? {
        normalizedOptionalString(task.noteContent)
    }

    static func url(for task: TodayMdReminderTaskSnapshot) -> URL? {
        URL(string: "\(taskURLScheme)://\(taskURLHost)/\(task.id.uuidString.lowercased())")
    }

    static func dueDateComponents(
        for block: TimeBlock,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> DateComponents? {
        let targetDate: Date?

        switch block {
        case .today:
            targetDate = calendar.startOfDay(for: referenceDate)
        case .thisWeek:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                targetDate = nil
                break
            }

            let lastDayOfWeek = calendar.date(byAdding: .day, value: -1, to: weekInterval.end)
            targetDate = lastDayOfWeek.map(calendar.startOfDay(for:))
        case .backlog:
            targetDate = nil
        }

        guard let targetDate else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        return components
    }

    static func dueDateComponents(
        for task: TodayMdReminderTaskSnapshot,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> DateComponents? {
        if let scheduledDate = task.scheduledDate {
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDate)
        }

        return dueDateComponents(for: task.block, calendar: calendar, referenceDate: referenceDate)
    }

    static func block(
        from dueDateComponents: DateComponents?,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> TimeBlock? {
        guard let dueDateComponents,
              let dueDate = calendar.date(from: dueDateComponents) else {
            return nil
        }

        if calendar.isDate(dueDate, inSameDayAs: referenceDate) {
            return .today
        }

        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
           dueDate >= weekInterval.start,
           dueDate < weekInterval.end {
            return .thisWeek
        }

        return .backlog
    }

    static func scheduledDate(
        from dueDateComponents: DateComponents?,
        calendar: Calendar = .current
    ) -> Date? {
        guard hasExplicitTime(in: dueDateComponents),
              let dueDateComponents,
              let dueDate = calendar.date(from: dueDateComponents) else {
            return nil
        }

        return dueDate
    }

    private struct LegacyNotes {
        let taskID: UUID?
        let block: TimeBlock?
        let visibleNote: String?
        let hadLegacyMetadata: Bool
    }

    private static func parseLegacyNotes(_ rawNotes: String?) -> LegacyNotes {
        guard let rawNotes = normalizedOptionalString(rawNotes) else {
            return LegacyNotes(taskID: nil, block: nil, visibleNote: nil, hadLegacyMetadata: false)
        }

        let sections = rawNotes
            .components(separatedBy: "\n\n")
            .compactMap(normalizedOptionalString)
        let lines = rawNotes
            .components(separatedBy: .newlines)
            .compactMap(normalizedOptionalString)

        let taskID = lines
            .first(where: { $0.hasPrefix(legacyTaskIDPrefix) })
            .flatMap { UUID(uuidString: String($0.dropFirst(legacyTaskIDPrefix.count))) }
        let block = lines
            .first(where: { $0.hasPrefix(legacyBlockPrefix) })
            .flatMap { TimeBlock(rawValue: String($0.dropFirst(legacyBlockPrefix.count))) }

        let visibleSections = sections.filter { section in
            section != legacyMarker
                && !section.hasPrefix(legacyTaskIDPrefix)
                && !section.hasPrefix(legacyBlockPrefix)
                && !section.hasPrefix(legacyListIDPrefix)
        }
        let visibleNote = normalizedOptionalString(visibleSections.joined(separator: "\n\n"))
        let hadLegacyMetadata = visibleSections.count != sections.count

        return LegacyNotes(
            taskID: taskID,
            block: block,
            visibleNote: visibleNote,
            hadLegacyMetadata: hadLegacyMetadata
        )
    }

    private static func dueDateNeedsRefresh(
        scheduledDate: Date?,
        for block: TimeBlock,
        current dueDateComponents: DateComponents?,
        calendar: Calendar,
        referenceDate: Date
    ) -> Bool {
        if let scheduledDate {
            let expected = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDate)
            return !sameDueDate(dueDateComponents, expected, includingTime: true)
        }

        switch block {
        case .backlog:
            return dueDateComponents != nil
        case .today, .thisWeek:
            let expected = Self.dueDateComponents(for: block, calendar: calendar, referenceDate: referenceDate)
            return !sameDueDate(dueDateComponents, expected, includingTime: false)
        }
    }

    private static func hasExplicitTime(in dueDateComponents: DateComponents?) -> Bool {
        dueDateComponents?.hour != nil || dueDateComponents?.minute != nil || dueDateComponents?.second != nil
    }

    private static func sameDueDate(
        _ lhs: DateComponents?,
        _ rhs: DateComponents?,
        includingTime: Bool
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            let dateMatches = lhs.year == rhs.year
                && lhs.month == rhs.month
                && lhs.day == rhs.day
            guard dateMatches else { return false }

            if includingTime {
                return lhs.hour == rhs.hour && lhs.minute == rhs.minute
            }

            return true
        default:
            return false
        }
    }

    private static func taskID(from url: URL?) -> UUID? {
        guard let url,
              url.scheme == taskURLScheme,
              url.host == taskURLHost else {
            return nil
        }

        return UUID(uuidString: url.lastPathComponent)
    }

    static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static let taskURLScheme = "today-md"
    private static let taskURLHost = "reminder-task"
    private static let legacyMarker = "today-md reminder"
    private static let legacyTaskIDPrefix = "Task ID: "
    private static let legacyBlockPrefix = "Block: "
    private static let legacyListIDPrefix = "List ID: "
}

struct TodayMdReminderTaskSnapshot: Hashable {
    let id: UUID
    let title: String
    let isDone: Bool
    let noteContent: String?
    let block: TimeBlock
    let listID: UUID?
    let creationDate: Date
    let modifiedDate: Date
    let scheduledDate: Date?

    init(task: TaskItem) {
        self.id = task.id
        self.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title
        self.isDone = task.isDone
        self.noteContent = TodayMdReminderMetadata.normalizedOptionalString(task.note?.content)
        self.block = task.block
        self.listID = task.list?.id
        self.creationDate = task.creationDate
        self.modifiedDate = Self.effectiveModifiedDate(for: task)
        self.scheduledDate = task.scheduledDate
    }

    init(
        id: UUID,
        title: String,
        isDone: Bool,
        noteContent: String?,
        block: TimeBlock,
        listID: UUID?,
        creationDate: Date,
        modifiedDate: Date,
        scheduledDate: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : title
        self.isDone = isDone
        self.noteContent = TodayMdReminderMetadata.normalizedOptionalString(noteContent)
        self.block = block
        self.listID = listID
        self.creationDate = creationDate
        self.modifiedDate = modifiedDate
        self.scheduledDate = scheduledDate
    }

    func canonicalHash() -> String {
        let payload = [
            id.uuidString.lowercased(),
            title,
            isDone ? "1" : "0",
            noteContent ?? "",
            block.rawValue,
            scheduledDate.map(Self.iso8601String(from:)) ?? ""
        ].joined(separator: "\u{1F}")

        return payload
    }

    func makeTask(listsByID: [UUID: TaskList]) -> TaskItem {
        let note = noteContent.map { TaskNote(content: $0, lastModified: modifiedDate) }
        let subtasks = Self.makeSubtasks(from: noteContent)
        let task = TaskItem(
            id: id,
            title: title,
            block: block,
            schedulingState: scheduledDate == nil ? .unscheduled : .scheduled,
            sortOrder: 0,
            creationDate: creationDate,
            modifiedDate: modifiedDate,
            scheduledDate: scheduledDate,
            isDone: isDone,
            subtasks: subtasks,
            note: note
        )
        task.list = nil
        return task
    }

    static func makeSubtasks(from noteContent: String?) -> [SubTask] {
        guard let noteContent = TodayMdReminderMetadata.normalizedOptionalString(noteContent) else {
            return []
        }

        return noteContent
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                    return SubTask(title: String(trimmed.dropFirst(6)), isCompleted: true, sortOrder: index)
                }

                if trimmed.hasPrefix("- [ ] ") {
                    return SubTask(title: String(trimmed.dropFirst(6)), isCompleted: false, sortOrder: index)
                }

                return nil
            }
    }

    private static func effectiveModifiedDate(for task: TaskItem) -> Date {
        max(task.modifiedDate, task.note?.lastModified ?? task.modifiedDate)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func effectiveModifiedDate(for archive: TodayMdArchive.TaskArchive) -> Date {
        max(archive.modifiedDate, archive.note?.lastModified ?? archive.modifiedDate)
    }
}

struct TodayMdReminderRecord {
    let identifier: String
    let task: TodayMdReminderTaskSnapshot
    let needsMetadataRefresh: Bool
}

enum TodayMdReminderMutation: Equatable {
    case create(TodayMdReminderTaskSnapshot)
    case update(reminderIdentifier: String, task: TodayMdReminderTaskSnapshot)
    case delete(reminderIdentifier: String)
}

struct TodayMdReminderSyncOutcome {
    let archive: TodayMdArchive
    let mutations: [TodayMdReminderMutation]
}

enum TodayMdReminderSyncEngine {
    static func sync(
        localArchive: TodayMdArchive,
        remoteRecords: [TodayMdReminderRecord],
        snapshots: [TodayMdReminderSyncSnapshot]
    ) -> TodayMdReminderSyncOutcome {
        let hydrated = localArchive.instantiate()
        var lists = hydrated.lists
        var unassignedTasks = hydrated.unassignedTasks
        let listsByID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })

        func localTaskMap() -> [UUID: TaskItem] {
            Dictionary(uniqueKeysWithValues: (lists.flatMap(\.items) + unassignedTasks).map { ($0.id, $0) })
        }

        let remoteByTaskID = Dictionary(uniqueKeysWithValues: remoteRecords.map { ($0.task.id, $0) })
        let remoteByIdentifier = Dictionary(uniqueKeysWithValues: remoteRecords.map { ($0.identifier, $0) })
        var usedRemoteIdentifiers = Set<String>()
        var mutations: [TodayMdReminderMutation] = []

        func applyRemote(_ remoteTask: TodayMdReminderTaskSnapshot, to existingTask: TaskItem?) {
            if let existingTask {
                let previousBlock = existingTask.block
                existingTask.title = remoteTask.title
                existingTask.isDone = remoteTask.isDone
                existingTask.block = remoteTask.block
                existingTask.creationDate = remoteTask.creationDate
                existingTask.modifiedDate = remoteTask.modifiedDate
                existingTask.note = remoteTask.noteContent.map { TaskNote(content: $0, lastModified: remoteTask.modifiedDate) }
                existingTask.subtasks = TodayMdReminderTaskSnapshot.makeSubtasks(from: remoteTask.noteContent)

                if previousBlock != existingTask.block {
                    existingTask.sortOrder = 0
                }
            } else {
                let task = remoteTask.makeTask(listsByID: listsByID)
                if let list = task.list {
                    list.items.append(task)
                } else {
                    unassignedTasks.append(task)
                }
            }
        }

        func removeLocalTask(id: UUID) {
            for list in lists {
                list.items.removeAll { $0.id == id }
            }
            unassignedTasks.removeAll { $0.id == id }
        }

        for snapshot in snapshots {
            let currentLocalTasks = localTaskMap()
            let localTask = currentLocalTasks[snapshot.taskID]
            let remoteRecord = remoteByTaskID[snapshot.taskID] ?? remoteByIdentifier[snapshot.reminderIdentifier]
            if let remoteRecord {
                usedRemoteIdentifiers.insert(remoteRecord.identifier)
            }

            let localSnapshot = localTask.map(TodayMdReminderTaskSnapshot.init(task:))
            let localHash = localSnapshot?.canonicalHash()
            let remoteHash = remoteRecord?.task.canonicalHash()

            switch (localSnapshot, remoteRecord) {
            case (.some(let localSnapshot), .some(let remoteRecord)):
                let localChanged = localHash != snapshot.canonicalHash
                let remoteChanged = remoteHash != snapshot.canonicalHash

                if localChanged && remoteChanged {
                    if localSnapshot.modifiedDate >= remoteRecord.task.modifiedDate {
                        mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: localSnapshot))
                    } else {
                        applyRemote(remoteRecord.task, to: localTask)
                    }
                } else if localChanged {
                    mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: localSnapshot))
                } else if remoteChanged {
                    applyRemote(remoteRecord.task, to: localTask)
                } else if remoteRecord.needsMetadataRefresh {
                    mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: localSnapshot))
                }

            case (.some(let localSnapshot), .none):
                if localHash == snapshot.canonicalHash {
                    removeLocalTask(id: snapshot.taskID)
                } else {
                    mutations.append(.create(localSnapshot))
                }

            case (.none, .some(let remoteRecord)):
                if remoteHash == snapshot.canonicalHash {
                    mutations.append(.delete(reminderIdentifier: remoteRecord.identifier))
                } else {
                    applyRemote(remoteRecord.task, to: nil)
                    if remoteRecord.needsMetadataRefresh {
                        mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: remoteRecord.task))
                    }
                }

            case (.none, .none):
                break
            }
        }

        for remoteRecord in remoteRecords where !usedRemoteIdentifiers.contains(remoteRecord.identifier) {
            let currentLocalTasks = localTaskMap()
            if let localTask = currentLocalTasks[remoteRecord.task.id] {
                let localSnapshot = TodayMdReminderTaskSnapshot(task: localTask)
                if remoteRecord.task.modifiedDate > localSnapshot.modifiedDate {
                    applyRemote(remoteRecord.task, to: localTask)
                } else {
                    mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: localSnapshot))
                }

                if remoteRecord.needsMetadataRefresh {
                    let refreshedTask = localTaskMap()[remoteRecord.task.id].map(TodayMdReminderTaskSnapshot.init(task:)) ?? remoteRecord.task
                    mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: refreshedTask))
                }
                continue
            }

            applyRemote(remoteRecord.task, to: nil)
            let importedTask = localTaskMap()[remoteRecord.task.id].map(TodayMdReminderTaskSnapshot.init(task:)) ?? remoteRecord.task
            if remoteRecord.needsMetadataRefresh {
                mutations.append(.update(reminderIdentifier: remoteRecord.identifier, task: importedTask))
            }
        }

        let syncedTaskIDs = Set(snapshots.map(\.taskID))
        for task in localTaskMap().values where !syncedTaskIDs.contains(task.id) && remoteByTaskID[task.id] == nil {
            mutations.append(.create(TodayMdReminderTaskSnapshot(task: task)))
        }

        normalizeLists(&lists, unassignedTasks: &unassignedTasks)

        return TodayMdReminderSyncOutcome(
            archive: TodayMdArchive(lists: lists, unassignedTasks: unassignedTasks),
            mutations: deduplicated(mutations)
        )
    }

    private static func deduplicated(_ mutations: [TodayMdReminderMutation]) -> [TodayMdReminderMutation] {
        var latestCreateByTaskID: [UUID: TodayMdReminderTaskSnapshot] = [:]
        var latestUpdateByReminderID: [String: TodayMdReminderTaskSnapshot] = [:]
        var deletedReminderIDs = Set<String>()

        for mutation in mutations {
            switch mutation {
            case .create(let task):
                latestCreateByTaskID[task.id] = task
            case .update(let reminderIdentifier, let task):
                guard !deletedReminderIDs.contains(reminderIdentifier) else { continue }
                latestUpdateByReminderID[reminderIdentifier] = task
            case .delete(let reminderIdentifier):
                deletedReminderIDs.insert(reminderIdentifier)
                latestUpdateByReminderID.removeValue(forKey: reminderIdentifier)
            }
        }

        var deduplicated: [TodayMdReminderMutation] = latestCreateByTaskID.values
            .sorted { $0.creationDate < $1.creationDate }
            .map(TodayMdReminderMutation.create)

        deduplicated.append(contentsOf: latestUpdateByReminderID.keys.sorted().compactMap { identifier in
            latestUpdateByReminderID[identifier].map { .update(reminderIdentifier: identifier, task: $0) }
        })
        deduplicated.append(contentsOf: deletedReminderIDs.sorted().map(TodayMdReminderMutation.delete))
        return deduplicated
    }

    private static func normalizeLists(_ lists: inout [TaskList], unassignedTasks: inout [TaskItem]) {
        for (index, list) in lists.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            list.sortOrder = index
        }

        for list in lists {
            normalizeTaskSortOrder(in: list.items)
        }

        normalizeTaskSortOrder(in: unassignedTasks)
    }

    private static func normalizeTaskSortOrder(in tasks: [TaskItem]) {
        for block in TimeBlock.allCases {
            let ordered = tasks
                .filter { $0.block == block }
                .sorted(by: taskSort)

            for (index, task) in ordered.enumerated() {
                task.sortOrder = index
            }
        }
    }
}

@MainActor
final class TodayMdReminderSyncService: ObservableObject {
    private static let eventStoreRetryDelayNanoseconds: UInt64 = 500_000_000

    @Published private(set) var authorizationStatus: TodayMdRemindersAuthorizationState
    @Published private(set) var syncEnabled = false
    @Published private(set) var status: SyncStatus = .disabled
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var managedListTitle: String

    private let eventStore: EKEventStore
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults
    private var persistedState: TodayMdReminderSyncPersistedState
    private weak var store: TodayMdStore?
    private var eventStoreChangeObserver: NSObjectProtocol?
    private var pendingSyncWorkItem: DispatchWorkItem?
    private var isSyncInProgress = false

    init(
        eventStore: EKEventStore = EKEventStore(),
        notificationCenter: NotificationCenter = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.eventStore = eventStore
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
        self.persistedState = Self.loadState(from: userDefaults)
        self.authorizationStatus = .notDetermined
        self.managedListTitle = Self.managedCalendarTitle
        self.authorizationStatus = currentAuthorizationStatus()
        applyPersistedState()
        startObservingEventStoreChanges()
    }

    func attach(store: TodayMdStore) {
        self.store = store
        store.addPersistenceObserver { [weak self] in
            self?.handleLocalStoreChange()
        }
    }

    func handleAppLaunchIfNeeded() {
        refreshIfNeeded()
        if syncEnabled {
            syncNow()
        }
    }

    func handleAppDidBecomeActive() {
        refreshIfNeeded()
        if syncEnabled {
            syncNow()
        }
    }

    func enableSync() {
        updatePersistedState { state in
            state.syncEnabled = true
            state.status = .idle
            state.lastError = nil
        }
        syncNow()
    }

    func disableSync() {
        pendingSyncWorkItem?.cancel()
        pendingSyncWorkItem = nil
        updatePersistedState { state in
            state.syncEnabled = false
            state.status = .disabled
            state.lastError = nil
        }
    }

    func refreshIfNeeded() {
        authorizationStatus = currentAuthorizationStatus()
        if !authorizationStatus.canReadReminders, syncEnabled {
            updatePersistedState { state in
                state.status = .error
                state.lastError = authorizationStatus.guidance
            }
        }
    }

    func requestFullAccess() {
        lastError = nil

        guard Self.hasReminderUsageDescription else {
            lastError = "Reminders access requires launching today-md as a macOS app bundle. Run it from Xcode or use `bash scripts/dev-run.sh` instead of `swift run`."
            return
        }

        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = self.currentAuthorizationStatus()

                if let error {
                    self.lastError = error.localizedDescription
                    return
                }

                if granted {
                    self.enableSync()
                } else {
                    self.lastError = Self.authorizationFailureMessage(for: self.authorizationStatus)
                }
            }
        }
    }

    func openReminderPrivacySettings() {
        lastError = nil

        if let url = Self.remindersPrivacySettingsURL, NSWorkspace.shared.open(url) {
            return
        }

        if NSWorkspace.shared.open(Self.systemSettingsAppURL) {
            return
        }

        lastError = "Couldn't open System Settings automatically. Go to \(authorizationStatus.settingsActivationPath ?? "System Settings > Privacy & Security > Reminders")."
    }

    func resolveAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            requestFullAccess()
        case .denied, .restricted, .writeOnly:
            openReminderPrivacySettings()
        case .fullAccess:
            refreshIfNeeded()
        }
    }

    func syncNow() {
        guard syncEnabled else { return }
        guard authorizationStatus.canReadReminders else {
            updatePersistedState { state in
                state.status = .error
                state.lastError = authorizationStatus.guidance
            }
            return
        }
        guard let store else { return }
        guard !isSyncInProgress else { return }

        isSyncInProgress = true
        updatePersistedState { state in
            state.status = .syncing
            state.lastError = nil
        }

        Task {
            do {
                try await self.performSync(store: store)
                self.isSyncInProgress = false
            } catch {
                self.isSyncInProgress = false
                self.recordError(error)
            }
        }
    }

    private func handleLocalStoreChange() {
        guard syncEnabled else { return }
        guard !isSyncInProgress else { return }
        scheduleDebouncedSync()
    }

    private func scheduleDebouncedSync() {
        pendingSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncNow()
        }

        pendingSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func startObservingEventStoreChanges() {
        eventStoreChangeObserver = notificationCenter.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.syncEnabled, !self.isSyncInProgress else { return }
                self.scheduleDebouncedSync()
            }
        }
    }

    private func performSync(store: TodayMdStore) async throws {
        let managedCalendar = try await resolveManagedCalendar()
        let snapshotLookup = Dictionary(uniqueKeysWithValues: persistedState.snapshots.map { ($0.reminderIdentifier, $0) })
        let remoteRecords = try await fetchReminderRecords(in: managedCalendar, snapshotLookup: snapshotLookup)
        let localArchive = store.makeArchive()
        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: localArchive,
            remoteRecords: remoteRecords,
            snapshots: persistedState.snapshots
        )

        let localRevision = try TodayMdObsidianBridge.contentRevisionID(for: localArchive)
        let mergedRevision = try TodayMdObsidianBridge.contentRevisionID(for: outcome.archive)
        if localRevision != mergedRevision {
            store.applyRemoteArchive(outcome.archive, notifySync: true)
        }

        try applyMutations(outcome.mutations, in: managedCalendar)

        let refreshedRecords = try await fetchReminderRecords(
            in: managedCalendar,
            snapshotLookup: Dictionary(uniqueKeysWithValues: persistedState.snapshots.map { ($0.reminderIdentifier, $0) })
        )
        let refreshedArchive = store.makeArchive()
        let refreshedSnapshots = makeSnapshots(localArchive: refreshedArchive, remoteRecords: refreshedRecords)

        authorizationStatus = .fullAccess
        updatePersistedState { state in
            state.snapshots = refreshedSnapshots
            state.lastSyncAt = Date()
            state.lastError = nil
            state.status = .idle
        }
    }

    private func resolveManagedCalendar() async throws -> EKCalendar {
        do {
            return try resolveManagedCalendarWithoutRetry()
        } catch TodayMdReminderSyncError.noWritableReminderSource {
            eventStore.reset()
            try? await Task.sleep(nanoseconds: Self.eventStoreRetryDelayNanoseconds)
            return try resolveManagedCalendarWithoutRetry()
        }
    }

    private func resolveManagedCalendarWithoutRetry() throws -> EKCalendar {
        if let identifier = persistedState.managedCalendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: identifier) {
            managedListTitle = calendar.title
            return calendar
        }

        if persistedState.managedCalendarIdentifier != nil {
            updatePersistedState { state in
                state.managedCalendarIdentifier = nil
            }
        }

        if let existingCalendar = eventStore.calendars(for: .reminder)
            .first(where: { calendar in
                calendar.allowsContentModifications
                    && calendar.title.compare(Self.managedCalendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
            updatePersistedState { state in
                state.managedCalendarIdentifier = existingCalendar.calendarIdentifier
            }
            managedListTitle = existingCalendar.title
            return existingCalendar
        }

        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = Self.managedCalendarTitle
        calendar.cgColor = NSColor.systemOrange.cgColor
        calendar.source = try preferredReminderSource()
        try eventStore.saveCalendar(calendar, commit: true)

        updatePersistedState { state in
            state.managedCalendarIdentifier = calendar.calendarIdentifier
        }

        managedListTitle = calendar.title
        return calendar
    }

    private func preferredReminderSource() throws -> EKSource {
        if let source = eventStore.defaultCalendarForNewReminders()?.source {
            return source
        }

        let writableReminderCalendars = eventStore.calendars(for: .reminder)
            .filter(\.allowsContentModifications)

        if let source = writableReminderCalendars.first?.source {
            return source
        }

        if let source = eventStore.sources.first(where: { source in
            !source.calendars(for: .reminder).isEmpty
        }) {
            return source
        }

        if let source = eventStore.sources.first(where: { source in
            source.sourceType == .calDAV || source.sourceType == .local || source.sourceType == .exchange
        }) {
            return source
        }

        throw TodayMdReminderSyncError.noWritableReminderSource
    }

    private func fetchReminderRecords(
        in calendar: EKCalendar,
        snapshotLookup: [String: TodayMdReminderSyncSnapshot]
    ) async throws -> [TodayMdReminderRecord] {
        let reminders = await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: [calendar])
            eventStore.fetchReminders(matching: predicate) { reminders in
                let records = (reminders ?? []).map { reminder in
                    let identifier = reminder.calendarItemIdentifier
                    let fallback = snapshotLookup[identifier]
                    let parsed = TodayMdReminderMetadata.parse(
                        url: reminder.url,
                        notes: reminder.notes,
                        dueDateComponents: reminder.dueDateComponents,
                        fallback: fallback
                    )
                    let reminderTitle = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? reminder.title!
                        : "Untitled Reminder"
                    let taskID = parsed.taskID ?? UUID()
                    let task = TodayMdReminderTaskSnapshot(
                        id: taskID,
                        title: reminderTitle,
                        isDone: reminder.isCompleted,
                        noteContent: parsed.visibleNote,
                        block: parsed.block ?? .backlog,
                        listID: nil,
                        creationDate: reminder.creationDate ?? Date(),
                        modifiedDate: reminder.lastModifiedDate ?? reminder.creationDate ?? Date(),
                        scheduledDate: parsed.scheduledDate
                    )

                    return TodayMdReminderRecord(
                        identifier: identifier,
                        task: task,
                        needsMetadataRefresh: parsed.needsMetadataRefresh
                    )
                }

                continuation.resume(returning: records)
            }
        }
        return reminders
    }

    private func applyMutations(_ mutations: [TodayMdReminderMutation], in calendar: EKCalendar) throws {
        guard !mutations.isEmpty else { return }

        for mutation in mutations {
            switch mutation {
            case .create(let task):
                let reminder = EKReminder(eventStore: eventStore)
                reminder.calendar = calendar
                configure(reminder, with: task)
                try eventStore.save(reminder, commit: false)

            case .update(let reminderIdentifier, let task):
                guard let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else { continue }
                reminder.calendar = calendar
                configure(reminder, with: task)
                try eventStore.save(reminder, commit: false)

            case .delete(let reminderIdentifier):
                guard let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else { continue }
                try eventStore.remove(reminder, commit: false)
            }
        }

        try eventStore.commit()
    }

    private func configure(_ reminder: EKReminder, with task: TodayMdReminderTaskSnapshot) {
        reminder.title = task.title
        reminder.notes = TodayMdReminderMetadata.notes(for: task)
        reminder.url = TodayMdReminderMetadata.url(for: task)
        reminder.dueDateComponents = TodayMdReminderMetadata.dueDateComponents(for: task)
        reminder.isCompleted = task.isDone
        reminder.completionDate = task.isDone ? task.modifiedDate : nil
    }

    private func makeSnapshots(
        localArchive: TodayMdArchive,
        remoteRecords: [TodayMdReminderRecord]
    ) -> [TodayMdReminderSyncSnapshot] {
        struct LocalArchiveTask {
            let task: TodayMdArchive.TaskArchive
            let listID: UUID?
        }

        var localTasks: [UUID: LocalArchiveTask] = [:]
        for list in localArchive.lists {
            for task in list.tasks {
                localTasks[task.id] = LocalArchiveTask(task: task, listID: list.id)
            }
        }

        for task in localArchive.unassignedTasks {
            localTasks[task.id] = LocalArchiveTask(task: task, listID: nil)
        }

        return remoteRecords.compactMap { record in
            guard let localTask = localTasks[record.task.id] else { return nil }
            return TodayMdReminderSyncSnapshot(
                taskID: localTask.task.id,
                reminderIdentifier: record.identifier,
                canonicalHash: TodayMdReminderTaskSnapshot(
                    id: localTask.task.id,
                    title: localTask.task.title,
                    isDone: localTask.task.isDone,
                    noteContent: localTask.task.note?.content,
                    block: TimeBlock(rawValue: localTask.task.blockRaw) ?? .backlog,
                    listID: localTask.listID,
                    creationDate: localTask.task.creationDate,
                    modifiedDate: TodayMdReminderTaskSnapshot.effectiveModifiedDate(for: localTask.task),
                    scheduledDate: localTask.task.scheduledDate
                ).canonicalHash(),
                blockRaw: localTask.task.blockRaw,
                listID: localTask.listID,
                scheduledDate: localTask.task.scheduledDate
            )
        }
        .sorted { $0.taskID.uuidString < $1.taskID.uuidString }
    }

    private func recordError(_ error: Error) {
        updatePersistedState { state in
            state.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state.status = .error
        }
    }

    private func currentAuthorizationStatus() -> TodayMdRemindersAuthorizationState {
        let reported = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .reminder))
        let hasManagedCalendar = persistedState.managedCalendarIdentifier
            .flatMap(eventStore.calendar(withIdentifier:)) != nil
        let hasVisibleReminderData = eventStore.defaultCalendarForNewReminders() != nil
            || !eventStore.calendars(for: .reminder).isEmpty
        return Self.resolvedAuthorizationStatus(
            reported: reported,
            syncEnabled: persistedState.syncEnabled,
            lastSyncAt: persistedState.lastSyncAt,
            hasManagedCalendar: hasManagedCalendar,
            hasVisibleReminderData: hasVisibleReminderData
        )
    }

    private func updatePersistedState(_ mutate: (inout TodayMdReminderSyncPersistedState) -> Void) {
        mutate(&persistedState)
        applyPersistedState()
        saveState()
    }

    private func applyPersistedState() {
        syncEnabled = persistedState.syncEnabled
        status = persistedState.status
        lastSyncAt = persistedState.lastSyncAt
        lastError = persistedState.lastError
    }

    private func saveState() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(persistedState) else { return }
        userDefaults.set(data, forKey: Self.persistedStateDefaultsKey)
    }

    private static func loadState(from userDefaults: UserDefaults) -> TodayMdReminderSyncPersistedState {
        guard
            let data = userDefaults.data(forKey: persistedStateDefaultsKey),
            let state = try? JSONDecoder().decode(TodayMdReminderSyncPersistedState.self, from: data)
        else {
            return .initial()
        }

        return state
    }

    static func resolvedAuthorizationStatus(
        reported: TodayMdRemindersAuthorizationState,
        syncEnabled: Bool,
        lastSyncAt: Date?,
        hasManagedCalendar: Bool,
        hasVisibleReminderData: Bool
    ) -> TodayMdRemindersAuthorizationState {
        guard reported == .notDetermined else { return reported }

        if hasManagedCalendar {
            return .fullAccess
        }

        if hasVisibleReminderData {
            return .fullAccess
        }

        return .notDetermined
    }

    private static func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> TodayMdRemindersAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .writeOnly:
            return .writeOnly
        case .fullAccess, .authorized:
            return .fullAccess
        @unknown default:
            return .denied
        }
    }

    private static func authorizationFailureMessage(for status: TodayMdRemindersAuthorizationState) -> String {
        switch status {
        case .notDetermined:
            return "macOS did not complete the Reminders permission request. Close and reopen today-md, then try Connect Reminders again. If the prompt still does not appear, open System Settings > Privacy & Security > Reminders and allow today-md manually."
        case .denied:
            return "Reminders access is off for today-md. Enable it in System Settings > Privacy & Security > Reminders."
        case .restricted:
            return "Reminders access is restricted on this Mac. Review System Settings > Privacy & Security > Reminders, but device policies may still block changes."
        case .writeOnly:
            return "today-md only has write-only Reminders access. Change it to Full Access in System Settings > Privacy & Security > Reminders."
        case .fullAccess:
            return "today-md can already access Apple Reminders."
        }
    }

    private static let persistedStateDefaultsKey = "today-md.reminders.sync.state"
    private static let managedCalendarTitle = "today-md"
    private static let remindersPrivacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
    private static let systemSettingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    private static var hasReminderUsageDescription: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return false
        }

        let fullAccessDescription = Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") as? String
        return !(fullAccessDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private enum TodayMdReminderSyncError: LocalizedError {
    case noWritableReminderSource

    var errorDescription: String? {
        switch self {
        case .noWritableReminderSource:
            return "No writable Apple Reminders account is available on this Mac."
        }
    }
}
