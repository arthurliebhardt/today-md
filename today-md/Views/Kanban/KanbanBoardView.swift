import SwiftUI

struct BoardView: View {
    let tasks: (TimeBlock) -> [TaskItem]
    @Binding var selectedTaskID: UUID?
    @Binding var selectedTaskIDs: Set<UUID>
    @Binding var focusedBlock: TimeBlock?
    let onSelect: (TaskItem, Bool) -> Void
    let onAdd: (String, TimeBlock) -> Void
    let onMove: (UUID, TimeBlock) -> Void
    let onMoveToDone: (UUID, TimeBlock) -> Void
    let onReorderInBlock: (UUID, TimeBlock, UUID?) -> Void
    let onDelete: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void

    @State private var backlogCollapsed = false
    @State private var thisWeekCollapsed = false

    private var isFocusTodayActive: Bool {
        backlogCollapsed && thisWeekCollapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let shouldCollapse = !isFocusTodayActive
                        backlogCollapsed = shouldCollapse
                        thisWeekCollapsed = shouldCollapse
                    }
                } label: {
                    Label(
                        isFocusTodayActive ? "Show All Lanes" : "Focus Today",
                        systemImage: isFocusTodayActive ? "rectangle.3.group" : "line.3.horizontal.decrease.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFocusTodayActive ? .orange : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange.opacity(isFocusTodayActive ? 0.16 : 0.08)))
                }
                .buttonStyle(.plain)
                .help(isFocusTodayActive ? "Expand This Week and Backlog" : "Collapse This Week and Backlog")
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(TimeBlock.allCases) { block in
                    if block == .backlog || block == .thisWeek {
                        let isCollapsed = block == .backlog ? backlogCollapsed : thisWeekCollapsed
                        if isCollapsed {
                            collapsedLane(block: block) {
                                if block == .backlog { backlogCollapsed = false }
                                else { thisWeekCollapsed = false }
                            }
                        } else {
                            LaneView(
                                block: block,
                                tasks: tasks(block),
                                selectedTaskID: $selectedTaskID,
                                selectedTaskIDs: $selectedTaskIDs,
                                isFocused: focusedBlock == block,
                                onSelect: onSelect,
                                onAdd: { title in onAdd(title, block) },
                                onMove: onMove,
                                onMoveToDone: onMoveToDone,
                                onReorderActive: { draggedID, beforeID in
                                    onReorderInBlock(draggedID, block, beforeID)
                                },
                                onDelete: onDelete,
                                onToggle: onToggle,
                                onFocus: { focusedBlock = block },
                                onCollapse: {
                                    if block == .backlog { backlogCollapsed = true }
                                    else { thisWeekCollapsed = true }
                                }
                            )
                        }
                    } else {
                        LaneView(
                            block: block,
                            tasks: tasks(block),
                            selectedTaskID: $selectedTaskID,
                            selectedTaskIDs: $selectedTaskIDs,
                            isFocused: focusedBlock == block,
                            onSelect: onSelect,
                            onAdd: { title in onAdd(title, block) },
                            onMove: onMove,
                            onMoveToDone: onMoveToDone,
                            onReorderActive: { draggedID, beforeID in
                                onReorderInBlock(draggedID, block, beforeID)
                            },
                            onDelete: onDelete,
                            onToggle: onToggle,
                            onFocus: { focusedBlock = block }
                        )
                    }
                }
            }
        }
        .padding()
    }

    private func collapsedLane(block: TimeBlock, expand: @escaping () -> Void) -> some View {
        let activeCount = tasks(block).filter { !$0.isDone }.count
        let color: Color = block == .thisWeek ? .blue : .secondary
        return VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expand() }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: block.icon)
                        .foregroundStyle(color)
                    Text("\(activeCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.3)))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(width: 36)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .dropDestination(for: TaskItemTransfer.self) { items, _ in
            for item in items { onMove(item.id, block) }
            return !items.isEmpty
        } isTargeted: { _ in }
    }
}

