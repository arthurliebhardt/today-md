import Combine
import EventKit
import Foundation

enum TodayMdCalendarAuthorizationState: Equatable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    var label: String {
        switch self {
        case .notDetermined:
            return "Not Connected"
        case .denied:
            return "Access Denied"
        case .restricted:
            return "Restricted"
        case .writeOnly:
            return "Write Only"
        case .fullAccess:
            return "Connected"
        }
    }

    var canReadEvents: Bool {
        self == .fullAccess
    }

    var canCreateEvents: Bool {
        self == .fullAccess || self == .writeOnly
    }

    var guidance: String {
        switch self {
        case .notDetermined:
            return "Connect Calendar to read your availability and create focus blocks from tasks."
        case .denied:
            return "today-md cannot read your calendars until you allow access in System Settings."
        case .restricted:
            return "Calendar access is restricted on this Mac."
        case .writeOnly:
            return "today-md can create events, but full access is required to read your schedule and suggest open slots."
        case .fullAccess:
            return "today-md can read your schedule and block time directly from a task."
        }
    }
}

struct TodayMdCalendarSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let sourceType: EKSourceType
    let calendarType: EKCalendarType
    let allowsContentModifications: Bool

    var displayTitle: String {
        guard !sourceTitle.isEmpty, sourceTitle.caseInsensitiveCompare(title) != .orderedSame else {
            return title
        }
        return "\(title) (\(sourceTitle))"
    }

    var subtitle: String {
        let sourceLabel = switch sourceType {
        case .exchange:
            "Outlook / Exchange"
        case .calDAV:
            "CalDAV"
        case .local:
            "On My Mac"
        case .mobileMe:
            "iCloud"
        case .subscribed:
            "Subscribed"
        case .birthdays:
            "Birthdays"
        @unknown default:
            "Calendar"
        }

        if sourceTitle.isEmpty {
            return sourceLabel
        }

        return "\(sourceTitle) • \(sourceLabel)"
    }

    var isExchangeCalendar: Bool {
        sourceType == .exchange || calendarType == .exchange
    }
}

struct TodayMdCalendarEventSummary: Identifiable, Hashable {
    let id: String
    let eventIdentifier: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let allowsContentModifications: Bool
    let isTodayMdBlock: Bool

    var canEdit: Bool {
        allowsContentModifications && eventIdentifier != nil && isTodayMdBlock
    }

    var canDelete: Bool {
        canEdit
    }
}

struct TodayMdCalendarBlockResult: Equatable {
    let eventIdentifier: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
}

enum TodayMdCalendarError: LocalizedError {
    case accessRequired
    case fullAccessRequired
    case noWritableCalendars
    case destinationCalendarUnavailable
    case noAvailableTimeSlot
    case invalidTimeRange
    case failedToSave(String)
    case eventUnavailable
    case eventNotEditable
    case failedToDelete(String)

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            return "Connect Calendar before blocking time."
        case .fullAccessRequired:
            return "Full calendar access is required to read your availability and suggest a time slot."
        case .noWritableCalendars:
            return "No writable calendars are available. Add a calendar account in macOS Calendar first."
        case .destinationCalendarUnavailable:
            return "The selected calendar is no longer available."
        case .noAvailableTimeSlot:
            return "No open slot was found in the next two weeks."
        case .invalidTimeRange:
            return "Choose a block with an end time after the start time."
        case .failedToSave(let message):
            return message
        case .eventUnavailable:
            return "That calendar entry is no longer available."
        case .eventNotEditable:
            return "Only blockers created from today-md can be deleted here."
        case .failedToDelete(let message):
            return message
        }
    }
}

enum CalendarTimeBlocking {
    struct BusySlot: Equatable {
        let start: Date
        let end: Date
    }

    static func roundUp(_ date: Date, stepMinutes: Int = 15, calendar: Calendar = .current) -> Date {
        guard stepMinutes > 0 else { return date }

        let seconds = calendar.component(.second, from: date)
        let nanoseconds = calendar.component(.nanosecond, from: date)
        let minute = calendar.component(.minute, from: date)

        var rounded = calendar.date(
            bySettingHour: calendar.component(.hour, from: date),
            minute: minute,
            second: 0,
            of: date
        ) ?? date

        let remainder = minute % stepMinutes
        if remainder == 0, seconds == 0, nanoseconds == 0 {
            return rounded
        }

        let delta = remainder == 0 ? stepMinutes : (stepMinutes - remainder)
        rounded = calendar.date(byAdding: .minute, value: delta, to: rounded) ?? rounded
        return rounded
    }

