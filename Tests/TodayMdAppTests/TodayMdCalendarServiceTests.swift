import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdCalendarServiceTests: XCTestCase {
    func testRoundUpMovesToNextQuarterHour() {
        let date = makeDate(year: 2026, month: 3, day: 23, hour: 9, minute: 7)

        let rounded = CalendarTimeBlocking.roundUp(date, stepMinutes: 15, calendar: calendar)

        XCTAssertEqual(rounded, makeDate(year: 2026, month: 3, day: 23, hour: 9, minute: 15))
    }

    func testNextAvailableSlotFindsGapBeforeFirstBusyEvent() {
        let now = makeDate(year: 2026, month: 3, day: 23, hour: 8, minute: 10)
        let busySlots = [
            CalendarTimeBlocking.BusySlot(
                start: makeDate(year: 2026, month: 3, day: 23, hour: 10, minute: 0),
                end: makeDate(year: 2026, month: 3, day: 23, hour: 11, minute: 0)
            )
        ]

        let slot = CalendarTimeBlocking.nextAvailableSlot(
            after: now,
            durationMinutes: 60,
            busySlots: busySlots,
            calendar: calendar
        )

        XCTAssertEqual(slot?.start, makeDate(year: 2026, month: 3, day: 23, hour: 8, minute: 15))
        XCTAssertEqual(slot?.end, makeDate(year: 2026, month: 3, day: 23, hour: 9, minute: 15))
    }

    func testNextAvailableSlotMovesPastBusyEventAndRoundsUp() {
        let now = makeDate(year: 2026, month: 3, day: 23, hour: 9, minute: 0)
        let busySlots = [
            CalendarTimeBlocking.BusySlot(
                start: makeDate(year: 2026, month: 3, day: 23, hour: 9, minute: 5),
                end: makeDate(year: 2026, month: 3, day: 23, hour: 10, minute: 20)
            )
        ]

        let slot = CalendarTimeBlocking.nextAvailableSlot(
            after: now,
            durationMinutes: 30,
            busySlots: busySlots,
            calendar: calendar
        )

        XCTAssertEqual(slot?.start, makeDate(year: 2026, month: 3, day: 23, hour: 10, minute: 30))
        XCTAssertEqual(slot?.end, makeDate(year: 2026, month: 3, day: 23, hour: 11, minute: 0))
    }

    func testNextAvailableSlotFallsIntoNextDayAfterWorkdayEnds() {
        let now = makeDate(year: 2026, month: 3, day: 23, hour: 19, minute: 40)

        let slot = CalendarTimeBlocking.nextAvailableSlot(
            after: now,
            durationMinutes: 60,
            busySlots: [],
            calendar: calendar
        )

        XCTAssertEqual(slot?.start, makeDate(year: 2026, month: 3, day: 24, hour: 8, minute: 0))
        XCTAssertEqual(slot?.end, makeDate(year: 2026, month: 3, day: 24, hour: 9, minute: 0))
    }

    func testResolvedAuthorizationStatusFallsBackToFullAccessWhenCalendarDataIsVisible() {
        let resolved = TodayMdCalendarService.resolvedAuthorizationStatus(
            reported: .notDetermined,
            hasVisibleCalendarData: true
        )

        XCTAssertEqual(resolved, .fullAccess)
    }

    func testResolvedAuthorizationStatusKeepsExplicitDeniedState() {
        let resolved = TodayMdCalendarService.resolvedAuthorizationStatus(
            reported: .denied,
            hasVisibleCalendarData: true
        )

        XCTAssertEqual(resolved, .denied)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        return calendar.date(from: components)!
    }
}
