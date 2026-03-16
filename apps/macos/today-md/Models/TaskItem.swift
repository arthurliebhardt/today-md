import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

struct TaskCardMetadata {
    let hasNote: Bool
    let checkboxDone: Int
    let checkboxTotal: Int

    static let empty = TaskCardMetadata(hasNote: false, checkboxDone: 0, checkboxTotal: 0)
}

@Observable
final class TaskItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isDone: Bool
    var blockRaw: String
    var sortOrder: Int
    var creationDate: Date
    weak var list: TaskList?
    var subtasks: [SubTask]
    var note: TaskNote?

    var block: TimeBlock {
        get { TimeBlock(rawValue: blockRaw) ?? .backlog }
        set { blockRaw = newValue.rawValue }
    }

    var completedSubtaskCount: Int {
        subtasks.filter(\.isCompleted).count
    }

    var checkboxTotal: Int {
        cardMetadata.checkboxTotal
    }

    var checkboxDone: Int {
        cardMetadata.checkboxDone
    }

    var cardMetadata: TaskCardMetadata {
        guard let note else { return .empty }

        var checkboxDone = 0
        var checkboxTotal = 0

        for line in note.content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                checkboxTotal += 1
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                checkboxTotal += 1
                checkboxDone += 1
            }
        }

        return TaskCardMetadata(
            hasNote: true,
            checkboxDone: checkboxDone,
            checkboxTotal: checkboxTotal
        )
    }

    init(
        id: UUID = UUID(),
        title: String,
        block: TimeBlock = .backlog,
        sortOrder: Int = 0,
        creationDate: Date = Date(),
        isDone: Bool = false,
        subtasks: [SubTask] = [],
        note: TaskNote? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.blockRaw = block.rawValue
        self.sortOrder = sortOrder
        self.creationDate = creationDate
        self.subtasks = subtasks
        self.note = note
    }

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TaskItemTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .taskItem)
    }
}

extension UTType {
    static let taskItem = UTType(exportedAs: "com.today-md.app.taskitem")
}
