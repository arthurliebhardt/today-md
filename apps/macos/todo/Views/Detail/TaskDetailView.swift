import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    let onDelete: (TaskItem) -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                ChecklistSection(task: task)
                Divider()
                MarkdownEditorView(task: task)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    onDelete(task)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: { task.isDone.toggle() }) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.isDone ? .green : .secondary)
                }
                .buttonStyle(.plain)

                TextField("Task title", text: $task.title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
            }
            HStack(spacing: 12) {
                if let list = task.list {
                    Label(list.name, systemImage: list.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Created \(task.creationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

}
