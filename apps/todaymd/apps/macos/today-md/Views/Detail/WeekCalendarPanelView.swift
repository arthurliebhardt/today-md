import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WeekCalendarPanelStyle {
    static let dayStartHour = 6
    static let dayEndHour = 22
    static let hourHeight: CGFloat = 60
    static let hourLabelWidth: CGFloat = 52
    static let minimumDayColumnWidth: CGFloat = 138
    static let dayColumnSpacing: CGFloat = 8
    static let snapMinutes = 15
    static let minimumDurationMinutes = 15
    static let eventHorizontalInset: CGFloat = 6
    static let deleteBadgeSize: CGFloat = 20
    static let deleteBadgeInset: CGFloat = 8
    static let resizeHandleHitHeight: CGFloat = 22
    static let resizeHandleWidth: CGFloat = 34
    static let resizeHandleThickness: CGFloat = 4
}

enum WeekCalendarPanelDisplayMode {
    case week
    case upcomingWeek
    case todayAndTomorrow

    var visibleDayCount: Int {
        switch self {
        case .week:
            return 7
        case .upcomingWeek:
            return 7
        case .todayAndTomorrow:
            return 2
        }
    }

    var resetButtonTitle: String {
        switch self {
        case .week:
            return "This Week"
        case .upcomingWeek:
            return "Today"
        case .todayAndTomorrow:
            return "Today"
        }
    }
}

private struct WeekCalendarDragPreview: Equatable {
    let eventIdentifier: String
    let title: String
    let interval: DateInterval
    let columnIndex: Int
}

enum WeekCalendarEventLayout {
    static let columnGap: CGFloat = 4

    static func frames(
        for events: [TodayMdCalendarEventSummary],
        on day: Date,
        timelineHeight: CGFloat,
        dayColumnWidth: CGFloat,
        calendar: Calendar = .current
    ) -> [String: CGRect] {
        let sortedEvents = events.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }

        var frames: [String: CGRect] = [:]
        var cluster: [TodayMdCalendarEventSummary] = []
        var activeClusterEnd: Date?

        for event in sortedEvents {
            if let currentClusterEnd = activeClusterEnd, event.startDate >= currentClusterEnd, !cluster.isEmpty {
                assignFrames(
                    for: cluster,
                    on: day,
                    timelineHeight: timelineHeight,
                    dayColumnWidth: dayColumnWidth,
                    calendar: calendar,
                    into: &frames
                )
                cluster.removeAll(keepingCapacity: true)
                activeClusterEnd = nil
            }

            cluster.append(event)
            if let existingClusterEnd = activeClusterEnd {
                activeClusterEnd = max(existingClusterEnd, event.endDate)
            } else {
                activeClusterEnd = event.endDate
            }
        }

        if !cluster.isEmpty {
            assignFrames(
                for: cluster,
                on: day,
                timelineHeight: timelineHeight,
                dayColumnWidth: dayColumnWidth,
                calendar: calendar,
                into: &frames
            )
        }

        return frames
    }

    private static func assignFrames(
        for cluster: [TodayMdCalendarEventSummary],
        on day: Date,
        timelineHeight: CGFloat,
        dayColumnWidth: CGFloat,
        calendar: Calendar,
        into frames: inout [String: CGRect]
    ) {
        var laneEnds: [Date] = []
        var laneAssignments: [String: Int] = [:]
        var laneCount = 0

        for event in cluster {
            if let reusableLane = laneEnds.firstIndex(where: { $0 <= event.startDate }) {
                laneAssignments[event.id] = reusableLane
                laneEnds[reusableLane] = event.endDate
            } else {
                laneAssignments[event.id] = laneEnds.count
                laneEnds.append(event.endDate)
            }

            laneCount = max(laneCount, laneEnds.count)
        }

        let usableWidth = dayColumnWidth - (WeekCalendarPanelStyle.eventHorizontalInset * 2)
        let totalGap = CGFloat(max(laneCount - 1, 0)) * columnGap
        let cardWidth = max((usableWidth - totalGap) / CGFloat(max(laneCount, 1)), 44)

        for event in cluster {
            let laneIndex = laneAssignments[event.id] ?? 0
            let metrics = metrics(for: event, on: day, timelineHeight: timelineHeight, calendar: calendar)
            let x = WeekCalendarPanelStyle.eventHorizontalInset + (CGFloat(laneIndex) * (cardWidth + columnGap))

            frames[event.id] = CGRect(
                x: x,
                y: metrics.y,
                width: cardWidth,
                height: max(metrics.height, 34)
            )
        }
    }

    private static func metrics(
        for event: TodayMdCalendarEventSummary,
        on day: Date,
        timelineHeight: CGFloat,
        calendar: Calendar
    ) -> (y: CGFloat, height: CGFloat) {
        let dayStart = calendar.date(bySettingHour: WeekCalendarPanelStyle.dayStartHour, minute: 0, second: 0, of: day)
            ?? calendar.startOfDay(for: day)
        let dayEnd = calendar.date(bySettingHour: WeekCalendarPanelStyle.dayEndHour, minute: 0, second: 0, of: day)
            ?? dayStart.addingTimeInterval(16 * 60 * 60)
        let totalVisibleMinutes = Double(WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * 60
        let start = max(event.startDate, dayStart)
        let end = min(event.endDate, dayEnd)
        let startMinutes = start.timeIntervalSince(dayStart) / 60
        let endMinutes = end.timeIntervalSince(dayStart) / 60
        let y = CGFloat(startMinutes / totalVisibleMinutes) * timelineHeight
        let height = CGFloat((endMinutes - startMinutes) / totalVisibleMinutes) * timelineHeight
        return (y, max(height, 18))
    }
}

