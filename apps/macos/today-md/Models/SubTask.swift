import Foundation
import Observation

@Observable
final class SubTask: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }

    static func == (lhs: SubTask, rhs: SubTask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
