import Foundation
import Observation

@Observable
final class TaskNote {
    var content: String
    var lastModified: Date

    init(content: String = "", lastModified: Date = Date()) {
        self.content = content
        self.lastModified = lastModified
    }
}