struct LaneView: View {
    let block: TimeBlock
    let tasks: [TaskItem]
    @Binding var selectedTaskID: UUID?
    @Binding var selectedTaskIDs: Set<UUID>
    let isFocused: Bool
    let onSelect: (TaskItem, Bool) -> Void
    let onAdd: (String) -> Void
    let onMove: (UUID, TimeBlock) -> Void
    let onMoveToDone: (UUID, TimeBlock) -> Void
    let onReorderActive: (UUID, UUID?) -> Void
    let onDelete: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void
    let onFocus: () -> Void
    var onCollapse: (() -> Void)? = nil

    @State private var isTargeted = false
    @State private var isAdding = false
    @State private var newTitle = ""
    @State private var currentDropTarget: ReorderTarget?
    @State private var isDoneSectionTargeted = false
    @State private var isDoneSectionExpanded = false
    @FocusState private var isNewTaskFieldFocused: Bool

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isDone } }
    private var doneTasks: [TaskItem] { tasks.filter { $0.isDone } }

    private enum ReorderTarget: Hashable {
        case before(UUID)
        case after(UUID)
        case end
    }

    private var isTodayLane: Bool {
        block == .today
    }

    private var accentColor: Color {
        switch block {
        case .today:
            return .orange
        case .thisWeek:
            return .blue
        case .backlog:
            return .secondary
        }
    }

    private var laneBackgroundColor: Color {
        if isTargeted {
            return accentColor.opacity(isTodayLane ? 0.14 : 0.08)
        }

        if isTodayLane {
            return accentColor.opacity(0.06)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var laneBorderColor: Color {
        if isFocused {
            return accentColor.opacity(isTodayLane ? 0.7 : 0.45)
        }

        if isTodayLane {
            return accentColor.opacity(0.35)
        }

        return Color(nsColor: .separatorColor).opacity(0.18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(activeTasks) { task in
                        TaskCardView(
                            task: task,
                            isSelected: selectedTaskIDs.contains(task.id),
                            onToggle: { onToggle(task) },
                            onMove: { targetBlock in onMove(task.id, targetBlock) },
                            onDelete: { onDelete(task) }
                        )
                        .gesture(taskTapGesture(for: task))
                        .draggable(TaskItemTransfer(id: task.id))
                        .overlay {
                            if currentDropTarget == .before(task.id) || currentDropTarget == .after(task.id) {
                                Rectangle()
                                    .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .dropDestination(for: TaskItemTransfer.self) { items, location in
                            let target: ReorderTarget = location.y > 40 ? .after(task.id) : .before(task.id)
                            return handleReorderDrop(items, target: target)
                        } isTargeted: { targeted in
                            updateDropTarget(targeted: targeted, target: .before(task.id))
                        }
                    }
                    reorderDropZone(target: .end, height: 48)
                    addCard
                    doneSection
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    onFocus()
                    dismissEmptyDraftIfNeeded()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onFocus()
                dismissEmptyDraftIfNeeded()
            }
        }
        .frame(minWidth: 210, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(laneBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(laneBorderColor, lineWidth: isFocused ? 2 : (isTodayLane ? 1.5 : 1))
        )
        .dropDestination(for: TaskItemTransfer.self) { items, _ in
            for item in items { onMove(item.id, block) }
            return !items.isEmpty
        } isTargeted: { targeted in
            guard isTargeted != targeted else { return }
            isTargeted = targeted
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: block.icon)
                    .foregroundStyle(accentColor)
                Text(block.label)
                    .font(.headline.weight(isTodayLane ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(accentColor.opacity(isTodayLane ? 0.18 : block == .thisWeek ? 0.10 : 0.08)))
            Spacer()
            Text("\(activeTasks.count)")
                .font(.caption)
                .foregroundStyle(isTodayLane ? accentColor : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isTodayLane ? accentColor.opacity(0.14) : Color(nsColor: .separatorColor).opacity(0.3))
                )
            if let onCollapse {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { onCollapse() }
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
            dismissEmptyDraftIfNeeded()
        }
        .background(alignment: .bottom) {
            Capsule()
                .fill(accentColor.opacity(isTodayLane ? 0.8 : block == .thisWeek ? 0.35 : 0.18))
                .frame(height: isTodayLane ? 4 : 2)
                .padding(.horizontal, 12)
        }
    }

    private var addCard: some View {
        Group {
            if isAdding {
                TextField("Task title…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isNewTaskFieldFocused)
                    .onSubmit { submitNew() }
                    .onExitCommand { cancelAdd() }
                    .onChange(of: isNewTaskFieldFocused) { _, isFocused in
                        if !isFocused {
                            handleBlur()
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    }
            } else {
                Button(action: startAdd) {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(height: 48)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDoneSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(doneTasks.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.14)))
                    Image(systemName: isDoneSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isDoneSectionExpanded {
                if doneTasks.isEmpty {
                    Text("Drop tasks here to mark them done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                        )
                } else {
                    ForEach(doneTasks) { task in
                        TaskCardView(
                            task: task,
                            isSelected: selectedTaskIDs.contains(task.id),
                            onToggle: { onToggle(task) },
                            onMove: { targetBlock in onMove(task.id, targetBlock) },
                            onDelete: { onDelete(task) }
                        )
                        .gesture(taskTapGesture(for: task))
                        .draggable(TaskItemTransfer(id: task.id))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isDoneSectionTargeted
                        ? Color.green.opacity(0.14)
                        : Color.green.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isDoneSectionTargeted
                        ? Color.green.opacity(0.45)
                        : Color.green.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .dropDestination(for: TaskItemTransfer.self) { items, _ in
            guard !items.isEmpty else { return false }
            for item in items {
                onMoveToDone(item.id, block)
            }
            return true
        } isTargeted: { targeted in
            isDoneSectionTargeted = targeted
        }
    }

    private func handleReorderDrop(_ items: [TaskItemTransfer], target: ReorderTarget) -> Bool {
        guard let draggedID = items.first?.id else { return false }
        let beforeID: UUID? = {
            switch target {
            case .before(let id):
                return id
            case .after(let id):
                return nextActiveTaskID(after: id)
            case .end:
                return nil
            }
        }()
        onReorderActive(draggedID, beforeID)
        currentDropTarget = nil
        return true
    }

    private func updateDropTarget(targeted: Bool, target: ReorderTarget) {
        if targeted {
            guard currentDropTarget != target else { return }
            currentDropTarget = target
        } else if currentDropTarget == target {
            currentDropTarget = nil
        }
    }

    private func reorderDropZone(target: ReorderTarget, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                currentDropTarget == target
                    ? Color.accentColor.opacity(0.8)
                    : Color(nsColor: .separatorColor).opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(currentDropTarget == target ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .frame(height: height)
            .contentShape(Rectangle())
            .dropDestination(for: TaskItemTransfer.self) { items, _ in
                handleReorderDrop(items, target: target)
            } isTargeted: { targeted in
                updateDropTarget(targeted: targeted, target: target)
            }
    }

    private func nextActiveTaskID(after id: UUID) -> UUID? {
        guard let currentIndex = activeTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let nextIndex = activeTasks.index(after: currentIndex)
        guard nextIndex < activeTasks.endIndex else { return nil }
        return activeTasks[nextIndex].id
    }

    private func submitNew() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        onAdd(title)
        newTitle = ""
        isAdding = false
        isNewTaskFieldFocused = false
    }

    private func cancelAdd() {
        newTitle = ""
        isAdding = false
        isNewTaskFieldFocused = false
    }

    private func startAdd() {
        isAdding = true
        DispatchQueue.main.async {
            isNewTaskFieldFocused = true
        }
    }

    private func handleBlur() {
        dismissEmptyDraftIfNeeded()
    }

    private func dismissEmptyDraftIfNeeded() {
        guard newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cancelAdd()
    }

    private func taskTapGesture(for task: TaskItem) -> some Gesture {
        TapGesture()
            .modifiers(.shift)
            .onEnded {
                onFocus()
                onSelect(task, true)
                dismissEmptyDraftIfNeeded()
            }
            .exclusively(
                before: TapGesture().onEnded {
                    onFocus()
                    onSelect(task, false)
                    dismissEmptyDraftIfNeeded()
                }
            )
    }
}
