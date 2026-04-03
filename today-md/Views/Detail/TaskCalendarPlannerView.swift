import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum TaskCalendarTimelineStyle {
    static let dayStartHour = 6
    static let dayEndHour = 22
    static let hourHeight: CGFloat = 78
    static let hourLabelWidth: CGFloat = 58
    static let snapMinutes = 15
    static let minimumDurationMinutes = 15
    static let resizeHandleHeight: CGFloat = 22
    static let resizeHandleWidth: CGFloat = 34
    static let resizeHandleThickness: CGFloat = 6
    static let deleteBadgeInset: CGFloat = 8
    static let compactDeleteBadgeSize: CGFloat = 18
    static let regularDeleteBadgeSize: CGFloat = 20
}

private enum TaskCalendarCardDensity {
    case compact
    case standard
    case expanded
}

private enum TaskCalendarTimelineInteractionMode {
    case move
    case resizeStart
    case resizeEnd
}

private struct TaskCalendarTimelineDeleteTarget: Equatable {
    let eventID: String
    let rect: CGRect
}

private enum TaskCalendarVisibilitySelection {
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

private extension TodayMdCalendarSummary {
    var accentColor: Color {
        Color(nsColor: nsColor)
    }
}

private extension TodayMdCalendarEventSummary {
    var accentColor: Color {
        Color(nsColor: nsColor)
    }
}

struct TaskCalendarPlannerView: View {
    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var calendarService: TodayMdCalendarService
    @AppStorage(TodayMdPreferenceKey.calendarDefaultDurationMinutes) private var calendarDefaultDurationMinutes = 60
    @AppStorage(TodayMdPreferenceKey.calendarDefaultIdentifier) private var calendarDefaultIdentifier = ""
    @AppStorage(TodayMdPreferenceKey.calendarVisibleIdentifiers) private var calendarVisibleIdentifiersRaw = ""

    let task: TaskItem
    @Binding var isInteractingWithCalendar: Bool

    @State private var dayEvents: [TodayMdCalendarEventSummary] = []
    @State private var draftInterval: DateInterval?
    @State private var moveBaseline: DateInterval?
    @State private var resizeStartBaseline: DateInterval?
    @State private var resizeEndBaseline: DateInterval?
    @State private var pendingDeletionEvent: TodayMdCalendarEventSummary?
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

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

    private var calendar: Calendar {
        Calendar.current
    }

    private var displayDayStart: Date {
        calendar.date(bySettingHour: TaskCalendarTimelineStyle.dayStartHour, minute: 0, second: 0, of: Date()) ?? calendar.startOfDay(for: Date())
    }

    private var displayDayEnd: Date {
        calendar.date(bySettingHour: TaskCalendarTimelineStyle.dayEndHour, minute: 0, second: 0, of: Date()) ?? displayDayStart.addingTimeInterval(16 * 60 * 60)
    }

    private var timelineHeight: CGFloat {
        CGFloat(TaskCalendarTimelineStyle.dayEndHour - TaskCalendarTimelineStyle.dayStartHour) * TaskCalendarTimelineStyle.hourHeight
    }

    private var totalVisibleMinutes: Double {
        displayDayEnd.timeIntervalSince(displayDayStart) / 60
    }

    private var destinationTitle: String {
        calendarService.selectedDestinationCalendar(preferredIdentifier: preferredIdentifier)?.displayTitle ?? "No writable calendar"
    }

    private var visibleCalendarIdentifiers: Set<String> {
        TaskCalendarVisibilitySelection.resolvedIdentifiers(
            from: calendarVisibleIdentifiersRaw,
            availableCalendars: calendarService.calendars
        )
    }

    private var allDayEvents: [TodayMdCalendarEventSummary] {
        dayEvents.filter(\.isAllDay)
    }

    private var timedEvents: [TodayMdCalendarEventSummary] {
        dayEvents
            .filter { !$0.isAllDay }
            .filter { $0.endDate > displayDayStart && $0.startDate < displayDayEnd }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
    }

    private var selectedBlockSummary: String {
        guard let draftInterval else { return "No blocker selected" }

        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: draftInterval.start, to: draftInterval.end)
    }

