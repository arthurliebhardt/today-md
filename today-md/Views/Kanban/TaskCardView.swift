import SwiftUI

struct TaskListBadgePicker: View {
    @Environment(TodayMdStore.self) private var store

    let task: TaskItem

    @State private var isPickerPresented = false

    private var listColor: Color {
        task.list?.listColor.color ?? .secondary
    }

    private var listLabel: String {
        task.list?.name ?? "Unassigned"
    }

    private var listIcon: String {
        task.list?.icon ?? "tray"
    }

    private var sortedLists: [TaskList] {
        store.lists.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Button {
            guard !sortedLists.isEmpty else { return }
            isPickerPresented = true
        } label: {
            labelChip
        }
        .buttonStyle(.plain)
        .disabled(sortedLists.isEmpty)
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            pickerContent
        }
    }

    private var labelChip: some View {
        HStack(spacing: 4) {
            Image(systemName: listIcon)
                .font(.caption2)
            Text(listLabel)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(listColor.opacity(0.18)))
        .foregroundStyle(listColor)
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            pickerRow(
                title: "Unassigned",
                icon: "tray",
                color: .secondary,
                isSelected: task.list == nil,
                action: { assignTask(to: nil) }
            )

            Divider()
                .padding(.vertical, 2)

            ForEach(sortedLists) { list in
                pickerRow(
                    title: list.name,
                    icon: list.icon,
                    color: list.listColor.color,
                    isSelected: task.list?.id == list.id,
                    action: { assignTask(to: list.id) }
                )
            }
        }
        .padding(10)
        .frame(minWidth: 180, alignment: .leading)
    }

    private func pickerRow(
        title: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? color.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func assignTask(to listID: UUID?) {
        store.assignTask(id: task.id, toListID: listID)
        isPickerPresented = false
    }
}

struct TaskCardView: View {
    @Environment(TodayMdStore.self) private var store

    let task: TaskItem
    var isSelected: Bool = false
    var showsListBadge: Bool = false
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
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(task.isDone ? .green : listColor)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill((task.isDone ? Color.green : listColor).opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(searchQuery.highlightedText(for: task.title.isEmpty ? "New task" : task.title))
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

                    HStack(spacing: 6) {
                        if showsListBadge {
                            TaskListBadgePicker(task: task)
                        }
                        if metadata.checkboxTotal > 0 {
                            HStack(spacing: 2) {
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
            }
            .padding(10)
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
            ForEach(TimeBlock.allCases) { b in
                if b != task.block {
                    Button("Move to \(b.label)") { onMove(b) }
                }
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
