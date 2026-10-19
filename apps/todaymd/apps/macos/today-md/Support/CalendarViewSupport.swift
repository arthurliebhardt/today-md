import SwiftUI

enum TaskCalendarVisibilitySelection {
    static func resolvedIdentifiers(from rawValue: String, availableCalendars: [TodayMdCalendarSummary]) -> Set<String> {
        let availableIdentifiers = Set(availableCalendars.map(\.id))
        guard !availableIdentifiers.isEmpty else { return [] }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return availableIdentifiers }

        let selectedIdentifiers = Set(trimmedValue.split(separator: ",").map(String.init))
            .intersection(availableIdentifiers)

        return selectedIdentifiers.isEmpty ? availableIdentifiers : selectedIdentifiers
    }

    static func storedValue(for identifiers: Set<String>, availableCalendars: [TodayMdCalendarSummary]) -> String {
        let availableIdentifiers = Set(availableCalendars.map(\.id))
        guard !availableIdentifiers.isEmpty else { return "" }

        let sanitizedIdentifiers = identifiers.intersection(availableIdentifiers)
        guard !sanitizedIdentifiers.isEmpty, sanitizedIdentifiers.count < availableIdentifiers.count else {
            return ""
        }

        return sanitizedIdentifiers.sorted().joined(separator: ",")
    }
}

extension TodayMdCalendarSummary {
    var accentColor: Color {
        Color(nsColor: nsColor)
    }
}

extension TodayMdCalendarEventSummary {
    var accentColor: Color {
        Color(nsColor: nsColor)
    }
}

