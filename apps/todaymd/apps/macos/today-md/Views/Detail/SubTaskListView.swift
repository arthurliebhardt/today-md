import SwiftUI

struct SubTaskListView: View {
    @Environment(TodayMdStore.self) private var store
    let task: TaskItem

    @State private var newSubtaskTitle = ""

    private var mappedSubtasks: [SubTask] {
        task.mappedSubtasks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subtasks")
                    .font(.subheadline.bold())
                Spacer()
                if !mappedSubtasks.isEmpty {
                    Text("\(task.mappedCompletedSubtaskCount)/\(mappedSubtasks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(mappedSubtasks) { subtask in
                subtaskRow(subtask)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                TextField("Add subtask...", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit { addSubtask() }
            }
            .padding(.vertical, 4)
        }
    }

    private func subtaskRow(_ subtask: SubTask) -> some View {
        HStack(spacing: 8) {
            Button(action: { store.toggleSubtask(taskID: task.id, subtaskID: subtask.id) }) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .strikethrough(subtask.isCompleted)
                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            Button(action: { store.deleteSubtask(taskID: task.id, subtaskID: subtask.id) }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.vertical, 2)
    }

    private func addSubtask() {
        store.addSubtask(taskID: task.id, title: newSubtaskTitle)
        newSubtaskTitle = ""
    }
}
