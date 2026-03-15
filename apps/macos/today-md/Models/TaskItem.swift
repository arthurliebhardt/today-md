import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

struct TaskCardMetadata {
    let hasNote: Bool
    let checkboxDone: Int
    let checkboxTotal: Int

    static let empty = TaskCardMetadata(hasNote: false, checkboxDone: 0, checkboxTotal: 0)
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var blockRaw: String
    var sortOrder: Int
    var creationDate: Date
    var list: TaskList?

    @Relationship(deleteRule: .cascade, inverse: \SubTask.parentTask)
    var subtasks: [SubTask] = []

    @Relationship(deleteRule: .cascade, inverse: \TaskNote.parentTask)
    var notes: [TaskNote] = []

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

    var note: TaskNote? {
        notes.max { lhs, rhs in
            lhs.lastModified < rhs.lastModified
        }
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

    init(title: String, block: TimeBlock = .backlog, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isDone = false
        self.blockRaw = block.rawValue
        self.sortOrder = sortOrder
        self.creationDate = Date()
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
