import SwiftUI

struct TaskDetailView: View {
    @Environment(TodayMdStore.self) private var store

    let task: TaskItem
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void

    @State private var draftTitle = ""

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
        .onAppear {
            draftTitle = task.title
        }
        .onChange(of: task.id, initial: true) { _, _ in
            draftTitle = task.title
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
                Button(action: { onToggle(task) }) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.isDone ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .focusEffectDisabled()

                TextField("Task title", text: $draftTitle)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onChange(of: draftTitle) { _, newValue in
                        store.updateTaskTitle(id: task.id, title: newValue)
                    }
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
