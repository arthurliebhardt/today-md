import Foundation
import SwiftData

@Model
final class SubTask {
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var parentTask: TaskItem?

    init(title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}
