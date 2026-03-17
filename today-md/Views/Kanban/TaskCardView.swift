import SwiftUI

struct TaskCardView: View {
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

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(listColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.isDone ? .green : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "New task" : task.title)
                        .font(.body)
                        .lineLimit(2)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)

                    HStack(spacing: 6) {
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
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
