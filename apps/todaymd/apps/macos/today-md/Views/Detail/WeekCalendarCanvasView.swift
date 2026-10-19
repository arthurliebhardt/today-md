import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WeekCalendarCanvasView: NSViewRepresentable {
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

final class WeekCalendarCanvasNSView: NSView {
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
