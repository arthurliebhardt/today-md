import Foundation

extension Calendar {
    func mondayBasedWeekInterval(containing date: Date) -> DateInterval {
        let startOfReferenceDay = startOfDay(for: date)
        let weekday = component(.weekday, from: startOfReferenceDay)
        let daysFromMonday = (weekday - 2 + 7) % 7
        let start = self.date(byAdding: .day, value: -daysFromMonday, to: startOfReferenceDay) ?? startOfReferenceDay
        let end = self.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }
}
