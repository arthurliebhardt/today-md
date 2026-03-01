import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

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
        note?.content.components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ")
            }.count ?? 0
    }

    var checkboxDone: Int {
        note?.content.components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ")
            }.count ?? 0
    }

    var note: TaskNote? {
        notes.max { lhs, rhs in
            lhs.lastModified < rhs.lastModified
        }
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
    static let taskItem = UTType(exportedAs: "com.todo.app.taskitem")
}