struct WeekCalendarPanelView: View {
    let displayMode: WeekCalendarPanelDisplayMode

    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var calendarService: TodayMdCalendarService
    @AppStorage(TodayMdPreferenceKey.calendarDefaultDurationMinutes) private var calendarDefaultDurationMinutes = 60
    @AppStorage(TodayMdPreferenceKey.calendarDefaultIdentifier) private var calendarDefaultIdentifier = ""
    @AppStorage(TodayMdPreferenceKey.calendarVisibleIdentifiers) private var calendarVisibleIdentifiersRaw = ""

    @State private var visibleWeekStart: Date
    @State private var weekEventsByDay: [Date: [TodayMdCalendarEventSummary]] = [:]
    @State private var activeDraggedEvent: TodayMdCalendarEventSummary?
    @State private var dragPreview: WeekCalendarDragPreview?
    @State private var selectedEvent: TodayMdCalendarEventSummary?
    @State private var selectedEventFrame: CGRect?
    @State private var pendingDeletionEvent: TodayMdCalendarEventSummary?
    @State private var isScheduling = false
    @State private var isDeleting = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    init(displayMode: WeekCalendarPanelDisplayMode = .week) {
        self.displayMode = displayMode
        _visibleWeekStart = State(initialValue: Self.defaultVisibleStart(for: displayMode))
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var preferredIdentifier: String? {
        calendarDefaultIdentifier.isEmpty ? nil : calendarDefaultIdentifier
    }

    private var effectiveDefaultDuration: Int {
        [30, 60, 90, 120].contains(calendarDefaultDurationMinutes) ? calendarDefaultDurationMinutes : 60
    }

    private func calendarAuthorizationMessage(for capability: String) -> String {
        let settingsPath = calendarService.authorizationStatus.settingsActivationPath ?? "System Settings > Privacy & Security > Calendars"

        switch calendarService.authorizationStatus {
        case .notDetermined:
            return "Grant calendar access to \(capability)"
        case .denied:
            return "Enable today-md in \(settingsPath) to \(capability)"
        case .restricted:
            return "Review \(settingsPath) to \(capability) Access may still be managed by Screen Time or device policies on this Mac."
        case .writeOnly:
            return "Change today-md to Full Access in \(settingsPath) to \(capability)"
        case .fullAccess:
            return capability
        }
    }

    private var timelineHeight: CGFloat {
        CGFloat(WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * WeekCalendarPanelStyle.hourHeight
    }

    private var totalVisibleMinutes: Double {
        Double(WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * 60
    }

    private var weekDays: [Date] {
        (0..<displayMode.visibleDayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: visibleWeekStart)
        }
    }

    private var weekInterval: DateInterval {
        let visibleDays = displayMode.visibleDayCount
        let end = calendar.date(byAdding: .day, value: visibleDays, to: visibleWeekStart)
            ?? visibleWeekStart.addingTimeInterval(TimeInterval(visibleDays * 24 * 60 * 60))
        return DateInterval(start: visibleWeekStart, end: end)
    }

    private var destinationTitle: String {
        calendarService.selectedDestinationCalendar(preferredIdentifier: preferredIdentifier)?.displayTitle ?? "No writable calendar"
    }

    private var availableCalendars: [TodayMdCalendarSummary] {
        calendarService.calendars
    }

    private var visibleCalendarIdentifiers: Set<String> {
        TaskCalendarVisibilitySelection.resolvedIdentifiers(
            from: calendarVisibleIdentifiersRaw,
            availableCalendars: availableCalendars
        )
    }

    private var allCalendarsVisible: Bool {
        availableCalendars.isEmpty || visibleCalendarIdentifiers.count >= availableCalendars.count
    }

    private var weekRangeText: String {
        let trailingDayCount = max(displayMode.visibleDayCount - 1, 0)
        guard let lastDay = calendar.date(byAdding: .day, value: trailingDayCount, to: visibleWeekStart) else {
            return visibleWeekStart.formatted(date: .abbreviated, time: .omitted)
        }

        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: visibleWeekStart, to: lastDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            guidance
            plannerContent
            messageContent
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            calendarService.refreshIfNeeded()
            reloadWeekEvents()
        }
        .onChange(of: visibleWeekStart) { _, _ in
            reloadWeekEvents()
        }
        .onChange(of: calendarService.authorizationStatus) { _, _ in
            reloadWeekEvents()
        }
        .onChange(of: calendarService.refreshRevision, initial: true) { _, _ in
            reloadWeekEvents()
        }
        .onChange(of: calendarVisibleIdentifiersRaw, initial: true) { _, _ in
            reloadWeekEvents()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar")
                    .font(.title3.weight(.semibold))
                Text(destinationTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    shiftWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button(displayMode.resetButtonTitle) {
                    visibleWeekStart = Self.defaultVisibleStart(for: displayMode)
                }
                .buttonStyle(.bordered)

                Button {
                    shiftWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekRangeText)
                .font(.subheadline.weight(.semibold))

            Text("Drag tasks from the board into any day column to place a \(effectiveDefaultDuration) minute blocker. Click an entry to inspect it, drag the body to move it, drag the top or bottom edge to resize it, and use the delete badge to remove calendar-colored blockers directly in the weekly view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var plannerContent: some View {
        if !calendarService.authorizationStatus.canReadEvents {
            unavailableState(
                title: calendarService.authorizationStatus.resolutionActionTitle,
                message: calendarAuthorizationMessage(for: "drag tasks into the week, inspect availability, and place time blocks without leaving this workspace."),
                actionTitle: calendarService.authorizationStatus.resolutionActionTitle,
                action: {
                    calendarService.resolveAuthorization()
                }
            )
        } else if calendarService.selectedDestinationCalendar(preferredIdentifier: preferredIdentifier) == nil {
            unavailableState(
                title: "No Writable Calendar",
                message: "Add an iCloud, Google, Outlook, or Exchange calendar in the macOS Calendar app, then come back here to drop tasks straight onto your week.",
                actionTitle: nil,
                action: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if availableCalendars.count > 1 {
                    calendarVisibilityRow
                }

                weekGrid
            }
        }
    }

    private var calendarVisibilityRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(
                    allCalendarsVisible
                        ? "Showing all calendars"
                        : "Showing \(visibleCalendarIdentifiers.count) of \(availableCalendars.count) calendars"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                if !allCalendarsVisible {
                    Button("Show All") {
                        calendarVisibleIdentifiersRaw = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableCalendars) { calendar in
                        calendarVisibilityChip(calendar)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func calendarVisibilityChip(_ calendar: TodayMdCalendarSummary) -> some View {
        let isSelected = visibleCalendarIdentifiers.contains(calendar.id)

        return Button {
            toggleCalendarVisibility(calendar)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(calendar.accentColor)
                    .frame(width: 9, height: 9)

                Text(calendar.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? calendar.accentColor.opacity(0.18)
                            : Color.secondary.opacity(0.08)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected
                            ? calendar.accentColor.opacity(0.34)
                            : Color.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .opacity(isSelected ? 1 : 0.74)
        }
        .buttonStyle(.plain)
        .help("\(calendar.displayTitle)\n\(calendar.subtitle)")
    }

    private func unavailableState(
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 18) {
            ContentUnavailableView {
                Label(title, systemImage: "calendar.badge.plus")
            } description: {
                Text(message)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }

            Text(weekRangeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))
                )
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var weekGrid: some View {
        GeometryReader { geometry in
            let dayColumnWidth = resolvedDayColumnWidth(containerWidth: geometry.size.width)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Color.clear
                            .frame(width: WeekCalendarPanelStyle.hourLabelWidth, height: 1)

                        ForEach(weekDays, id: \.self) { day in
                            dayHeader(for: day)
                                .frame(width: dayColumnWidth, alignment: .topLeading)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        hourLabelColumn
                        weekColumnsSection(dayColumnWidth: dayColumnWidth)
                    }
                }
                .padding(16)
                .frame(
                    minWidth: max(geometry.size.width - 2, requiredGridWidth(for: dayColumnWidth)),
                    alignment: .leading
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.12), lineWidth: 1)
        )
    }

    private func weekColumnsSection(dayColumnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            WeekCalendarCanvasView(
                days: weekDays,
                eventsByDay: Dictionary(uniqueKeysWithValues: weekDays.map { day in
                    (calendar.startOfDay(for: day), timedEvents(for: day))
                }),
                timelineHeight: timelineHeight,
                dayColumnWidth: dayColumnWidth,
                defaultDurationMinutes: effectiveDefaultDuration,
                isInteractionEnabled: !(isScheduling || isDeleting),
                selectedEventID: selectedEvent?.id,
                pendingDeletionEventID: pendingDeletionEvent?.id,
                onDropTask: { taskID, interval in
                    scheduleDroppedTask(taskID, interval: interval)
                },
                onSelectEvent: { event, frame in
                    if pendingDeletionEvent?.id != event?.id {
                        pendingDeletionEvent = nil
                    }
                    selectedEvent = event
                    selectedEventFrame = frame
                },
                onDeleteEvent: { event in
                    requestDeletion(for: event)
                },
                onMoveEvent: { event, interval in
                    moveEvent(event, to: interval)
                }
            )

            if let selectedEvent {
                anchoredSelectedEventPopup(selectedEvent, dayColumnWidth: dayColumnWidth)
            }
        }
        .frame(width: columnsWidth(for: dayColumnWidth), height: timelineHeight)
    }

    private func dayHeader(for day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let allDayEvents = allDayEvents(for: day)
        let weekdayText = day.formatted(.dateTime.weekday(.abbreviated))
        let dayNumberText = day.formatted(.dateTime.day())

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(weekdayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(dayNumberText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isToday ? .orange : .primary)
            }

            if allDayEvents.isEmpty {
                Text("Drop here to schedule")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allDayEvents.prefix(2)) { event in
                        allDayEventPreview(event)
                    }

                    if allDayEvents.count > 2 {
                        Text("+\(allDayEvents.count - 2) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(isToday ? 0.96 : 0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isToday ? Color.orange.opacity(0.24) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func allDayEventPreview(_ event: TodayMdCalendarEventSummary) -> some View {
        let isSelected = selectedEvent?.id == event.id

        return HStack(spacing: 6) {
            Text(event.title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)

            if event.canDelete {
                Button {
                    requestDeletion(for: event)
                } label: {
                    inlineDeleteBadge(size: 14, isArmed: isDeletionPending(for: event))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule()
                .fill(event.accentColor.opacity(isSelected ? 0.20 : 0.14))
        )
        .overlay(
            Capsule()
                .stroke(event.accentColor.opacity(isSelected ? 0.34 : 0.22), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture {
            pendingDeletionEvent = nil
            selectedEvent = event
            selectedEventFrame = nil
        }
    }

    private var hourLabelColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(WeekCalendarPanelStyle.dayStartHour..<WeekCalendarPanelStyle.dayEndHour + 1, id: \.self) { hour in
                Text(hourLabel(for: hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: WeekCalendarPanelStyle.hourHeight, alignment: .topTrailing)
            }
        }
        .frame(width: WeekCalendarPanelStyle.hourLabelWidth)
    }

    private var selectedEventPopupWidth: CGFloat { 344 }

    private var selectedEventPopupHeight: CGFloat { 236 }

    private func anchoredSelectedEventPopup(_ event: TodayMdCalendarEventSummary, dayColumnWidth: CGFloat) -> some View {
        let metrics = popoverMetrics(for: event, dayColumnWidth: dayColumnWidth)
        let popupWidth = selectedEventPopupWidth
        let popupHeight = selectedEventPopupHeight
        let arrowSize: CGFloat = 16
        let cardX = metrics.origin.x
        let cardY = metrics.origin.y
        let arrowOffset = min(max(metrics.arrowY - cardY - 24, 36), popupHeight - 36)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .frame(width: popupWidth, height: popupHeight)
                .overlay {
                    ScrollView {
                        popupBody(for: event)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: popupWidth, height: popupHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .overlay(alignment: metrics.arrowEdge) {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: arrowSize, height: arrowSize)
                        .rotationEffect(.degrees(45))
                        .overlay(
                            Rectangle()
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                .frame(width: arrowSize, height: arrowSize)
                                .rotationEffect(.degrees(45))
                        )
                        .offset(
                            x: metrics.arrowEdge == .leading ? -arrowSize / 2 : arrowSize / 2,
                            y: arrowOffset - popupHeight / 2
                        )
                }
        }
        .frame(width: popupWidth, height: popupHeight)
        .offset(x: cardX, y: cardY)
        .zIndex(20)
    }

    private func popupBody(for event: TodayMdCalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(event.accentColor)
                    .frame(width: 16, height: 16)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(3)

                    Text(scheduleText(for: event))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    if event.isTodayMdBlock {
                        Text("Created from today-md")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }
                }

                Spacer(minLength: 8)

                Button {
                    pendingDeletionEvent = nil
                    selectedEvent = nil
                    selectedEventFrame = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }

            Divider()

            detailRow(label: "Calendar", value: event.calendarTitle)

            if let location = event.location {
                detailRow(label: "Location", value: location)
            }

            if let url = event.url {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Link(url.absoluteString, destination: url)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            if event.canDelete {
                Divider()

                HStack(spacing: 12) {
                    let isArmed = isDeletionPending(for: event)
                    Button {
                        requestDeletion(for: event)
                    } label: {
                        Label(
                            "Delete",
                            systemImage: isArmed ? "checkmark" : "xmark"
                        )
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                    .tint(isArmed ? .red : .gray)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func popoverMetrics(for event: TodayMdCalendarEventSummary, dayColumnWidth: CGFloat) -> (origin: CGPoint, arrowY: CGFloat, arrowEdge: Alignment) {
        let popupWidth = selectedEventPopupWidth
        let popupHeight = selectedEventPopupHeight
        let margin: CGFloat = 14

        let anchor = selectedEventFrame ?? CGRect(
            x: columnsWidth(for: dayColumnWidth) * 0.35,
            y: 96,
            width: dayColumnWidth - (WeekCalendarPanelStyle.eventHorizontalInset * 2),
            height: 44
        )

        let totalColumnsWidth = columnsWidth(for: dayColumnWidth)
        let preferRight = anchor.maxX + 28 + popupWidth <= totalColumnsWidth - margin
        let x: CGFloat
        let arrowEdge: Alignment
        if preferRight {
            x = min(anchor.maxX + 20, totalColumnsWidth - popupWidth - margin)
            arrowEdge = .leading
        } else {
            x = max(anchor.minX - popupWidth - 20, margin)
            arrowEdge = .trailing
        }

        let y = min(
            max(anchor.midY - (popupHeight * 0.36), margin),
            max(timelineHeight - popupHeight - margin, margin)
        )

        return (CGPoint(x: x, y: y), anchor.midY, arrowEdge)
    }

    @ViewBuilder
    private var messageContent: some View {
        if let successMessage {
            Text(successMessage)
                .font(.caption)
                .foregroundStyle(.green)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else if let lastError = calendarService.lastError {
            Text(lastError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func shiftWeek(by delta: Int) {
        let visibleDays = displayMode.visibleDayCount
        guard let nextRange = calendar.date(byAdding: .day, value: delta * visibleDays, to: visibleWeekStart) else { return }
        visibleWeekStart = Self.normalizedVisibleStart(for: nextRange, displayMode: displayMode, calendar: calendar)
    }

    private func reloadWeekEvents() {
        guard calendarService.authorizationStatus.canReadEvents else {
            weekEventsByDay = [:]
            selectedEvent = nil
            selectedEventFrame = nil
            return
        }

        let groupedEvents = Dictionary(grouping: calendarService.events(in: weekInterval, visibleCalendarIdentifiers: visibleCalendarIdentifiers)) { event in
            calendar.startOfDay(for: event.startDate)
        }
        weekEventsByDay = groupedEvents

        if let selectedEvent {
            let refreshedEvents = groupedEvents.values.flatMap { $0 }
            self.selectedEvent = refreshedEvents.first(where: { $0.id == selectedEvent.id })
            if self.selectedEvent == nil {
                selectedEventFrame = nil
            }
        }
    }

    private func timedEvents(for day: Date) -> [TodayMdCalendarEventSummary] {
        let dayStart = calendar.startOfDay(for: day)
        return (weekEventsByDay[dayStart] ?? [])
            .filter { !$0.isAllDay }
            .filter { $0.endDate > displayDayStart(for: day) && $0.startDate < displayDayEnd(for: day) }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
    }

    private func allDayEvents(for day: Date) -> [TodayMdCalendarEventSummary] {
        let dayStart = calendar.startOfDay(for: day)
        return (weekEventsByDay[dayStart] ?? [])
            .filter(\.isAllDay)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func displayDayStart(for day: Date) -> Date {
        calendar.date(bySettingHour: WeekCalendarPanelStyle.dayStartHour, minute: 0, second: 0, of: day) ?? calendar.startOfDay(for: day)
    }

    private func displayDayEnd(for day: Date) -> Date {
        calendar.date(bySettingHour: WeekCalendarPanelStyle.dayEndHour, minute: 0, second: 0, of: day)
            ?? displayDayStart(for: day).addingTimeInterval(16 * 60 * 60)
    }

    private func metrics(for interval: DateInterval, on day: Date) -> (y: CGFloat, height: CGFloat) {
        let start = max(interval.start, displayDayStart(for: day))
        let end = min(interval.end, displayDayEnd(for: day))
        let startMinutes = start.timeIntervalSince(displayDayStart(for: day)) / 60
        let endMinutes = end.timeIntervalSince(displayDayStart(for: day)) / 60
        let y = CGFloat(startMinutes / totalVisibleMinutes) * timelineHeight
        let height = CGFloat((endMinutes - startMinutes) / totalVisibleMinutes) * timelineHeight
        return (y, max(height, 18))
    }

    private func metrics(for event: TodayMdCalendarEventSummary, on day: Date) -> (y: CGFloat, height: CGFloat) {
        metrics(for: DateInterval(start: event.startDate, end: event.endDate), on: day)
    }

    private func intervalForDroppedTask(on day: Date, yPosition: CGFloat) -> DateInterval {
        let start = snappedDate(for: yPosition, on: day)
        return clampedInterval(startingAt: start, durationMinutes: effectiveDefaultDuration, on: day)
    }

    private func snappedDate(for yPosition: CGFloat, on day: Date) -> Date {
        let clampedY = min(max(yPosition, 0), timelineHeight)
        let rawMinutes = Double(clampedY / timelineHeight) * totalVisibleMinutes
        let snappedMinutes = (rawMinutes / Double(WeekCalendarPanelStyle.snapMinutes)).rounded() * Double(WeekCalendarPanelStyle.snapMinutes)
        let minuteOffset = Int(snappedMinutes)
        return calendar.date(byAdding: .minute, value: minuteOffset, to: displayDayStart(for: day)) ?? displayDayStart(for: day)
    }

    private func clampedInterval(startingAt start: Date, durationMinutes: Int, on day: Date) -> DateInterval {
        let duration = TimeInterval(max(durationMinutes, WeekCalendarPanelStyle.minimumDurationMinutes) * 60)
        let dayStart = displayDayStart(for: day)
        let dayEnd = displayDayEnd(for: day)
        var interval = DateInterval(start: min(max(start, dayStart), dayEnd), duration: duration)

        if interval.end > dayEnd {
            let adjustedStart = max(dayStart, dayEnd.addingTimeInterval(-duration))
            interval = DateInterval(start: adjustedStart, end: dayEnd)
        }

        return interval
    }

    private func clampedColumnIndex(for x: CGFloat) -> Int {
        let band = WeekCalendarPanelStyle.minimumDayColumnWidth + WeekCalendarPanelStyle.dayColumnSpacing
        let rawIndex = Int((max(x, 0) / band).rounded(.down))
        return min(max(rawIndex, 0), weekDays.count - 1)
    }

    private func columnIndex(for date: Date) -> Int? {
        weekDays.firstIndex { calendar.isDate($0, inSameDayAs: date) }
    }

    private func timeText(for interval: DateInterval) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: interval.start, to: interval.end)
    }

    private func scheduleText(for event: TodayMdCalendarEventSummary) -> String {
        if event.isAllDay {
            let startDay = calendar.startOfDay(for: event.startDate)
            let endDay = calendar.startOfDay(for: event.endDate)
            let spanDays = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0

            if spanDays <= 1 {
                return "\(startDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) • All day"
            }

            let displayEndDay = calendar.date(byAdding: .day, value: -1, to: endDay) ?? event.endDate

            let formatter = DateIntervalFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "\(formatter.string(from: startDay, to: displayEndDay)) • All day"
        }

        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate, to: event.endDate)
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func scheduleDroppedTask(_ taskID: UUID, interval: DateInterval) -> Bool {
        guard let task = store.task(id: taskID) else { return false }
        createManagedBlock(for: task, interval: interval)
        return true
    }

    private func createManagedBlock(for task: TaskItem, interval: DateInterval) {
        successMessage = nil
        errorMessage = nil
        isScheduling = true

        Task { @MainActor in
            defer { isScheduling = false }

            do {
                let result = try calendarService.createBlock(
                    for: task,
                    interval: interval,
                    preferredCalendarIdentifier: preferredIdentifier,
                    replacingExistingManagedBlocks: true
                )

                if let taskID = result.taskID {
                    store.syncTaskBlockWithScheduledDate(id: taskID, scheduledDate: result.startDate, calendar: calendar)
                }
                successMessage = "Scheduled \(task.title) for \(result.startDate.formatted(date: .omitted, time: .shortened))."
                reloadWeekEvents()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func moveEvent(_ event: TodayMdCalendarEventSummary, to interval: DateInterval) {
        guard let eventIdentifier = event.eventIdentifier else {
            errorMessage = "Only blockers created from today-md can be moved here."
            return
        }

        guard interval.start != event.startDate || interval.end != event.endDate else {
            return
        }

        successMessage = nil
        errorMessage = nil
        isScheduling = true

        Task { @MainActor in
            defer { isScheduling = false }

            do {
                let result = try calendarService.moveEvent(identifier: eventIdentifier, to: interval)
                if let taskID = result.taskID {
                    store.syncTaskBlockWithScheduledDate(id: taskID, scheduledDate: result.startDate, calendar: calendar)
                }
                let formatter = DateIntervalFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                successMessage = "Updated \(event.title): \(formatter.string(from: result.startDate, to: result.endDate))"
                reloadWeekEvents()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func scheduleDroppedTask(_ taskID: UUID, on day: Date, yPosition: CGFloat) -> Bool {
        guard let task = store.task(id: taskID) else { return false }
        let interval = intervalForDroppedTask(on: day, yPosition: yPosition)
        createManagedBlock(for: task, interval: interval)
        return true
    }

    private func deleteEvent(_ event: TodayMdCalendarEventSummary) {
        guard let eventIdentifier = event.eventIdentifier else {
            errorMessage = "Only blockers created from today-md can be deleted here."
            pendingDeletionEvent = nil
            return
        }

        successMessage = nil
        errorMessage = nil
        isDeleting = true

        Task { @MainActor in
            defer {
                isDeleting = false
                pendingDeletionEvent = nil
            }

            do {
                try calendarService.deleteEvent(identifier: eventIdentifier)
                if let taskID = event.taskID {
                    store.setTaskSchedulingState(id: taskID, isScheduled: false)
                }
                reloadWeekEvents()
                successMessage = "Deleted \(event.title)."
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func requestDeletion(for event: TodayMdCalendarEventSummary) {
        guard !isDeleting, event.canDelete else { return }

        if isDeletionPending(for: event) {
            deleteEvent(event)
        } else {
            pendingDeletionEvent = event
        }
    }

    private func isDeletionPending(for event: TodayMdCalendarEventSummary) -> Bool {
        pendingDeletionEvent?.id == event.id
    }

    private func inlineDeleteBadge(size: CGFloat, isArmed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))

            Image(systemName: isArmed ? "checkmark" : "xmark")
                .font(.system(size: size * 0.72, weight: .bold))
                .foregroundStyle(isArmed ? Color.red.opacity(0.88) : Color.secondary.opacity(0.72))
        }
        .frame(width: size, height: size)
    }

    private func hourLabel(for hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: visibleWeekStart) ?? visibleWeekStart
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func beginEventMove(_ event: TodayMdCalendarEventSummary) {
        guard event.canEdit,
              let eventIdentifier = event.eventIdentifier,
              let columnIndex = columnIndex(for: event.startDate) else {
            return
        }

        if activeDraggedEvent?.id == event.id {
            return
        }

        successMessage = nil
        errorMessage = nil
        activeDraggedEvent = event
        dragPreview = WeekCalendarDragPreview(
            eventIdentifier: eventIdentifier,
            title: event.title,
            interval: DateInterval(start: event.startDate, end: event.endDate),
            columnIndex: columnIndex
        )
    }

    private func updateEventMove(for event: TodayMdCalendarEventSummary, location: CGPoint) {
        beginEventMove(event)
        guard let activeDraggedEvent, activeDraggedEvent.id == event.id else { return }

        let columnIndex = clampedColumnIndex(for: location.x)
        let day = weekDays[columnIndex]
        let durationMinutes = max(Int(activeDraggedEvent.endDate.timeIntervalSince(activeDraggedEvent.startDate) / 60), WeekCalendarPanelStyle.minimumDurationMinutes)
        let start = snappedDate(for: location.y, on: day)

        dragPreview = WeekCalendarDragPreview(
            eventIdentifier: activeDraggedEvent.eventIdentifier ?? event.id,
            title: activeDraggedEvent.title,
            interval: clampedInterval(startingAt: start, durationMinutes: durationMinutes, on: day),
            columnIndex: columnIndex
        )
    }

    private func endEventMove(for event: TodayMdCalendarEventSummary, location: CGPoint) {
        updateEventMove(for: event, location: location)

        guard let activeDraggedEvent,
              activeDraggedEvent.id == event.id,
              let dragPreview,
              let eventIdentifier = activeDraggedEvent.eventIdentifier else {
            self.activeDraggedEvent = nil
            self.dragPreview = nil
            return
        }

        self.activeDraggedEvent = nil
        self.dragPreview = nil
        isScheduling = true

        Task { @MainActor in
            defer { isScheduling = false }

            do {
                let result = try calendarService.moveEvent(identifier: eventIdentifier, to: dragPreview.interval)
                if let taskID = result.taskID {
                    store.syncTaskBlockWithScheduledDate(id: taskID, scheduledDate: result.startDate, calendar: calendar)
                }
                successMessage = "Moved blocker to \(result.startDate.formatted(date: .abbreviated, time: .shortened))."
                reloadWeekEvents()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func dragPreviewCard(_ preview: WeekCalendarDragPreview) -> some View {
        let metrics = metrics(for: preview.interval, on: weekDays[preview.columnIndex])
        let previewFrames = dayColumnFrames(for: WeekCalendarPanelStyle.minimumDayColumnWidth)

        return VStack(alignment: .leading, spacing: 4) {
            Text(preview.title)
                .font(.caption.weight(.semibold))
                .lineLimit(metrics.height < 46 ? 1 : 2)
                .truncationMode(.tail)

            if metrics.height >= 46 {
                Text(timeText(for: preview.interval))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(
            width: WeekCalendarPanelStyle.minimumDayColumnWidth - (WeekCalendarPanelStyle.eventHorizontalInset * 2),
            height: max(metrics.height, 34),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.34), lineWidth: 1)
        )
        .offset(
            x: previewFrames[preview.columnIndex].minX + WeekCalendarPanelStyle.eventHorizontalInset,
            y: metrics.y
        )
    }

    private func resolvedDayColumnWidth(containerWidth: CGFloat) -> CGFloat {
        let totalSpacing = CGFloat(max(weekDays.count - 1, 0)) * WeekCalendarPanelStyle.dayColumnSpacing
        let availableColumnsWidth = containerWidth
            - WeekCalendarPanelStyle.hourLabelWidth
            - 8
            - 32
            - totalSpacing
        let stretchedWidth = availableColumnsWidth / CGFloat(max(weekDays.count, 1))
        return max(WeekCalendarPanelStyle.minimumDayColumnWidth, stretchedWidth.rounded(.down))
    }

    private func columnsWidth(for dayColumnWidth: CGFloat) -> CGFloat {
        (CGFloat(weekDays.count) * dayColumnWidth)
        + (CGFloat(max(weekDays.count - 1, 0)) * WeekCalendarPanelStyle.dayColumnSpacing)
    }

    private func dayColumnFrames(for dayColumnWidth: CGFloat) -> [CGRect] {
        weekDays.indices.map { index in
            CGRect(
                x: CGFloat(index) * (dayColumnWidth + WeekCalendarPanelStyle.dayColumnSpacing),
                y: 0,
                width: dayColumnWidth,
                height: timelineHeight
            )
        }
    }

    private func requiredGridWidth(for dayColumnWidth: CGFloat) -> CGFloat {
        WeekCalendarPanelStyle.hourLabelWidth + 8 + columnsWidth(for: dayColumnWidth) + 32
    }

    private static func defaultVisibleStart(
        for displayMode: WeekCalendarPanelDisplayMode,
        calendar: Calendar = .current
    ) -> Date {
        normalizedVisibleStart(for: Date(), displayMode: displayMode, calendar: calendar)
    }

    private static func normalizedVisibleStart(
        for date: Date,
        displayMode: WeekCalendarPanelDisplayMode,
        calendar: Calendar
    ) -> Date {
        switch displayMode {
        case .week:
            return startOfWeek(for: date, calendar: calendar)
        case .upcomingWeek:
            return calendar.startOfDay(for: date)
        case .todayAndTomorrow:
            return calendar.startOfDay(for: date)
        }
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.mondayBasedWeekInterval(containing: date).start
    }

    private func toggleCalendarVisibility(_ calendar: TodayMdCalendarSummary) {
        let availableIdentifiers = Set(availableCalendars.map(\.id))
        guard availableIdentifiers.contains(calendar.id) else { return }

        var updatedSelection = visibleCalendarIdentifiers

        if allCalendarsVisible {
            updatedSelection = availableIdentifiers.subtracting([calendar.id])
        } else if updatedSelection.contains(calendar.id) {
            guard updatedSelection.count > 1 else { return }
            updatedSelection.remove(calendar.id)
        } else {
            updatedSelection.insert(calendar.id)
        }

        calendarVisibleIdentifiersRaw = TaskCalendarVisibilitySelection.storedValue(
            for: updatedSelection,
            availableCalendars: availableCalendars
        )
    }
}

private struct WeekCalendarDayColumn: View {
    let day: Date
    let events: [TodayMdCalendarEventSummary]
    let eventFrames: [String: CGRect]
    let timelineHeight: CGFloat
    let hiddenEventIdentifier: String?
    let pendingDeletionEventID: String? = nil
    let onMoveEventStart: (TodayMdCalendarEventSummary) -> Void
    let onMoveEventChange: (TodayMdCalendarEventSummary, CGPoint) -> Void
    let onMoveEventEnd: (TodayMdCalendarEventSummary, CGPoint) -> Void
    let onDropTask: (UUID, CGFloat) -> Bool
    let onDeleteEvent: (TodayMdCalendarEventSummary) -> Void

    @State private var isTaskTargeted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            dayGrid

            ForEach(events) { event in
                if hiddenEventIdentifier != event.eventIdentifier,
                   let frame = eventFrames[event.id] {
                    timedEventBlock(event, frame: frame)
                }
            }
        }
        .frame(width: WeekCalendarPanelStyle.minimumDayColumnWidth, height: timelineHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isTaskTargeted ? Color.orange.opacity(0.35) : Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .dropDestination(for: TaskItemTransfer.self) { items, location in
            guard let taskID = items.first?.id else { return false }
            return onDropTask(taskID, location.y)
        } isTargeted: { targeted in
            isTaskTargeted = targeted
        }
    }

    private var dayGrid: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(isTaskTargeted ? 0.96 : 1))

            ForEach(0...(WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * 2, id: \.self) { tick in
                Rectangle()
                    .fill(tick.isMultiple(of: 2) ? Color.secondary.opacity(0.16) : Color.secondary.opacity(0.08))
                    .frame(height: tick.isMultiple(of: 2) ? 1 : 0.5)
                    .offset(y: CGFloat(tick) * (WeekCalendarPanelStyle.hourHeight / 2))
            }
        }
    }

    @ViewBuilder
    private func timedEventBlock(_ event: TodayMdCalendarEventSummary, frame: CGRect) -> some View {
        let compact = frame.height < 46

        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)

                if !compact {
                    Text(timeText(for: event))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .padding(.trailing, event.canDelete ? 20 : 0)

            if event.canDelete {
                Button {
                    onDeleteEvent(event)
                } label: {
                    inlineDeleteBadge(
                        size: 16,
                        isArmed: pendingDeletionEventID == event.id
                    )
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .frame(
            width: frame.width,
            height: frame.height,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(event.accentColor.opacity(event.canDelete ? 0.20 : 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(event.accentColor.opacity(event.canEdit ? 0.36 : 0.24), lineWidth: 1)
        )
        .offset(x: frame.minX, y: frame.minY)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .highPriorityGesture(eventMoveGesture(for: event), including: event.canEdit ? .gesture : .subviews)
    }

    private func timeText(for event: TodayMdCalendarEventSummary) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate, to: event.endDate)
    }

    private func inlineDeleteBadge(size: CGFloat, isArmed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))

            Image(systemName: isArmed ? "checkmark" : "xmark")
                .font(.system(size: size * 0.72, weight: .bold))
                .foregroundStyle(isArmed ? Color.red.opacity(0.88) : Color.secondary.opacity(0.72))
        }
        .frame(width: size, height: size)
    }

    private func eventMoveGesture(for event: TodayMdCalendarEventSummary) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("WeekCalendarColumns"))
            .onChanged { value in
                guard event.canEdit else { return }
                onMoveEventStart(event)
                onMoveEventChange(event, value.location)
            }
            .onEnded { value in
                guard event.canEdit else { return }
                onMoveEventEnd(event, value.location)
            }
    }
}

