import SwiftUI

struct BoardView: View {
    let tasks: (TimeBlock) -> [TaskItem]
    @Binding var selectedTask: TaskItem?
    let onAdd: (String, TimeBlock) -> Void
    let onMove: (UUID, TimeBlock) -> Void
    let onReorderInBlock: (UUID, TimeBlock, UUID?) -> Void
    let onDelete: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void

    @State private var backlogCollapsed = false
    @State private var thisWeekCollapsed = false

    var body: some View {
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
                            selectedTask: $selectedTask,
                            onAdd: { title in onAdd(title, block) },
                            onDrop: { id in onMove(id, block) },
                            onReorderActive: { draggedID, beforeID in
                                onReorderInBlock(draggedID, block, beforeID)
                            },
                            onDelete: onDelete,
                            onToggle: onToggle,
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
                        selectedTask: $selectedTask,
                        onAdd: { title in onAdd(title, block) },
                        onDrop: { id in onMove(id, block) },
                        onReorderActive: { draggedID, beforeID in
                            onReorderInBlock(draggedID, block, beforeID)
                        },
                        onDelete: onDelete,
                        onToggle: onToggle
                    )
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
    @Binding var selectedTask: TaskItem?
    let onAdd: (String) -> Void
    let onDrop: (UUID) -> Void
    let onReorderActive: (UUID, UUID?) -> Void
    let onDelete: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void
    var onCollapse: (() -> Void)? = nil

    @State private var isTargeted = false
    @State private var isAdding = false
    @State private var newTitle = ""
    @State private var currentDropTarget: ReorderTarget?

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isDone } }
    private var doneTasks: [TaskItem] { tasks.filter { $0.isDone } }

    private enum ReorderTarget: Hashable {
        case before(UUID)
        case after(UUID)
        case end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(activeTasks) { task in
                        TaskCardView(task: task, isSelected: selectedTask == task, onToggle: { onToggle(task) }, onDelete: { onDelete(task) })
                            .onTapGesture { selectedTask = task }
                            .draggable(TaskItemTransfer(id: task.id))
                            .overlay {
                                if currentDropTarget == .before(task.id) || currentDropTarget == .after(task.id) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                                }
                            }
                            .contentShape(Rectangle())
                            .dropDestination(for: TaskItemTransfer.self) { items, location in
                                let target: ReorderTarget = location.y > 40
                                    ? .after(task.id)
                                    : .before(task.id)
                                return handleReorderDrop(items, target: target)
                            } isTargeted: { targeted in
                                updateDropTarget(targeted: targeted, target: .before(task.id))
                            }
                    }
                    reorderDropZone(target: .end, height: 48)
                    addCard
                    if !doneTasks.isEmpty {
                        doneSection
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 160, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .dropDestination(for: TaskItemTransfer.self) { items, _ in
            for item in items { onDrop(item.id) }
            return !items.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: block.icon)
                .foregroundStyle(block == .today ? .orange : block == .thisWeek ? .blue : .secondary)
            Text(block.label)
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
            Spacer()
            Text("\(activeTasks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.3)))
            if let onCollapse = onCollapse {
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
        .padding(.bottom, 4)
    }

    private var addCard: some View {
        Group {
            if isAdding {
                TextField("Task title…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { submitNew() }
                    .onExitCommand { cancelAdd() }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    }
            } else {
                Button(action: { isAdding = true }) {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(height: 48)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var doneSection: some View {
        DisclosureGroup("Done (\(doneTasks.count))") {
            ForEach(doneTasks) { task in
                TaskCardView(task: task, isSelected: selectedTask == task, onToggle: { onToggle(task) }, onDelete: { onDelete(task) })
                    .onTapGesture { selectedTask = task }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
    }

    private func cancelAdd() {
        newTitle = ""
        isAdding = false
    }
}
