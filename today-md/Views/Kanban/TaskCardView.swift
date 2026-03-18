import SwiftUI

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

    private var listLabel: String {
        task.list?.name ?? "Unassigned"
    }

    private var listIcon: String {
        task.list?.icon ?? "tray"
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
                            HStack(spacing: 4) {
                                Image(systemName: listIcon)
                                    .font(.caption2)
                                Text(listLabel)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(listColor.opacity(0.12)))
                            .foregroundStyle(listColor)
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
