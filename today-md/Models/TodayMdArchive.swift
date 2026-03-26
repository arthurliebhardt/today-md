import Foundation

struct TodayMdArchive: Codable {
    let version: Int
    let exportedAt: Date
    let syncRevisionID: String?
    let syncUpdatedAt: Date?
    let syncUpdatedByDeviceID: String?
    let lists: [ListArchive]
    let unassignedTasks: [TaskArchive]

    init(
        version: Int = 1,
        exportedAt: Date = Date(),
        syncRevisionID: String? = nil,
        syncUpdatedAt: Date? = nil,
        syncUpdatedByDeviceID: String? = nil,
        lists: [ListArchive],
        unassignedTasks: [TaskArchive]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.syncRevisionID = syncRevisionID
        self.syncUpdatedAt = syncUpdatedAt
        self.syncUpdatedByDeviceID = syncUpdatedByDeviceID
        self.lists = lists
        self.unassignedTasks = unassignedTasks
    }

    init(
        lists: [TaskList],
        unassignedTasks: [TaskItem],
        exportedAt: Date = Date(),
        syncRevisionID: String? = nil,
        syncUpdatedAt: Date? = nil,
        syncUpdatedByDeviceID: String? = nil
    ) {
        self.version = 1
        self.exportedAt = exportedAt
        self.syncRevisionID = syncRevisionID
        self.syncUpdatedAt = syncUpdatedAt
        self.syncUpdatedByDeviceID = syncUpdatedByDeviceID
        self.lists = lists
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { list in
                ListArchive(
                    id: list.id,
                    name: list.name,
                    icon: list.icon,
                    colorName: list.colorName,
                    sortOrder: list.sortOrder,
                    tasks: list.items
                        .sorted(by: taskSort)
                        .map(TaskArchive.init(task:))
                )
            }
        self.unassignedTasks = unassignedTasks
            .sorted(by: taskSort)
            .map(TaskArchive.init(task:))
    }

    func instantiate() -> (lists: [TaskList], unassignedTasks: [TaskItem]) {
        let hydratedLists = lists
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { listArchive in
                TaskList(
                    id: listArchive.id,
                    name: listArchive.name,
                    icon: listArchive.icon,
                    color: ListColor(rawValue: listArchive.colorName) ?? .blue,
                    sortOrder: listArchive.sortOrder
                )
            }

        let listsByID = Dictionary(uniqueKeysWithValues: hydratedLists.map { ($0.id, $0) })

        for listArchive in lists {
            guard let list = listsByID[listArchive.id] else { continue }
            list.items = listArchive.tasks.map { archive in
                let task = archive.makeTask()
                task.list = list
                return task
            }
        }

        let hydratedUnassigned = unassignedTasks.map { $0.makeTask() }
        return (hydratedLists, hydratedUnassigned)
    }

    struct ListArchive: Codable {
        let id: UUID
        let name: String
        let icon: String
        let colorName: String
        let sortOrder: Int
        let tasks: [TaskArchive]

        init(id: UUID, name: String, icon: String, colorName: String, sortOrder: Int, tasks: [TaskArchive]) {
            self.id = id
            self.name = name
            self.icon = icon
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.tasks = tasks
        }
    }

    struct TaskArchive: Codable {
        let id: UUID
        let title: String
        let isDone: Bool
        let blockRaw: String
        let schedulingStateRaw: String
        let sortOrder: Int
        let creationDate: Date
        let note: NoteArchive?
        let subtasks: [SubTaskArchive]

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case isDone
            case blockRaw
            case schedulingStateRaw
            case sortOrder
            case creationDate
            case note
            case subtasks
        }

        init(
            id: UUID,
            title: String,
            isDone: Bool,
            blockRaw: String,
            schedulingStateRaw: String = TaskSchedulingState.unscheduled.rawValue,
            sortOrder: Int,
            creationDate: Date,
            note: NoteArchive?,
            subtasks: [SubTaskArchive]
        ) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.blockRaw = blockRaw
            self.schedulingStateRaw = schedulingStateRaw
            self.sortOrder = sortOrder
            self.creationDate = creationDate
            self.note = note
            self.subtasks = subtasks
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            isDone = try container.decode(Bool.self, forKey: .isDone)
            blockRaw = try container.decode(String.self, forKey: .blockRaw)
            schedulingStateRaw = try container.decodeIfPresent(String.self, forKey: .schedulingStateRaw)
                ?? TaskSchedulingState.unscheduled.rawValue
            sortOrder = try container.decode(Int.self, forKey: .sortOrder)
            creationDate = try container.decode(Date.self, forKey: .creationDate)
            note = try container.decodeIfPresent(NoteArchive.self, forKey: .note)
            subtasks = try container.decode([SubTaskArchive].self, forKey: .subtasks)
        }

        init(task: TaskItem) {
            self.id = task.id
            self.title = task.title
            self.isDone = task.isDone
            self.blockRaw = task.blockRaw
            self.schedulingStateRaw = task.schedulingStateRaw
            self.sortOrder = task.sortOrder
            self.creationDate = task.creationDate
            self.note = task.note.map(NoteArchive.init(note:))
            self.subtasks = task.subtasks
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(SubTaskArchive.init(subtask:))
        }

        func makeTask() -> TaskItem {
            TaskItem(
                id: id,
                title: title,
                block: TimeBlock(rawValue: blockRaw) ?? .backlog,
                schedulingState: TaskSchedulingState(rawValue: schedulingStateRaw) ?? .unscheduled,
                sortOrder: sortOrder,
                creationDate: creationDate,
                isDone: isDone,
                subtasks: subtasks.map { $0.makeSubtask() },
                note: note?.makeNote()
            )
        }
    }

    struct NoteArchive: Codable {
        let content: String
        let lastModified: Date

        init(content: String, lastModified: Date) {
            self.content = content
            self.lastModified = lastModified
        }

        init(note: TaskNote) {
            self.content = note.content
            self.lastModified = note.lastModified
        }

        func makeNote() -> TaskNote {
            TaskNote(content: content, lastModified: lastModified)
        }
    }

    struct SubTaskArchive: Codable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        let sortOrder: Int

        init(id: UUID, title: String, isCompleted: Bool, sortOrder: Int) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
            self.sortOrder = sortOrder
        }

        init(subtask: SubTask) {
            self.id = subtask.id
            self.title = subtask.title
            self.isCompleted = subtask.isCompleted
            self.sortOrder = subtask.sortOrder
        }

        func makeSubtask() -> SubTask {
            SubTask(id: id, title: title, isCompleted: isCompleted, sortOrder: sortOrder)
        }
    }
}

func taskSort(lhs: TaskItem, rhs: TaskItem) -> Bool {
    let lhsTuple = (
        blockRank(lhs.block),
        lhs.sortOrder,
        -lhs.creationDate.timeIntervalSinceReferenceDate,
        lhs.id.uuidString
    )
    let rhsTuple = (
        blockRank(rhs.block),
        rhs.sortOrder,
        -rhs.creationDate.timeIntervalSinceReferenceDate,
        rhs.id.uuidString
    )
    return lhsTuple < rhsTuple
}

func blockRank(_ block: TimeBlock) -> Int {
    switch block {
    case .today:
        return 0
    case .thisWeek:
        return 1
    case .backlog:
        return 2
    }
}