    static func nextAvailableSlot(
        after date: Date,
        durationMinutes: Int,
        busySlots: [BusySlot],
        calendar: Calendar = .current,
        startHour: Int = 8,
        endHour: Int = 20,
        searchDays: Int = 14,
        stepMinutes: Int = 15
    ) -> DateInterval? {
        guard durationMinutes > 0 else { return nil }
        let duration = TimeInterval(durationMinutes * 60)
        let mergedBusySlots = merge(busySlots)
        let initialCandidate = roundUp(date, stepMinutes: stepMinutes, calendar: calendar)

        for dayOffset in 0..<max(searchDays, 1) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: initialCandidate) else { continue }
            let startOfDay = calendar.startOfDay(for: day)
            guard
                let dayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: startOfDay),
                let dayEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: startOfDay)
            else {
                continue
            }

            var candidate = dayOffset == 0 ? max(initialCandidate, dayStart) : dayStart
            candidate = roundUp(candidate, stepMinutes: stepMinutes, calendar: calendar)
            guard candidate < dayEnd else { continue }

            let slotsForDay = mergedBusySlots.filter { slot in
                slot.end > dayStart && slot.start < dayEnd
            }

            for slot in slotsForDay {
                let busyStart = max(slot.start, dayStart)
                let busyEnd = min(slot.end, dayEnd)

                if candidate.addingTimeInterval(duration) <= busyStart {
                    return DateInterval(start: candidate, duration: duration)
                }

                if candidate < busyEnd {
                    candidate = roundUp(busyEnd, stepMinutes: stepMinutes, calendar: calendar)
                }

                if candidate >= dayEnd {
                    break
                }
            }

            if candidate.addingTimeInterval(duration) <= dayEnd {
                return DateInterval(start: candidate, duration: duration)
            }
        }

        return nil
    }

    private static func merge(_ busySlots: [BusySlot]) -> [BusySlot] {
        let sortedSlots = busySlots
            .filter { $0.end > $0.start }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return lhs.end < rhs.end
                }
                return lhs.start < rhs.start
            }

        var merged: [BusySlot] = []
        for slot in sortedSlots {
            guard let last = merged.last else {
                merged.append(slot)
                continue
            }

            if slot.start <= last.end {
                merged[merged.count - 1] = BusySlot(start: last.start, end: max(last.end, slot.end))
            } else {
                merged.append(slot)
            }
        }

        return merged
    }
}

@MainActor
final class TodayMdCalendarService: ObservableObject {
    private static let todayMdBlockMarker = "Created from today-md"

    @Published private(set) var authorizationStatus: TodayMdCalendarAuthorizationState
    @Published private(set) var calendars: [TodayMdCalendarSummary] = []
    @Published private(set) var upcomingEvents: [TodayMdCalendarEventSummary] = []
    @Published private(set) var lastCreatedBlock: TodayMdCalendarBlockResult?
    @Published private(set) var lastError: String?
    @Published private(set) var refreshRevision = 0

    private let eventStore: EKEventStore
    private let notificationCenter: NotificationCenter
    private let nowProvider: () -> Date
    private var eventStoreChangeObserver: NSObjectProtocol?
    private var busySlots: [CalendarTimeBlocking.BusySlot] = []

    init(
        eventStore: EKEventStore = EKEventStore(),
        notificationCenter: NotificationCenter = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.notificationCenter = notificationCenter
        self.nowProvider = nowProvider
        self.authorizationStatus = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
        startObservingEventStoreChanges()

        if authorizationStatus.canReadEvents {
            refresh()
        }
    }

    var writableCalendars: [TodayMdCalendarSummary] {
        calendars
            .filter(\.allowsContentModifications)
            .sorted(by: Self.sortCalendarSummaries)
    }