    private var selectedBlockDurationText: String {
        guard let draftInterval else { return "" }
        let minutes = Int(draftInterval.duration / 60)
        return "\(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            guidance
            plannerContent
            messageContent
        }
        .onAppear {
            calendarService.refreshIfNeeded()
            isInteractingWithCalendar = false
        }
        .onDisappear {
            isInteractingWithCalendar = false
        }
        .onChange(of: task.id, initial: true) { _, _ in
            successMessage = nil
            errorMessage = nil
            syncCalendarState(resetDraft: true)
        }
        .onChange(of: calendarService.authorizationStatus) { _, _ in
            syncCalendarState(resetDraft: draftInterval == nil)
        }
        .onChange(of: calendarService.refreshRevision, initial: true) { _, _ in
            syncCalendarState(resetDraft: draftInterval == nil)
        }
        .onChange(of: calendarVisibleIdentifiersRaw, initial: true) { _, _ in
            reloadTodayEvents()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                Text(destinationTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if draftInterval != nil {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(selectedBlockSummary)
                        .font(.subheadline.weight(.semibold))
                    Text(selectedBlockDurationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var guidance: some View {
        Text("Double-click the day grid to drop the task block, drag it to move, resize it from the thicker top or bottom grips, and remove existing entries with the delete control.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var plannerContent: some View {
        if !calendarService.authorizationStatus.canReadEvents {
            VStack(alignment: .leading, spacing: 12) {
                Text(calendarAuthorizationMessage(for: "see availability and place a time block from this task."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(calendarService.authorizationStatus.resolutionActionTitle) {
                    calendarService.resolveAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        } else if calendarService.selectedDestinationCalendar(preferredIdentifier: preferredIdentifier) == nil {
            Text("No writable calendar is available yet. Add an account in Calendar or choose a writable calendar in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            controlRow

            if !allDayEvents.isEmpty {
                allDayEventSection
            }

            timelineSection
        }
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            if draftInterval != nil {
                Button("Clear Draft") {
                    clearDraft()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || isDeleting)
            }

            Spacer(minLength: 0)

            Button("Place Blocker") {
                saveDraftInterval()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isSaving || isDeleting || draftInterval == nil)
        }
    }

    private var allDayEventSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All-Day")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allDayEvents) { event in
                        allDayEventChip(event)
                    }
                }
            }
        }
    }

    private var timelineSection: some View {
        HStack(alignment: .top, spacing: 12) {
            hourLabelColumn
            timelineLane
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.12), lineWidth: 1)
        )
    }

    private var hourLabelColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(TaskCalendarTimelineStyle.dayStartHour..<TaskCalendarTimelineStyle.dayEndHour + 1, id: \.self) { hour in
                Text(hourLabel(for: hour))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: TaskCalendarTimelineStyle.hourHeight, alignment: .topTrailing)
            }
        }
        .frame(width: TaskCalendarTimelineStyle.hourLabelWidth)
    }

    private var timelineLane: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                timelineGrid

                ForEach(timedEvents) { event in
                    timedEventBlock(event, laneWidth: geometry.size.width)
                }

                if let draftInterval {
                    draftBlock(interval: draftInterval, laneWidth: geometry.size.width)
                }

                TaskCalendarTimelineInteractionLayer(
                    draftRect: draftFrame(laneWidth: geometry.size.width),
                    deleteTargets: deleteTargets(laneWidth: geometry.size.width),
                    resizeHandleHeight: TaskCalendarTimelineStyle.resizeHandleHeight,
                    onBackgroundClick: {
                        pendingDeletionEvent = nil
                    },
                    onDoubleClick: { yPosition in
                        placeDraftByDoubleClick(at: yPosition)
                    },
                    onDeleteTarget: { eventID in
                        requestDeletion(for: eventID)
                    },
                    onInteractionStart: { mode in
                        beginTimelineInteraction(mode)
                    },
                    onInteractionChange: { mode, translationHeight in
                        updateTimelineInteraction(mode, translationHeight: translationHeight)
                    },
                    onInteractionEnd: {
                        endTimelineInteraction()
                    }
                )
            }
        }
        .frame(height: timelineHeight)
    }

    private var timelineGrid: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))

            ForEach(0...(TaskCalendarTimelineStyle.dayEndHour - TaskCalendarTimelineStyle.dayStartHour) * 2, id: \.self) { tick in
                Rectangle()
                    .fill(tick.isMultiple(of: 2) ? Color.secondary.opacity(0.16) : Color.secondary.opacity(0.08))
                    .frame(height: tick.isMultiple(of: 2) ? 1 : 0.5)
                    .offset(y: CGFloat(tick) * (TaskCalendarTimelineStyle.hourHeight / 2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func allDayEventChip(_ event: TodayMdCalendarEventSummary) -> some View {
        HStack(spacing: 6) {
            Text(event.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if event.canDelete {
                Button {
                    requestDeletion(for: event)
                } label: {
                    deleteEntryBadge(size: 16, isArmed: isDeletionPending(for: event))
                }
                .buttonStyle(.plain)
                .help(isDeletionPending(for: event) ? "Delete calendar entry" : "Arm calendar entry deletion")
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Capsule())
        .onTapGesture {
            pendingDeletionEvent = nil
        }
        .background(
            Capsule()
                .fill(event.accentColor.opacity(0.14))
        )
        .overlay(
            Capsule()
                .stroke(event.accentColor.opacity(0.24), lineWidth: 1)
        )
    }

    private func timedEventBlock(_ event: TodayMdCalendarEventSummary, laneWidth: CGFloat) -> some View {
        let metrics = metrics(for: DateInterval(start: event.startDate, end: event.endDate))
        let density = cardDensity(for: metrics.height)
        let cornerRadius: CGFloat = density == .compact ? 12 : 14

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(density == .compact ? 1 : 2)
                    .truncationMode(.tail)

                if density != .compact {
                    Text(eventTimeText(event.startDate, event.endDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if density == .expanded {
                    Text(event.calendarTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(density == .compact ? 8 : 10)
            .padding(.trailing, event.canDelete ? deleteBadgeSize(for: density) + (TaskCalendarTimelineStyle.deleteBadgeInset * 1.5) : 0)

            if event.canDelete {
                deleteEntryBadge(
                    size: deleteBadgeSize(for: density),
                    isArmed: isDeletionPending(for: event)
                )
                    .padding(TaskCalendarTimelineStyle.deleteBadgeInset)
            }
        }
        .frame(width: laneWidth - 12, height: max(metrics.height, 34), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(event.accentColor.opacity(event.canDelete ? 0.20 : 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(event.accentColor.opacity(event.canDelete ? 0.34 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .offset(x: 6, y: metrics.y)
    }

    private func draftBlock(interval: DateInterval, laneWidth: CGFloat) -> some View {
        let metrics = metrics(for: interval)
        let density = cardDensity(for: metrics.height)
        let blockShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title.isEmpty ? "Focus Block" : task.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(density == .compact ? 1 : 2)
                    .truncationMode(.tail)

                if density != .compact {
                    Text(eventTimeText(interval.start, interval.end))
                        .font(.caption2)
                        .lineLimit(1)
                }

                if density == .expanded {
                    Text(selectedBlockDurationText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, density == .compact ? 10 : 12)
            .padding(.top, density == .compact ? 10 : 12)
        }
        .frame(width: laneWidth - 12, height: max(metrics.height, 44), alignment: .topLeading)
        .background(
            blockShape
                .fill(Color.orange.opacity(0.26))
        )
        .overlay(
            blockShape
                .stroke(Color.orange.opacity(0.44), lineWidth: 1.5)
        )
        .clipShape(blockShape)
        .overlay(alignment: .top) {
            resizeHandle()
                .offset(y: -TaskCalendarTimelineStyle.resizeHandleThickness / 2)
        }
        .overlay(alignment: .bottom) {
            resizeHandle()
                .offset(y: TaskCalendarTimelineStyle.resizeHandleThickness / 2)
        }
        .offset(x: 6, y: metrics.y)
        .contentShape(blockShape)
    }

    private func resizeHandle() -> some View {
        Capsule()
            .fill(Color.orange.opacity(0.96))
            .frame(
                width: TaskCalendarTimelineStyle.resizeHandleWidth,
                height: TaskCalendarTimelineStyle.resizeHandleThickness
            )
    }

    private func deleteEntryBadge(size: CGFloat, isArmed: Bool = false) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))

            Image(systemName: isArmed ? "checkmark" : "xmark")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(isArmed ? Color.red.opacity(0.88) : Color.secondary.opacity(0.72))
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke((isArmed ? Color.red : Color.secondary).opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var messageContent: some View {
        if let successMessage {
            Text(successMessage)
                .font(.caption)
                .foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let lastError = calendarService.lastError {
            Text(lastError)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func initializeDraft(force: Bool) {
        guard calendarService.authorizationStatus.canReadEvents else {
            if force {
                draftInterval = nil
            }
            return
        }

        guard force || draftInterval == nil else { return }

        let busySlots = timedEvents.map {
            CalendarTimeBlocking.BusySlot(start: $0.startDate, end: $0.endDate)
        }
        let initialStart = max(Date(), displayDayStart)
        let nextFreeSlot = CalendarTimeBlocking.nextAvailableSlot(
            after: initialStart,
            durationMinutes: effectiveDefaultDuration,
            busySlots: busySlots,
            calendar: calendar,
            startHour: TaskCalendarTimelineStyle.dayStartHour,
            endHour: TaskCalendarTimelineStyle.dayEndHour,
            searchDays: 1,
            stepMinutes: TaskCalendarTimelineStyle.snapMinutes
        )

        if let nextFreeSlot, nextFreeSlot.start < displayDayEnd {
            draftInterval = DateInterval(start: max(nextFreeSlot.start, displayDayStart), end: min(nextFreeSlot.end, displayDayEnd))
            return
        }

        let fallbackStart = min(
            max(initialStart, calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? displayDayStart),
            displayDayEnd.addingTimeInterval(TimeInterval(-effectiveDefaultDuration * 60))
        )
        let snappedFallback = CalendarTimeBlocking.roundUp(fallbackStart, stepMinutes: TaskCalendarTimelineStyle.snapMinutes, calendar: calendar)
        let fallbackEnd = min(displayDayEnd, snappedFallback.addingTimeInterval(TimeInterval(effectiveDefaultDuration * 60)))
        draftInterval = DateInterval(start: snappedFallback, end: fallbackEnd)
    }

    private func placeDraftByDoubleClick(at yPosition: CGFloat) {
        pendingDeletionEvent = nil
        let durationMinutes = draftDurationMinutes
        let startDate = snappedDate(for: yPosition)
        draftInterval = clampedInterval(startingAt: startDate, durationMinutes: durationMinutes)
        successMessage = nil
        errorMessage = nil
    }

    private func beginTimelineInteraction(_ mode: TaskCalendarTimelineInteractionMode) {
        guard let draftInterval else { return }

        pendingDeletionEvent = nil
        successMessage = nil
        errorMessage = nil
        isInteractingWithCalendar = true

        switch mode {
        case .move:
            moveBaseline = draftInterval
            resizeStartBaseline = nil
            resizeEndBaseline = nil
        case .resizeStart:
            resizeStartBaseline = draftInterval
            moveBaseline = nil
            resizeEndBaseline = nil
        case .resizeEnd:
            resizeEndBaseline = draftInterval
            moveBaseline = nil
            resizeStartBaseline = nil
        }
    }

    private func updateTimelineInteraction(_ mode: TaskCalendarTimelineInteractionMode, translationHeight: CGFloat) {
        let minuteDelta = snappedMinuteOffset(for: translationHeight)

        switch mode {
        case .move:
            guard let baseline = moveBaseline else { return }
            updateMovedDraft(from: baseline, minuteDelta: minuteDelta)
        case .resizeStart:
            guard let baseline = resizeStartBaseline else { return }
            updateResizedDraftStart(from: baseline, minuteDelta: minuteDelta)
        case .resizeEnd:
            guard let baseline = resizeEndBaseline else { return }
            updateResizedDraftEnd(from: baseline, minuteDelta: minuteDelta)
        }
    }

    private func endTimelineInteraction() {
        moveBaseline = nil
        resizeStartBaseline = nil
        resizeEndBaseline = nil
        isInteractingWithCalendar = false
    }

    private func syncCalendarState(resetDraft: Bool) {
        reloadTodayEvents()
        initializeDraft(force: resetDraft)
    }

    private func reloadTodayEvents() {
        guard calendarService.authorizationStatus.canReadEvents else {
            dayEvents = []
            return
        }

        dayEvents = calendarService.eventsForDay(Date(), visibleCalendarIdentifiers: visibleCalendarIdentifiers)
    }

    private func saveDraftInterval() {
        guard let draftInterval else { return }
        createBlock(for: task, interval: draftInterval)
    }

    private func createBlock(for task: TaskItem, interval: DateInterval) {
        successMessage = nil
        errorMessage = nil
        isSaving = true

        Task { @MainActor in
            defer { isSaving = false }

            do {
                try calendarService.deleteManagedBlocks(forTaskIDs: [task.id])

                let result = try calendarService.createBlock(
                    for: task,
                    interval: interval,
                    preferredCalendarIdentifier: preferredIdentifier
                )

                if let taskID = result.taskID {
                    store.syncTaskBlockWithScheduledDate(id: taskID, scheduledDate: result.startDate, calendar: calendar)
                }
                self.draftInterval = DateInterval(start: result.startDate, end: result.endDate)
                successMessage = "Placed blocker in \(result.calendarTitle): \(eventTimeText(result.startDate, result.endDate))"
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func clearDraft() {
        draftInterval = nil
        successMessage = nil
        errorMessage = nil
    }

    private func requestDeletion(for eventID: String) {
        guard !isDeleting,
              let event = dayEvents.first(where: { $0.id == eventID }),
              event.canDelete else { return }

        requestDeletion(for: event)
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

    private func deleteEvent(_ event: TodayMdCalendarEventSummary) {
        guard let eventIdentifier = event.eventIdentifier else {
            errorMessage = "This calendar entry can’t be deleted from today-md."
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
                reloadTodayEvents()
                successMessage = "Deleted \(event.title)."
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func hourLabel(for hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var draftDurationMinutes: Int {
        guard let draftInterval else { return effectiveDefaultDuration }
        return max(Int(draftInterval.duration / 60), TaskCalendarTimelineStyle.minimumDurationMinutes)
    }

    private func draftFrame(laneWidth: CGFloat) -> CGRect? {
        guard let draftInterval else { return nil }
        let metrics = metrics(for: draftInterval)
        return CGRect(
            x: 6,
            y: metrics.y,
            width: max(laneWidth - 12, 0),
            height: max(metrics.height, 44)
        )
    }

    private func deleteTargets(laneWidth: CGFloat) -> [TaskCalendarTimelineDeleteTarget] {
        timedEvents.compactMap { event in
            guard let rect = deleteBadgeFrame(for: event, laneWidth: laneWidth) else {
                return nil
            }

            return TaskCalendarTimelineDeleteTarget(eventID: event.id, rect: rect)
        }
    }

    private func deleteBadgeFrame(for event: TodayMdCalendarEventSummary, laneWidth: CGFloat) -> CGRect? {
        guard event.canDelete else { return nil }

        let metrics = metrics(for: DateInterval(start: event.startDate, end: event.endDate))
        let density = cardDensity(for: metrics.height)
        let badgeSize = deleteBadgeSize(for: density)
        let cardFrame = CGRect(
            x: 6,
            y: metrics.y,
            width: max(laneWidth - 12, 0),
            height: max(metrics.height, 34)
        )

        return CGRect(
            x: cardFrame.maxX - badgeSize - TaskCalendarTimelineStyle.deleteBadgeInset,
            y: cardFrame.minY + TaskCalendarTimelineStyle.deleteBadgeInset,
            width: badgeSize,
            height: badgeSize
        )
    }

    private func metrics(for interval: DateInterval) -> (y: CGFloat, height: CGFloat) {
        let start = max(interval.start, displayDayStart)
        let end = min(interval.end, displayDayEnd)
        let startMinutes = start.timeIntervalSince(displayDayStart) / 60
        let endMinutes = end.timeIntervalSince(displayDayStart) / 60
        let y = CGFloat(startMinutes / totalVisibleMinutes) * timelineHeight
        let height = CGFloat((endMinutes - startMinutes) / totalVisibleMinutes) * timelineHeight
        return (y, max(height, 18))
    }

    private func snappedMinuteOffset(for translationHeight: CGFloat) -> Int {
        let rawMinutes = Double(translationHeight / timelineHeight) * totalVisibleMinutes
        let snapped = (rawMinutes / Double(TaskCalendarTimelineStyle.snapMinutes)).rounded() * Double(TaskCalendarTimelineStyle.snapMinutes)
        return Int(snapped)
    }

    private func snappedDate(for yPosition: CGFloat) -> Date {
        let clampedY = min(max(yPosition, 0), timelineHeight)
        let rawMinutes = Double(clampedY / timelineHeight) * totalVisibleMinutes
        let snappedMinutes = (rawMinutes / Double(TaskCalendarTimelineStyle.snapMinutes)).rounded() * Double(TaskCalendarTimelineStyle.snapMinutes)
        let minuteOffset = Int(snappedMinutes)
        return calendar.date(byAdding: .minute, value: minuteOffset, to: displayDayStart) ?? displayDayStart
    }

    private func clampedInterval(startingAt startDate: Date, durationMinutes: Int) -> DateInterval {
        let duration = TimeInterval(max(durationMinutes, TaskCalendarTimelineStyle.minimumDurationMinutes) * 60)
        var start = min(max(startDate, displayDayStart), displayDayEnd)
        var end = start.addingTimeInterval(duration)

        if end > displayDayEnd {
            end = displayDayEnd
            start = max(displayDayStart, end.addingTimeInterval(-duration))
        }

        if end <= start {
            end = min(displayDayEnd, start.addingTimeInterval(TimeInterval(TaskCalendarTimelineStyle.minimumDurationMinutes * 60)))
        }

        return DateInterval(start: start, end: end)
    }

    private func cardDensity(for height: CGFloat) -> TaskCalendarCardDensity {
        switch height {
        case ..<48:
            return .compact
        case ..<82:
            return .standard
        default:
            return .expanded
        }
    }

    private func deleteBadgeSize(for density: TaskCalendarCardDensity) -> CGFloat {
        switch density {
        case .compact:
            return TaskCalendarTimelineStyle.compactDeleteBadgeSize
        case .standard, .expanded:
            return TaskCalendarTimelineStyle.regularDeleteBadgeSize
        }
    }

    private func updateMovedDraft(from baseline: DateInterval, minuteDelta: Int) {
        let duration = baseline.duration
        var newStart = calendar.date(byAdding: .minute, value: minuteDelta, to: baseline.start) ?? baseline.start
        var newEnd = newStart.addingTimeInterval(duration)

        if newStart < displayDayStart {
            let correction = displayDayStart.timeIntervalSince(newStart)
            newStart = displayDayStart
            newEnd = newEnd.addingTimeInterval(correction)
        }

        if newEnd > displayDayEnd {
            let correction = newEnd.timeIntervalSince(displayDayEnd)
            newEnd = displayDayEnd
            newStart = newStart.addingTimeInterval(-correction)
        }

        draftInterval = DateInterval(start: newStart, end: newEnd)
    }

    private func updateResizedDraftStart(from baseline: DateInterval, minuteDelta: Int) {
        var newStart = calendar.date(byAdding: .minute, value: minuteDelta, to: baseline.start) ?? baseline.start
        let minimumEnd = baseline.end.addingTimeInterval(TimeInterval(-TaskCalendarTimelineStyle.minimumDurationMinutes * 60))
        newStart = min(max(newStart, displayDayStart), minimumEnd)
        draftInterval = DateInterval(start: newStart, end: baseline.end)
    }

    private func updateResizedDraftEnd(from baseline: DateInterval, minuteDelta: Int) {
        var newEnd = calendar.date(byAdding: .minute, value: minuteDelta, to: baseline.end) ?? baseline.end
        let minimumStart = baseline.start.addingTimeInterval(TimeInterval(TaskCalendarTimelineStyle.minimumDurationMinutes * 60))
        newEnd = max(min(newEnd, displayDayEnd), minimumStart)
        draftInterval = DateInterval(start: baseline.start, end: newEnd)
    }

    private func eventTimeText(_ start: Date, _ end: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: start, to: end)
    }
}

private struct TaskCalendarTimelineInteractionLayer: NSViewRepresentable {
    let draftRect: CGRect?
    let deleteTargets: [TaskCalendarTimelineDeleteTarget]
    let resizeHandleHeight: CGFloat
    let onBackgroundClick: () -> Void
    let onDoubleClick: (CGFloat) -> Void
    let onDeleteTarget: (String) -> Void
    let onInteractionStart: (TaskCalendarTimelineInteractionMode) -> Void
    let onInteractionChange: (TaskCalendarTimelineInteractionMode, CGFloat) -> Void
    let onInteractionEnd: () -> Void

    func makeNSView(context: Context) -> TimelineInteractionNSView {
        let view = TimelineInteractionNSView()
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: TimelineInteractionNSView, context: Context) {
        nsView.draftRect = draftRect
        nsView.deleteTargets = deleteTargets
        nsView.resizeHandleHeight = resizeHandleHeight
        nsView.onBackgroundClick = onBackgroundClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onDeleteTarget = onDeleteTarget
        nsView.onInteractionStart = onInteractionStart
        nsView.onInteractionChange = onInteractionChange
        nsView.onInteractionEnd = onInteractionEnd
    }
}

private final class TimelineInteractionNSView: NSView {
    var draftRect: CGRect?
    var deleteTargets: [TaskCalendarTimelineDeleteTarget] = []
    var resizeHandleHeight: CGFloat = 22
    var onBackgroundClick: (() -> Void)?
    var onDoubleClick: ((CGFloat) -> Void)?
    var onDeleteTarget: ((String) -> Void)?
    var onInteractionStart: ((TaskCalendarTimelineInteractionMode) -> Void)?
    var onInteractionChange: ((TaskCalendarTimelineInteractionMode, CGFloat) -> Void)?
    var onInteractionEnd: (() -> Void)?

    private var activeMode: TaskCalendarTimelineInteractionMode?
    private var dragStartPoint: CGPoint = .zero

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let deleteTarget = deleteTargets.first(where: { $0.rect.contains(point) }) {
            onDeleteTarget?(deleteTarget.eventID)
            return
        }

        if event.clickCount >= 2 {
            onDoubleClick?(point.y)
            return
        }

        guard let mode = interactionMode(for: point) else {
            onBackgroundClick?()
            return
        }

        activeMode = mode
        dragStartPoint = point
        onInteractionStart?(mode)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        onInteractionChange?(activeMode, point.y - dragStartPoint.y)
    }

    override func mouseUp(with event: NSEvent) {
        guard activeMode != nil else { return }
        activeMode = nil
        onInteractionEnd?()
    }

    private func interactionMode(for point: CGPoint) -> TaskCalendarTimelineInteractionMode? {
        guard let draftRect, draftRect.contains(point) else {
            return nil
        }

        if point.y <= draftRect.minY + resizeHandleHeight {
            return .resizeStart
        }

        if point.y >= draftRect.maxY - resizeHandleHeight {
            return .resizeEnd
        }

        return .move
    }
}

private enum WeekCalendarPanelStyle {
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

private enum WeekCalendarEventLayout {
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
                try calendarService.deleteManagedBlocks(forTaskIDs: [task.id])

                let result = try calendarService.createBlock(
                    for: task,
                    interval: interval,
                    preferredCalendarIdentifier: preferredIdentifier
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

private struct WeekCalendarCanvasView: NSViewRepresentable {
    let days: [Date]
    let eventsByDay: [Date: [TodayMdCalendarEventSummary]]
    let timelineHeight: CGFloat
    let dayColumnWidth: CGFloat
    let defaultDurationMinutes: Int
    let isInteractionEnabled: Bool
    let selectedEventID: String?
    let pendingDeletionEventID: String?
    let onDropTask: (UUID, DateInterval) -> Bool
    let onSelectEvent: (TodayMdCalendarEventSummary?, CGRect?) -> Void
    let onDeleteEvent: (TodayMdCalendarEventSummary) -> Void
    let onMoveEvent: (TodayMdCalendarEventSummary, DateInterval) -> Void

    func makeNSView(context: Context) -> WeekCalendarCanvasNSView {
        WeekCalendarCanvasNSView()
    }

    func updateNSView(_ nsView: WeekCalendarCanvasNSView, context: Context) {
        nsView.update(
            days: days,
            eventsByDay: eventsByDay,
            timelineHeight: timelineHeight,
            dayColumnWidth: dayColumnWidth,
            defaultDurationMinutes: defaultDurationMinutes,
            isInteractionEnabled: isInteractionEnabled,
            selectedEventID: selectedEventID,
            pendingDeletionEventID: pendingDeletionEventID,
            onDropTask: onDropTask,
            onSelectEvent: onSelectEvent,
            onDeleteEvent: onDeleteEvent,
            onMoveEvent: onMoveEvent
        )
    }
}

private struct WeekCalendarCanvasEventGeometry {
    let event: TodayMdCalendarEventSummary
    let frame: CGRect
    let deleteFrame: CGRect?
    let resizeStartFrame: CGRect?
    let resizeEndFrame: CGRect?
}

private struct WeekCalendarCanvasPreview {
    let title: String
    let interval: DateInterval
    let columnIndex: Int
}

private enum WeekCalendarCanvasInteractionMode {
    case move
    case resizeStart
    case resizeEnd
}

private struct WeekCalendarCanvasDragState {
    let event: TodayMdCalendarEventSummary
    let mode: WeekCalendarCanvasInteractionMode
    let frame: CGRect
    let originalInterval: DateInterval
    let initialPoint: CGPoint
    let verticalGrabOffset: CGFloat
    var preview: WeekCalendarCanvasPreview?
}

private final class WeekCalendarCanvasNSView: NSView {
    private let calendar = Calendar.current
    private let taskPasteboardType = NSPasteboard.PasteboardType(UTType.taskItem.identifier)

    private var days: [Date] = []
    private var eventsByDay: [Date: [TodayMdCalendarEventSummary]] = [:]
    private var timelineHeight: CGFloat = 0
    private var dayColumnWidth: CGFloat = WeekCalendarPanelStyle.minimumDayColumnWidth
    private var defaultDurationMinutes = 60
    private var isInteractionEnabled = true
    private var selectedEventID: String?
    private var pendingDeletionEventID: String?
    private var onDropTask: ((UUID, DateInterval) -> Bool)?
    private var onSelectEvent: ((TodayMdCalendarEventSummary?, CGRect?) -> Void)?
    private var onDeleteEvent: ((TodayMdCalendarEventSummary) -> Void)?
    private var onMoveEvent: ((TodayMdCalendarEventSummary, DateInterval) -> Void)?

    private var dayColumnFrames: [CGRect] = []
    private var eventGeometries: [WeekCalendarCanvasEventGeometry] = []
    private var activeDragState: WeekCalendarCanvasDragState?
    private var taskDropPreview: WeekCalendarCanvasPreview?
    private var pushedClosedHandCursor = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        registerForDraggedTypes([taskPasteboardType])
    }

    func update(
        days: [Date],
        eventsByDay: [Date: [TodayMdCalendarEventSummary]],
        timelineHeight: CGFloat,
        dayColumnWidth: CGFloat,
        defaultDurationMinutes: Int,
        isInteractionEnabled: Bool,
        selectedEventID: String?,
        pendingDeletionEventID: String?,
        onDropTask: @escaping (UUID, DateInterval) -> Bool,
        onSelectEvent: @escaping (TodayMdCalendarEventSummary?, CGRect?) -> Void,
        onDeleteEvent: @escaping (TodayMdCalendarEventSummary) -> Void,
        onMoveEvent: @escaping (TodayMdCalendarEventSummary, DateInterval) -> Void
    ) {
        self.days = days
        self.eventsByDay = eventsByDay
        self.timelineHeight = timelineHeight
        self.dayColumnWidth = dayColumnWidth
        self.defaultDurationMinutes = defaultDurationMinutes
        self.isInteractionEnabled = isInteractionEnabled
        self.selectedEventID = selectedEventID
        self.pendingDeletionEventID = pendingDeletionEventID
        self.onDropTask = onDropTask
        self.onSelectEvent = onSelectEvent
        self.onDeleteEvent = onDeleteEvent
        self.onMoveEvent = onMoveEvent
        rebuildLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildLayout()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, frame) in dayColumnFrames.enumerated() {
            drawDayColumn(frame, highlighted: taskDropPreview?.columnIndex == index)
        }

        let hiddenEventID = activeDragState?.preview != nil ? activeDragState?.event.id : nil
        for geometry in eventGeometries where geometry.event.id != hiddenEventID {
            drawEventCard(geometry)
        }

        if let preview = taskDropPreview {
            drawPreview(preview, alpha: 0.18)
        }

        if let preview = activeDragState?.preview {
            drawPreview(preview, alpha: 0.26)
        }
    }

    override func resetCursorRects() {
        discardCursorRects()

        guard isInteractionEnabled else { return }

        for geometry in eventGeometries {
            if geometry.event.canEdit {
                addCursorRect(geometry.frame, cursor: .openHand)
                if let resizeStartFrame = geometry.resizeStartFrame {
                    addCursorRect(resizeStartFrame, cursor: .resizeUpDown)
                }
                if let resizeEndFrame = geometry.resizeEndFrame {
                    addCursorRect(resizeEndFrame, cursor: .resizeUpDown)
                }
            }

            if let deleteFrame = geometry.deleteFrame, geometry.event.canDelete {
                addCursorRect(deleteFrame, cursor: .pointingHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        guard let geometry = eventGeometry(at: point) else {
            onSelectEvent?(nil, nil)
            return
        }

        guard isInteractionEnabled else { return }

        if let deleteFrame = geometry.deleteFrame,
           deleteFrame.contains(point),
           geometry.event.canDelete {
            onDeleteEvent?(geometry.event)
            return
        }

        guard geometry.event.canEdit else {
            onSelectEvent?(geometry.event, geometry.frame)
            return
        }

        let interactionMode = interactionMode(for: point, in: geometry)
        activeDragState = WeekCalendarCanvasDragState(
            event: geometry.event,
            mode: interactionMode,
            frame: geometry.frame,
            originalInterval: DateInterval(start: geometry.event.startDate, end: geometry.event.endDate),
            initialPoint: point,
            verticalGrabOffset: verticalGrabOffset(for: interactionMode, point: point, in: geometry.frame),
            preview: nil
        )

        NSCursor.closedHand.push()
        pushedClosedHandCursor = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled, var activeDragState else { return }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - activeDragState.initialPoint.x, point.y - activeDragState.initialPoint.y)
        guard distance >= 2 else { return }

        activeDragState.preview = preview(for: activeDragState, point: point)
        self.activeDragState = activeDragState
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activeDragState = nil
            needsDisplay = true

            if pushedClosedHandCursor {
                NSCursor.pop()
                pushedClosedHandCursor = false
            }
        }

        guard isInteractionEnabled,
              let activeDragState else {
            return
        }

        guard let preview = activeDragState.preview else {
            if activeDragState.mode == .move {
                onSelectEvent?(activeDragState.event, activeDragState.frame)
            }
            return
        }

        guard preview.interval.start != activeDragState.originalInterval.start
                || preview.interval.end != activeDragState.originalInterval.end else {
            return
        }

        onMoveEvent?(activeDragState.event, preview.interval)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isInteractionEnabled, decodeTaskTransfer(from: sender.draggingPasteboard) != nil else {
            clearTaskDropPreview()
            return []
        }

        updateTaskDropPreview(with: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isInteractionEnabled, decodeTaskTransfer(from: sender.draggingPasteboard) != nil else {
            clearTaskDropPreview()
            return []
        }

        updateTaskDropPreview(with: sender)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        clearTaskDropPreview()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isInteractionEnabled && decodeTaskTransfer(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { clearTaskDropPreview() }

        guard isInteractionEnabled,
              let transfer = decodeTaskTransfer(from: sender.draggingPasteboard),
              let preview = previewForDroppedTask(at: convert(sender.draggingLocation, from: nil)) else {
            return false
        }

        return onDropTask?(transfer.id, preview.interval) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        clearTaskDropPreview()
    }

    private func rebuildLayout() {
        dayColumnFrames = days.indices.map { index in
            CGRect(
                x: CGFloat(index) * (dayColumnWidth + WeekCalendarPanelStyle.dayColumnSpacing),
                y: 0,
                width: dayColumnWidth,
                height: timelineHeight
            )
        }

        var updatedGeometries: [WeekCalendarCanvasEventGeometry] = []
        for (index, day) in days.enumerated() {
            let dayKey = calendar.startOfDay(for: day)
            let events = eventsByDay[dayKey] ?? []
            let localFrames = WeekCalendarEventLayout.frames(
                for: events,
                on: dayKey,
                timelineHeight: timelineHeight,
                dayColumnWidth: dayColumnWidth,
                calendar: calendar
            )

            for event in events {
                guard let localFrame = localFrames[event.id] else { continue }

                let frame = localFrame.offsetBy(dx: dayColumnFrames[index].minX, dy: 0)
                let resizeFrames = event.canEdit ? resizeHandleFrames(for: frame) : nil
                let deleteFrame: CGRect?
                if event.canDelete {
                    deleteFrame = CGRect(
                        x: frame.maxX - WeekCalendarPanelStyle.deleteBadgeSize - WeekCalendarPanelStyle.deleteBadgeInset,
                        y: frame.minY + WeekCalendarPanelStyle.deleteBadgeInset,
                        width: WeekCalendarPanelStyle.deleteBadgeSize,
                        height: WeekCalendarPanelStyle.deleteBadgeSize
                    )
                } else {
                    deleteFrame = nil
                }

                updatedGeometries.append(
                    WeekCalendarCanvasEventGeometry(
                        event: event,
                        frame: frame,
                        deleteFrame: deleteFrame,
                        resizeStartFrame: resizeFrames?.start,
                        resizeEndFrame: resizeFrames?.end
                    )
                )
            }
        }

        eventGeometries = updatedGeometries
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func drawDayColumn(_ frame: CGRect, highlighted: Bool) {
        let backgroundColor = highlighted
            ? NSColor.systemOrange.withAlphaComponent(0.08)
            : NSColor.textBackgroundColor
        let borderColor = highlighted
            ? NSColor.systemOrange.withAlphaComponent(0.22)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.10)

        let path = NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18)
        backgroundColor.setFill()
        path.fill()

        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let tickCount = (WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * 2
        for tick in 0...tickCount {
            let y = frame.minY + (CGFloat(tick) * (WeekCalendarPanelStyle.hourHeight / 2))
            let lineRect = CGRect(x: frame.minX, y: y, width: frame.width, height: tick.isMultiple(of: 2) ? 1 : 0.5)
            let linePath = NSBezierPath(rect: lineRect)
            let color = tick.isMultiple(of: 2)
                ? NSColor.secondaryLabelColor.withAlphaComponent(0.16)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.08)
            color.setFill()
            linePath.fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawEventCard(_ geometry: WeekCalendarCanvasEventGeometry) {
        let isSelected = selectedEventID == geometry.event.id
        let baseColor = geometry.event.nsColor
        let fillColor = baseColor.withAlphaComponent(
            geometry.event.canEdit
                ? (isSelected ? 0.28 : 0.20)
                : (isSelected ? 0.18 : 0.14)
        )
        let strokeColor = baseColor.withAlphaComponent(isSelected ? 0.56 : (geometry.event.canEdit ? 0.36 : 0.24))

        drawCard(
            title: geometry.event.title,
            subtitle: timeText(for: DateInterval(start: geometry.event.startDate, end: geometry.event.endDate)),
            frame: geometry.frame,
            fillColor: fillColor,
            strokeColor: strokeColor,
            deleteFrame: geometry.deleteFrame,
            deleteBadgeArmed: pendingDeletionEventID == geometry.event.id,
            showsResizeHandles: geometry.event.canEdit,
            strokeWidth: isSelected ? 2 : 1
        )
    }

    private func drawPreview(_ preview: WeekCalendarCanvasPreview, alpha: CGFloat) {
        guard let frame = previewFrame(for: preview) else { return }

        drawCard(
            title: preview.title,
            subtitle: timeText(for: preview.interval),
            frame: frame,
            fillColor: NSColor.systemOrange.withAlphaComponent(alpha),
            strokeColor: NSColor.systemOrange.withAlphaComponent(0.38),
            deleteFrame: nil,
            deleteBadgeArmed: false,
            showsResizeHandles: false,
            strokeWidth: 1
        )
    }

    private func drawCard(
        title: String,
        subtitle: String,
        frame: CGRect,
        fillColor: NSColor,
        strokeColor: NSColor,
        deleteFrame: CGRect?,
        deleteBadgeArmed: Bool,
        showsResizeHandles: Bool,
        strokeWidth: CGFloat
    ) {
        let cornerRadius: CGFloat = 14
        let cardPath = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        cardPath.fill()

        strokeColor.setStroke()
        cardPath.lineWidth = strokeWidth
        cardPath.stroke()

        let contentInset: CGFloat = 8
        let trailingInset = deleteFrame == nil ? contentInset : deleteFrame!.width + WeekCalendarPanelStyle.deleteBadgeInset * 1.75
        let contentRect = CGRect(
            x: frame.minX + contentInset,
            y: frame.minY + contentInset,
            width: max(frame.width - contentInset - trailingInset, 24),
            height: max(frame.height - (contentInset * 2), 18)
        )

        let showSubtitle = frame.height >= 44 && frame.width >= 78
        let titleHeight = showSubtitle ? min(contentRect.height - 18, 30) : contentRect.height
        let titleRect = CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: max(titleHeight, 16))

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titleParagraph
        ]

        (title as NSString).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: titleAttributes
        )

        if showSubtitle {
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: titleParagraph
            ]
            let subtitleRect = CGRect(
                x: contentRect.minX,
                y: min(contentRect.maxY - 14, titleRect.maxY + 2),
                width: contentRect.width,
                height: 14
            )
            (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttributes)
        }

        if let deleteFrame {
            drawDeleteBadge(in: deleteFrame, isArmed: deleteBadgeArmed)
        }

        if showsResizeHandles {
            drawResizeHandles(in: frame, color: strokeColor)
        }
    }

    private func drawDeleteBadge(in frame: CGRect, isArmed: Bool) {
        let badgePath = NSBezierPath(ovalIn: frame)
        NSColor.white.withAlphaComponent(0.94).setFill()
        badgePath.fill()

        let iconInset = frame.width * 0.34
        let iconPath = NSBezierPath()
        if isArmed {
            iconPath.move(to: CGPoint(x: frame.minX + iconInset * 0.75, y: frame.midY + iconInset * 0.1))
            iconPath.line(to: CGPoint(x: frame.midX - iconInset * 0.1, y: frame.maxY - iconInset))
            iconPath.line(to: CGPoint(x: frame.maxX - iconInset * 0.7, y: frame.minY + iconInset * 0.8))
        } else {
            iconPath.move(to: CGPoint(x: frame.minX + iconInset, y: frame.minY + iconInset))
            iconPath.line(to: CGPoint(x: frame.maxX - iconInset, y: frame.maxY - iconInset))
            iconPath.move(to: CGPoint(x: frame.maxX - iconInset, y: frame.minY + iconInset))
            iconPath.line(to: CGPoint(x: frame.minX + iconInset, y: frame.maxY - iconInset))
        }
        iconPath.lineWidth = 1.8
        iconPath.lineCapStyle = .round
        iconPath.lineJoinStyle = .round
        (isArmed ? NSColor.systemRed : NSColor.secondaryLabelColor).withAlphaComponent(0.88).setStroke()
        iconPath.stroke()
    }

    private func drawResizeHandles(in frame: CGRect, color: NSColor) {
        let thickness = WeekCalendarPanelStyle.resizeHandleThickness
        guard frame.height >= (thickness * 2) + 10 else { return }

        let handleWidth = min(
            WeekCalendarPanelStyle.resizeHandleWidth,
            max(frame.width - 28, 18)
        )

        let x = frame.midX - (handleWidth / 2)
        let topFrame = CGRect(
            x: x,
            y: frame.minY + 2,
            width: handleWidth,
            height: thickness
        )
        let bottomFrame = CGRect(
            x: x,
            y: frame.maxY - thickness - 2,
            width: handleWidth,
            height: thickness
        )

        for handleFrame in [topFrame, bottomFrame] {
            let path = NSBezierPath(
                roundedRect: handleFrame,
                xRadius: thickness / 2,
                yRadius: thickness / 2
            )
            color.withAlphaComponent(0.9).setFill()
            path.fill()
        }
    }

    private func eventGeometry(at point: CGPoint) -> WeekCalendarCanvasEventGeometry? {
        eventGeometries.reversed().first { geometry in
            geometry.frame.contains(point) || geometry.deleteFrame?.contains(point) == true
        }
    }

    private func preview(for dragState: WeekCalendarCanvasDragState, point: CGPoint) -> WeekCalendarCanvasPreview {
        switch dragState.mode {
        case .move:
            return previewForMovedEvent(
                dragState.event,
                point: point,
                verticalGrabOffset: dragState.verticalGrabOffset
            )
        case .resizeStart:
            return previewForResizedEventStart(
                dragState.event,
                originalInterval: dragState.originalInterval,
                point: point,
                topGrabOffset: dragState.verticalGrabOffset
            )
        case .resizeEnd:
            return previewForResizedEventEnd(
                dragState.event,
                originalInterval: dragState.originalInterval,
                point: point,
                bottomGrabOffset: dragState.verticalGrabOffset
            )
        }
    }

    private func previewForMovedEvent(
        _ event: TodayMdCalendarEventSummary,
        point: CGPoint,
        verticalGrabOffset: CGFloat
    ) -> WeekCalendarCanvasPreview {
        let dayIndex = clampedColumnIndex(for: point.x)
        let day = days[dayIndex]
        let durationMinutes = max(
            Int(event.endDate.timeIntervalSince(event.startDate) / 60),
            WeekCalendarPanelStyle.minimumDurationMinutes
        )
        let topY = point.y - verticalGrabOffset
        let start = snappedDate(forTopY: topY, on: day)
        let interval = clampedInterval(startingAt: start, durationMinutes: durationMinutes, on: day)
        return WeekCalendarCanvasPreview(title: event.title, interval: interval, columnIndex: dayIndex)
    }

    private func previewForResizedEventStart(
        _ event: TodayMdCalendarEventSummary,
        originalInterval: DateInterval,
        point: CGPoint,
        topGrabOffset: CGFloat
    ) -> WeekCalendarCanvasPreview {
        let dayIndex = columnIndex(for: originalInterval.start) ?? clampedColumnIndex(for: point.x)
        let day = days[dayIndex]
        let proposedStart = snappedDate(forTopY: point.y - topGrabOffset, on: day)
        let minimumEnd = originalInterval.end.addingTimeInterval(
            TimeInterval(-WeekCalendarPanelStyle.minimumDurationMinutes * 60)
        )
        let clampedStart = min(max(proposedStart, displayDayStart(for: day)), minimumEnd)
        let interval = DateInterval(start: clampedStart, end: originalInterval.end)
        return WeekCalendarCanvasPreview(title: event.title, interval: interval, columnIndex: dayIndex)
    }

    private func previewForResizedEventEnd(
        _ event: TodayMdCalendarEventSummary,
        originalInterval: DateInterval,
        point: CGPoint,
        bottomGrabOffset: CGFloat
    ) -> WeekCalendarCanvasPreview {
        let dayIndex = columnIndex(for: originalInterval.start) ?? clampedColumnIndex(for: point.x)
        let day = days[dayIndex]
        let proposedEnd = snappedDate(forTopY: point.y + bottomGrabOffset, on: day)
        let minimumEnd = originalInterval.start.addingTimeInterval(
            TimeInterval(WeekCalendarPanelStyle.minimumDurationMinutes * 60)
        )
        let clampedEnd = max(min(proposedEnd, displayDayEnd(for: day)), minimumEnd)
        let interval = DateInterval(start: originalInterval.start, end: clampedEnd)
        return WeekCalendarCanvasPreview(title: event.title, interval: interval, columnIndex: dayIndex)
    }

    private func previewForDroppedTask(at point: CGPoint) -> WeekCalendarCanvasPreview? {
        guard !days.isEmpty else { return nil }

        let dayIndex = clampedColumnIndex(for: point.x)
        let day = days[dayIndex]
        let start = snappedDate(forTopY: point.y, on: day)
        let interval = clampedInterval(
            startingAt: start,
            durationMinutes: defaultDurationMinutes,
            on: day
        )
        return WeekCalendarCanvasPreview(title: "New Blocker", interval: interval, columnIndex: dayIndex)
    }

    private func previewFrame(for preview: WeekCalendarCanvasPreview) -> CGRect? {
        guard preview.columnIndex >= 0, preview.columnIndex < dayColumnFrames.count else {
            return nil
        }

        let columnFrame = dayColumnFrames[preview.columnIndex]
        let day = days[preview.columnIndex]
        let metrics = frameMetrics(for: preview.interval, on: day)

        return CGRect(
            x: columnFrame.minX + WeekCalendarPanelStyle.eventHorizontalInset,
            y: metrics.y,
            width: columnFrame.width - (WeekCalendarPanelStyle.eventHorizontalInset * 2),
            height: max(metrics.height, 34)
        )
    }

    private func updateTaskDropPreview(with sender: any NSDraggingInfo) {
        taskDropPreview = previewForDroppedTask(at: convert(sender.draggingLocation, from: nil))
        needsDisplay = true
    }

    private func clearTaskDropPreview() {
        taskDropPreview = nil
        needsDisplay = true
    }

    private func decodeTaskTransfer(from pasteboard: NSPasteboard) -> TaskItemTransfer? {
        if let data = pasteboard.data(forType: taskPasteboardType),
           let transfer = try? JSONDecoder().decode(TaskItemTransfer.self, from: data) {
            return transfer
        }

        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: taskPasteboardType),
               let transfer = try? JSONDecoder().decode(TaskItemTransfer.self, from: data) {
                return transfer
            }
        }

        return nil
    }

    private func clampedColumnIndex(for x: CGFloat) -> Int {
        let band = dayColumnWidth + WeekCalendarPanelStyle.dayColumnSpacing
        let rawIndex = Int((max(x, 0) / band).rounded(.down))
        return min(max(rawIndex, 0), max(days.count - 1, 0))
    }

    private func columnIndex(for date: Date) -> Int? {
        days.firstIndex { calendar.isDate($0, inSameDayAs: date) }
    }

    private func snappedDate(forTopY yPosition: CGFloat, on day: Date) -> Date {
        let clampedY = min(max(yPosition, 0), timelineHeight)
        let totalVisibleMinutes = Double(WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * 60
        let rawMinutes = Double(clampedY / max(timelineHeight, 1)) * totalVisibleMinutes
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

    private func frameMetrics(for interval: DateInterval, on day: Date) -> (y: CGFloat, height: CGFloat) {
        let dayStart = displayDayStart(for: day)
        let dayEnd = displayDayEnd(for: day)
        let totalVisibleMinutes = Double(WeekCalendarPanelStyle.dayEndHour - WeekCalendarPanelStyle.dayStartHour) * 60
        let start = max(interval.start, dayStart)
        let end = min(interval.end, dayEnd)
        let startMinutes = start.timeIntervalSince(dayStart) / 60
        let endMinutes = end.timeIntervalSince(dayStart) / 60
        let y = CGFloat(startMinutes / totalVisibleMinutes) * timelineHeight
        let height = CGFloat((endMinutes - startMinutes) / totalVisibleMinutes) * timelineHeight
        return (y, max(height, 18))
    }

    private func interactionMode(
        for point: CGPoint,
        in geometry: WeekCalendarCanvasEventGeometry
    ) -> WeekCalendarCanvasInteractionMode {
        if let resizeStartFrame = geometry.resizeStartFrame,
           resizeStartFrame.contains(point) {
            return .resizeStart
        }

        if let resizeEndFrame = geometry.resizeEndFrame,
           resizeEndFrame.contains(point) {
            return .resizeEnd
        }

        return .move
    }

    private func verticalGrabOffset(
        for mode: WeekCalendarCanvasInteractionMode,
        point: CGPoint,
        in frame: CGRect
    ) -> CGFloat {
        switch mode {
        case .move, .resizeStart:
            return point.y - frame.minY
        case .resizeEnd:
            return frame.maxY - point.y
        }
    }

    private func resizeHandleFrames(for frame: CGRect) -> (start: CGRect, end: CGRect) {
        let hitHeight = min(
            WeekCalendarPanelStyle.resizeHandleHitHeight,
            max((frame.height - 4) / 2, WeekCalendarPanelStyle.resizeHandleThickness)
        )

        return (
            start: CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: hitHeight
            ),
            end: CGRect(
                x: frame.minX,
                y: frame.maxY - hitHeight,
                width: frame.width,
                height: hitHeight
            )
        )
    }

    private func displayDayStart(for day: Date) -> Date {
        calendar.date(bySettingHour: WeekCalendarPanelStyle.dayStartHour, minute: 0, second: 0, of: day)
            ?? calendar.startOfDay(for: day)
    }

    private func displayDayEnd(for day: Date) -> Date {
        calendar.date(bySettingHour: WeekCalendarPanelStyle.dayEndHour, minute: 0, second: 0, of: day)
            ?? displayDayStart(for: day).addingTimeInterval(16 * 60 * 60)
    }

    private func timeText(for interval: DateInterval) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: interval.start, to: interval.end)
    }
}
