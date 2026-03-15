import Foundation
import SwiftData

@Model
final class TaskNote {
    var content: String
    var lastModified: Date
    var parentTask: TaskItem?

    init(content: String = "") {
        self.content = content
        self.lastModified = Date()
    }
}