    func refreshIfNeeded() {
        let previousAuthorizationStatus = authorizationStatus
        authorizationStatus = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))

        if authorizationStatus.canReadEvents || previousAuthorizationStatus != authorizationStatus {
            refresh()
        }
    }

    func requestFullAccess() {
        lastError = nil

        guard Self.hasCalendarUsageDescription else {
            lastError = "Calendar access requires launching today-md as a macOS app bundle. Run it from Xcode or use `bash scripts/dev-run.sh` instead of `swift run`."
            return
        }

        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))

                if let error {
                    if !Self.hasCalendarUsageDescription {
                        self.lastError = "Calendar access requires launching today-md as a macOS app bundle. Run it from Xcode or use `bash scripts/dev-run.sh` instead of `swift run`."
                    } else {
                        self.lastError = error.localizedDescription
                    }
                    return
                }

                if granted {
                    self.refresh()
                } else {
                    self.clearReadOnlyData()
                    if self.authorizationStatus == .denied {
                        self.lastError = "Calendar access is off for today-md. Enable it in System Settings > Privacy & Security > Calendars."
                    }
                }
            }
        }
    }

    func refresh() {
        authorizationStatus = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
        guard authorizationStatus.canReadEvents else {
            clearReadOnlyData()
            return
        }

        let eventCalendars = eventStore.calendars(for: .event)
            .map(Self.makeCalendarSummary)
            .sorted(by: Self.sortCalendarSummaries)

        calendars = eventCalendars

        let availabilityCalendars = eventStore.calendars(for: .event).filter(Self.shouldUseForAvailability)
        let startDate = nowProvider()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)
            ?? startDate.addingTimeInterval(7 * 24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: availabilityCalendars)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate > startDate }
            .sorted(by: Self.sortEvents)

        busySlots = events.compactMap(Self.makeBusySlot)
        upcomingEvents = events.prefix(8).map(Self.makeEventSummary)
        lastError = nil
        refreshRevision += 1
    }

    func selectedDestinationCalendar(preferredIdentifier: String?) -> TodayMdCalendarSummary? {
        let writableCalendars = writableCalendars
        if let preferredIdentifier,
           let preferredCalendar = writableCalendars.first(where: { $0.id == preferredIdentifier }) {
            return preferredCalendar
        }

        if let defaultIdentifier = eventStore.defaultCalendarForNewEvents?.calendarIdentifier,
           let defaultCalendar = writableCalendars.first(where: { $0.id == defaultIdentifier }) {
            return defaultCalendar
        }

        if let exchangeCalendar = writableCalendars.first(where: \.isExchangeCalendar) {
            return exchangeCalendar
        }

        return writableCalendars.first
    }

    func suggestedBlockInterval(durationMinutes: Int) -> DateInterval? {
        guard authorizationStatus.canReadEvents else { return nil }
        return CalendarTimeBlocking.nextAvailableSlot(
            after: nowProvider(),
            durationMinutes: durationMinutes,
            busySlots: busySlots
        )
    }

    func eventsForDay(_ date: Date) -> [TodayMdCalendarEventSummary] {
        guard authorizationStatus.canReadEvents else { return [] }

        let dayInterval = Self.dayInterval(for: date)
        return events(in: dayInterval)
    }

    func events(in interval: DateInterval) -> [TodayMdCalendarEventSummary] {
        guard authorizationStatus.canReadEvents else { return [] }

        let events = fetchEvents(
            from: interval.start,
            end: interval.end,
            calendars: eventStore.calendars(for: .event).filter(Self.shouldUseForAvailability)
        )

        return events
            .filter { $0.endDate > interval.start && $0.startDate < interval.end }
            .map(Self.makeEventSummary)
    }

    func createBlock(
        for task: TaskItem,
        durationMinutes: Int,
        preferredCalendarIdentifier: String?
    ) throws -> TodayMdCalendarBlockResult {
        guard let interval = suggestedBlockInterval(durationMinutes: durationMinutes) else {
            throw TodayMdCalendarError.noAvailableTimeSlot
        }

        return try createBlock(
            for: task,
            interval: interval,
            preferredCalendarIdentifier: preferredCalendarIdentifier
        )
    }

    func createBlock(
        for task: TaskItem,
        interval: DateInterval,
        preferredCalendarIdentifier: String?
    ) throws -> TodayMdCalendarBlockResult {
        refreshIfNeeded()

        guard authorizationStatus.canCreateEvents else {
            throw TodayMdCalendarError.accessRequired
        }
        guard authorizationStatus.canReadEvents else {
            throw TodayMdCalendarError.fullAccessRequired
        }
        guard interval.end > interval.start else {
            throw TodayMdCalendarError.invalidTimeRange
        }
        guard let destinationSummary = selectedDestinationCalendar(preferredIdentifier: preferredCalendarIdentifier) else {
            throw TodayMdCalendarError.noWritableCalendars
        }
        guard let destinationCalendar = eventStore.calendar(withIdentifier: destinationSummary.id) else {
            throw TodayMdCalendarError.destinationCalendarUnavailable
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = destinationCalendar
        event.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Focus Block" : task.title
        event.startDate = interval.start
        event.endDate = interval.end
        event.availability = .busy
        event.notes = Self.blockNotes(for: task)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            throw TodayMdCalendarError.failedToSave(error.localizedDescription)
        }

        let result = TodayMdCalendarBlockResult(
            eventIdentifier: event.eventIdentifier ?? UUID().uuidString,
            calendarTitle: destinationSummary.title,
            startDate: interval.start,
            endDate: interval.end
        )

        lastCreatedBlock = result
        refresh()
        return result
    }

    func deleteEvent(identifier: String) throws {
        refreshIfNeeded()

        guard authorizationStatus.canCreateEvents else {
            throw TodayMdCalendarError.accessRequired
        }
        guard authorizationStatus.canReadEvents else {
            throw TodayMdCalendarError.fullAccessRequired
        }
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw TodayMdCalendarError.eventUnavailable
        }
        guard event.calendar.allowsContentModifications, Self.isTodayMdManaged(event) else {
            throw TodayMdCalendarError.eventNotEditable
        }

        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        } catch {
            throw TodayMdCalendarError.failedToDelete(error.localizedDescription)
        }

        if lastCreatedBlock?.eventIdentifier == identifier {
            lastCreatedBlock = nil
        }

        refresh()
    }

    func moveEvent(identifier: String, to interval: DateInterval) throws -> TodayMdCalendarBlockResult {
        refreshIfNeeded()

        guard authorizationStatus.canCreateEvents else {
            throw TodayMdCalendarError.accessRequired
        }
        guard authorizationStatus.canReadEvents else {
            throw TodayMdCalendarError.fullAccessRequired
        }
        guard interval.end > interval.start else {
            throw TodayMdCalendarError.invalidTimeRange
        }
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw TodayMdCalendarError.eventUnavailable
        }
        guard event.calendar.allowsContentModifications, Self.isTodayMdManaged(event) else {
            throw TodayMdCalendarError.eventNotEditable
        }

        event.startDate = interval.start
        event.endDate = interval.end

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            throw TodayMdCalendarError.failedToSave(error.localizedDescription)
        }

        let result = TodayMdCalendarBlockResult(
            eventIdentifier: event.eventIdentifier ?? identifier,
            calendarTitle: event.calendar.title,
            startDate: interval.start,
            endDate: interval.end
        )

        lastCreatedBlock = result
        refresh()
        return result
    }

    private func clearReadOnlyData() {
        calendars = []
        upcomingEvents = []
        busySlots = []
        refreshRevision += 1
    }

    private func fetchEvents(from startDate: Date, end endDate: Date, calendars: [EKCalendar]) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return eventStore.events(matching: predicate)
            .sorted(by: Self.sortEvents)
    }

    private func startObservingEventStoreChanges() {
        eventStoreChangeObserver = notificationCenter.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfNeeded()
            }
        }
    }

    private static func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> TodayMdCalendarAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .writeOnly:
            return .writeOnly
        case .fullAccess, .authorized:
            return .fullAccess
        @unknown default:
            return .denied
        }
    }

    private static func makeCalendarSummary(calendar: EKCalendar) -> TodayMdCalendarSummary {
        TodayMdCalendarSummary(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceTitle: calendar.source.title,
            sourceType: calendar.source.sourceType,
            calendarType: calendar.type,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private static func makeEventSummary(event: EKEvent) -> TodayMdCalendarEventSummary {
        let eventIdentifier = event.eventIdentifier
        let identifier = eventIdentifier ?? [
            event.calendar.calendarIdentifier,
            event.title,
            ISO8601DateFormatter().string(from: event.startDate)
        ].joined(separator: "::")

        return TodayMdCalendarEventSummary(
            id: identifier,
            eventIdentifier: eventIdentifier,
            title: event.title?.isEmpty == false ? event.title : "Untitled Event",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            allowsContentModifications: event.calendar.allowsContentModifications,
            isTodayMdBlock: Self.isTodayMdManaged(event)
        )
    }

    private static func makeBusySlot(event: EKEvent) -> CalendarTimeBlocking.BusySlot? {
        if event.availability == .free {
            return nil
        }

        guard event.endDate > event.startDate else { return nil }
        return CalendarTimeBlocking.BusySlot(start: event.startDate, end: event.endDate)
    }

    private static func shouldUseForAvailability(calendar: EKCalendar) -> Bool {
        switch calendar.type {
        case .birthday, .subscription:
            return false
        default:
            return true
        }
    }

    private static func sortCalendarSummaries(lhs: TodayMdCalendarSummary, rhs: TodayMdCalendarSummary) -> Bool {
        let lhsRank = lhs.isExchangeCalendar ? 0 : 1
        let rhsRank = rhs.isExchangeCalendar ? 0 : 1
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private static func sortEvents(lhs: EKEvent, rhs: EKEvent) -> Bool {
        if lhs.startDate == rhs.startDate {
            let lhsTitle = lhs.title ?? ""
            let rhsTitle = rhs.title ?? ""
            let titleComparison = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            return lhs.eventIdentifier ?? "" < rhs.eventIdentifier ?? ""
        }

        return lhs.startDate < rhs.startDate
    }

    private static func blockNotes(for task: TaskItem) -> String {
        var parts = [todayMdBlockMarker]

        if let listName = task.list?.name {
            parts.append("List: \(listName)")
        }

        parts.append("Lane: \(task.block.label)")

        if let note = task.note?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            parts.append(note)
        }

        return parts.joined(separator: "\n\n")
    }

    private static func isTodayMdManaged(_ event: EKEvent) -> Bool {
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else {
            return false
        }

        return notes.contains(todayMdBlockMarker)
    }

    private static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private static var hasCalendarUsageDescription: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return false
        }

        let fullAccessDescription = Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") as? String
        return !(fullAccessDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
