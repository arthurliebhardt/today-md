import SwiftUI

struct TaskDetailView: View {
    @Environment(TodayMdStore.self) private var store

    let task: TaskItem
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void

    @State private var draftTitle = ""

    var body: some View {
        let searchQuery = SearchPresentationQuery(store.searchText)

        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection(searchQuery: searchQuery)
                    Divider()
                    ChecklistSection(task: task)
                    Divider()
                    MarkdownEditorView(task: task)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: max(proxy.size.height - 32, 0),
                    alignment: .topLeading
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            draftTitle = task.title
        }
        .onChange(of: task.id, initial: true) { _, _ in
            draftTitle = task.title
        }
    }

    private func headerSection(searchQuery: SearchPresentationQuery) -> some View {
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

                Button(role: .destructive) {
                    onDelete(task)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            if searchQuery.containsMatch(in: task.title) {
                Text(searchQuery.highlightedText(for: task.title.isEmpty ? "Untitled" : task.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TaskListBadgePicker(task: task)

                Text("Created \(task.creationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
