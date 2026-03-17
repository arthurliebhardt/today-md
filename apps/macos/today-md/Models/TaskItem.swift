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

struct MarkdownChecklistItem: Identifiable, Hashable {
    let lineIndex: Int
    let title: String
    let isChecked: Bool

    var id: Int { lineIndex }

    var normalizedTitle: String {
        Self.normalize(title)
    }

    static func normalize(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
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

    var checklistItems: [MarkdownChecklistItem] {
        guard let note else { return [] }

        return note.content
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { lineIndex, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                    return MarkdownChecklistItem(
                        lineIndex: lineIndex,
                        title: String(trimmed.dropFirst(6)),
                        isChecked: true
                    )
                } else if trimmed.hasPrefix("- [ ] ") {
                    return MarkdownChecklistItem(
                        lineIndex: lineIndex,
                        title: String(trimmed.dropFirst(6)),
                        isChecked: false
                    )
                }
                return nil
            }
    }

    var mappedSubtasks: [SubTask] {
        markdownSubtaskMappings().map(\.subtask)
    }

    var mappedCompletedSubtaskCount: Int {
        mappedSubtasks.filter(\.isCompleted).count
    }

    var cardMetadata: TaskCardMetadata {
        return TaskCardMetadata(
            hasNote: note != nil,
            checkboxDone: checklistItems.filter(\.isChecked).count,
            checkboxTotal: checklistItems.count
        )
    }

    func mappedChecklistLineIndex(for subtaskID: UUID) -> Int? {
        markdownSubtaskMappings().first(where: { $0.subtask.id == subtaskID })?.item.lineIndex
    }

    func mappedSubtaskID(forChecklistLineIndex lineIndex: Int) -> UUID? {
        markdownSubtaskMappings().first(where: { $0.item.lineIndex == lineIndex })?.subtask.id
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

    private func markdownSubtaskMappings() -> [(subtask: SubTask, item: MarkdownChecklistItem)] {
        var remainingItemsByTitle = Dictionary(grouping: checklistItems, by: \.normalizedTitle)
            .mapValues { items in
                items.sorted { $0.lineIndex < $1.lineIndex }
            }

        return subtasks
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { subtask in
                let titleKey = MarkdownChecklistItem.normalize(subtask.title)
                guard var matches = remainingItemsByTitle[titleKey], !matches.isEmpty else {
                    return nil
                }

                let item = matches.removeFirst()
                remainingItemsByTitle[titleKey] = matches
                return (subtask, item)
            }
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
