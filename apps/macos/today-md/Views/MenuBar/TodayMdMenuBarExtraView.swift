import AppKit
import SwiftUI

private enum MenuBarPalette {
    static let paper = Color(red: 240 / 255, green: 237 / 255, blue: 232 / 255)
    static let ink = Color(red: 28 / 255, green: 25 / 255, blue: 23 / 255)
    static let accent = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    static let accentSoft = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
}

enum TodayMdMenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let boxRect = NSRect(x: 1.5, y: 1.5, width: 15, height: 15)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 4.8, yRadius: 4.8)
        NSColor(calibratedRed: 217 / 255, green: 119 / 255, blue: 6 / 255, alpha: 1).setFill()
        boxPath.fill()

        let checkPath = NSBezierPath()
        checkPath.lineWidth = 2.1
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.move(to: NSPoint(x: 5.0, y: 8.8))
        checkPath.line(to: NSPoint(x: 7.6, y: 5.8))
        checkPath.line(to: NSPoint(x: 13.1, y: 12.5))
        NSColor.white.setStroke()
        checkPath.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }()
}

private struct TodayMdCheckboxMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MenuBarPalette.accent)

            Path { path in
                path.move(to: CGPoint(x: 9, y: 16))
                path.addLine(to: CGPoint(x: 14, y: 21))
                path.addLine(to: CGPoint(x: 24, y: 9))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 32, height: 32)
    }
}

struct TodayMdMenuBarExtraView: View {
    @Environment(TodayMdStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var presentationState: AppPresentationState
    @EnvironmentObject private var syncService: TodayMdSyncService
    @FocusState private var isQuickAddFieldFocused: Bool
    @State private var draftTitle = ""
    @State private var selectedQuickAddListID: UUID?

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var todayTasks: [TaskItem] {
        store.allTasks.filter { $0.block == .today && !$0.isDone }
    }

    private var visibleTodayTasks: [TaskItem] {
        Array(todayTasks.prefix(6))
    }

    private var hiddenTodayTaskCount: Int {
        max(todayTasks.count - visibleTodayTasks.count, 0)
    }

    private var trimmedDraftTitle: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedLists: [TaskList] {
        store.lists.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedQuickAddList: TaskList? {
        guard let selectedQuickAddListID else { return nil }
        return sortedLists.first { $0.id == selectedQuickAddListID }
    }

    private var quickAddListLabel: String {
        selectedQuickAddList?.name ?? "Unassigned"
    }

    private var quickAddListIcon: String {
        selectedQuickAddList?.icon ?? "tray"
    }

    private var quickAddListColor: Color {
        selectedQuickAddList?.listColor.color ?? .secondary
    }

    private var syncSummary: String {
        switch syncService.status {
        case .disabled:
            return "Local-only"
        case .syncing:
            return "Updating now"
        case .conflict:
            return "Needs attention"
        case .error:
            return syncService.lastError ?? "Sync error"
        case .idle:
            if let lastSyncAt = syncService.lastSyncAt {
                return "Updated \(relativeDateFormatter.localizedString(for: lastSyncAt, relativeTo: Date()))"
            }
            return "Ready"
        }
    }

    private var syncTint: Color {
        switch syncService.status {
        case .disabled:
            return .secondary
        case .syncing:
            return .blue
        case .conflict:
            return .orange
        case .error:
            return .red
        case .idle:
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            todayAgenda
            bottomAction
        }
        .padding(18)
        .frame(width: 336)
        .background(
            LinearGradient(
                colors: [
                    MenuBarPalette.paper,
                    MenuBarPalette.paper.opacity(0.96),
                    Color.white.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            DispatchQueue.main.async {
                isQuickAddFieldFocused = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MenuBarPalette.accent.opacity(0.18),
                                    MenuBarPalette.accentSoft.opacity(0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    TodayMdCheckboxMark()
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 6) {
                    Text("today-md")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(MenuBarPalette.ink)

                    Text("Today’s focus from the menu bar.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(syncTint)
                            .frame(width: 8, height: 8)

                        Text(syncService.statusLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(MenuBarPalette.ink)
                    }
                }
            }

            Text(syncSummary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var todayAgenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            quickAddRow

            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MenuBarPalette.ink)

                Spacer()

                Text(todayTasks.count == 1 ? "1 task" : "\(todayTasks.count) tasks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Group {
                if visibleTodayTasks.isEmpty {
                    emptyTodayState
                } else {
                    VStack(spacing: 8) {
                        ForEach(visibleTodayTasks) { task in
                            todayTaskButton(task)
                        }

                        if hiddenTodayTaskCount > 0 {
                            Text("+\(hiddenTodayTaskCount) more in the workspace")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(MenuBarPalette.accent.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var quickAddRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MenuBarPalette.accent)

                TextField("Add a task to Today", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isQuickAddFieldFocused)
                    .onSubmit(submitQuickAdd)

                Button(action: submitQuickAdd) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(trimmedDraftTitle.isEmpty ? MenuBarPalette.ink.opacity(0.25) : MenuBarPalette.ink)
                        )
                }
                .buttonStyle(.plain)
                .disabled(trimmedDraftTitle.isEmpty)
                .help("Add task to Today")
            }

            Menu {
                Button {
                    selectedQuickAddListID = nil
                } label: {
                    quickAddListMenuItem(
                        title: "Unassigned",
                        icon: "tray",
                        color: .secondary,
                        isSelected: selectedQuickAddList == nil
                    )
                }

                if !sortedLists.isEmpty {
                    Divider()
                }

                ForEach(sortedLists) { list in
                    Button {
                        selectedQuickAddListID = list.id
                    } label: {
                        quickAddListMenuItem(
                            title: list.name,
                            icon: list.icon,
                            color: list.listColor.color,
                            isSelected: selectedQuickAddList?.id == list.id
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: quickAddListIcon)
                        .font(.system(size: 11, weight: .semibold))

                    Text(quickAddListLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(quickAddListColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(quickAddListColor.opacity(0.14))
                )
            }
            .menuStyle(.borderlessButton)
            .padding(.leading, 25)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MenuBarPalette.accent.opacity(0.10), lineWidth: 1)
        )
    }

    private var emptyTodayState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No tasks scheduled for today.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MenuBarPalette.ink)

            Text("Add something above or open the workspace to pull work forward from This Week or Backlog.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func todayTaskButton(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                markTaskDone(task.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MenuBarPalette.accent.opacity(0.08))

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(MenuBarPalette.accent, lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark done")

            Button {
                openTask(task.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(MenuBarPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let list = task.list {
                        Text(list.name.uppercased())
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MenuBarPalette.accent.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(MenuBarPalette.accent.opacity(0.10))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var bottomAction: some View {
        Button(action: openWorkspace) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 12, weight: .semibold))
                Text("Open Workspace")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MenuBarPalette.ink)
            )
        }
        .buttonStyle(.plain)
    }

    private func openWorkspace() {
        openWindow(id: TodayMdSceneID.mainWindow)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openTask(_ taskID: UUID) {
        presentationState.openTask(taskID)
        openWorkspace()
    }

    private func markTaskDone(_ taskID: UUID) {
        store.setTaskCompletion(id: taskID, isDone: true)
    }

    private func submitQuickAdd() {
        guard store.quickAddTask(title: draftTitle, to: .today, listID: selectedQuickAddList?.id) != nil else { return }
        draftTitle = ""
        isQuickAddFieldFocused = true
    }

    private func quickAddListMenuItem(
        title: String,
        icon: String,
        color: Color,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(color)

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
    }
}
