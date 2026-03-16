import Foundation
import Observation
import SwiftUI

enum TimeBlock: String, Codable, CaseIterable, Identifiable {
    case today = "today"
    case thisWeek = "thisWeek"
    case backlog = "backlog"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:
            return "Today"
        case .thisWeek:
            return "This Week"
        case .backlog:
            return "Backlog"
        }
    }

    var icon: String {
        switch self {
        case .today:
            return "sun.max.fill"
        case .thisWeek:
            return "calendar"
        case .backlog:
            return "tray.full"
        }
    }
}

enum ListColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .purple:
            return .purple
        case .pink:
            return .pink
        case .red:
            return .red
        case .orange:
            return .orange
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .teal:
            return .teal
        }
    }
}

@Observable
final class TaskList: Identifiable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var colorName: String
    var sortOrder: Int
    var items: [TaskItem]

    var listColor: ListColor {
        get { ListColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "checklist",
        color: ListColor = .blue,
        sortOrder: Int = 0,
        items: [TaskItem] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = color.rawValue
        self.sortOrder = sortOrder
        self.items = items
    }

    static func == (lhs: TaskList, rhs: TaskList) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
