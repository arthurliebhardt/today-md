import SwiftUI

struct AllTasksView: View {
    let tasks: [TaskItem]
    @Binding var selectedTaskID: UUID?
    @Binding var selectedTaskIDs: Set<UUID>
    @Binding var doneSectionExpanded: Bool
    let onSelect: (TaskItem, Bool) -> Void
    let onMove: (UUID, TimeBlock) -> Void
    let onMarkDone: (UUID) -> Void
    let onDelete: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void
    let onReorderActive: (UUID, UUID?) -> Void

    @State private var currentDropTarget: ReorderTarget?
    @State private var isDoneSectionTargeted = false

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isDone } }
    private var doneTasks: [TaskItem] { tasks.filter { $0.isDone } }

    private enum ReorderTarget: Hashable {
        case before(UUID)
        case after(UUID)
        case end
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(activeTasks) { task in
                    AllTasksCardView(
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

                if !activeTasks.isEmpty {
                    reorderDropZone(target: .end, height: 52)
                }

                doneSection
            }
            .padding()
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

    private func nextActiveTaskID(after id: UUID) -> UUID? {
        guard let currentIndex = activeTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let nextIndex = activeTasks.index(after: currentIndex)
        guard nextIndex < activeTasks.endIndex else { return nil }
        return activeTasks[nextIndex].id
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

    private func taskTapGesture(for task: TaskItem) -> some Gesture {
        TapGesture()
            .modifiers(.shift)
            .onEnded {
                onSelect(task, true)
            }
            .exclusively(
                before: TapGesture().onEnded {
                    onSelect(task, false)
                }
            )
    }

    private var doneSection: some View {
        Group {
            if doneSectionExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: toggleDoneSection) {
                        doneSectionHeader
                    }
                    .buttonStyle(.plain)

                    if doneTasks.isEmpty {
                        Text("Drop tasks here to mark them done.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .allowsHitTesting(false)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                            )
                    } else {
                        ForEach(doneTasks) { task in
                            AllTasksCardView(
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
                .padding(12)
                .background {
                    Button(action: toggleDoneSection) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: toggleDoneSection) {
                    doneSectionHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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
        .padding(.top, 8)
        .dropDestination(for: TaskItemTransfer.self) { items, _ in
            guard !items.isEmpty else { return false }
            for item in items {
                onMarkDone(item.id)
            }
            return true
        } isTargeted: { targeted in
            isDoneSectionTargeted = targeted
        }
    }

    private var doneSectionHeader: some View {
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
            Image(systemName: doneSectionExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func toggleDoneSection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            doneSectionExpanded.toggle()
        }
    }
}

struct AllTasksCardView: View {
    @Environment(TodayMdStore.self) private var store

    let task: TaskItem
    var isSelected: Bool = false
    let onToggle: () -> Void
    let onMove: (TimeBlock) -> Void
    let onDelete: () -> Void

    private var listColor: Color {
        task.list?.listColor.color ?? .secondary
    }

    var body: some View {
        let metadata = task.cardMetadata
        let searchQuery = SearchPresentationQuery(store.searchText)
        let preview = searchQuery.preview(for: task)

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(listColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(task.isDone ? .green : listColor)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill((task.isDone ? Color.green : listColor).opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(searchQuery.highlightedText(for: task.title.isEmpty ? "Untitled" : task.title))
                        .font(.body)
                        .lineLimit(2)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)

                    if let preview {
                        Text(searchQuery.highlightedText(for: preview))
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if metadata.checkboxTotal > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "checklist")
                                    .font(.caption)
                                Text("\(metadata.checkboxDone)/\(metadata.checkboxTotal)")
                                    .font(.caption)
                            }
                            .foregroundStyle(.tertiary)
                        }
                        if metadata.hasNote {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        blockBadge(task.block)
                        TaskListBadgePicker(task: task)
                    }
                }
            }
            .padding(12)
        }
        .background {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(Rectangle())
        .overlay {
            if isSelected {
                Rectangle()
                    .strokeBorder(listColor.opacity(0.5), lineWidth: 1.5)
            }
        }
        .contextMenu {
            ForEach(TimeBlock.allCases) { block in
                if block != task.block {
                    Button("Move to \(block.label)") { onMove(block) }
                }
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func blockBadge(_ block: TimeBlock) -> some View {
        HStack(spacing: 3) {
            Image(systemName: block.icon)
                .font(.caption2)
            Text(block.label)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(blockColor(block).opacity(0.12)))
        .foregroundStyle(blockColor(block))
    }

    private func blockColor(_ block: TimeBlock) -> Color {
        switch block {
        case .today: return .orange
        case .thisWeek: return .blue
        case .backlog: return .secondary
        }
    }
}
