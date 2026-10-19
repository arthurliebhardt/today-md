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
                let result = try calendarService.createBlock(
                    for: task,
                    interval: interval,
                    preferredCalendarIdentifier: preferredIdentifier,
                    replacingExistingManagedBlocks: true
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
