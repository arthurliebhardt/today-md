import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    @Environment(\.modelContext) private var modelContext
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
        .onChange(of: task.title) { _, newValue in
            if newValue != draftTitle {
                draftTitle = newValue
            }
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
                .buttonStyle(.plain)

                TextField("Task title", text: $draftTitle)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onChange(of: draftTitle) { _, newValue in
                        performWithoutModelUndoRegistration {
                            task.title = newValue
                        }
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

    private func performWithoutModelUndoRegistration(_ update: () -> Void) {
        let undoManager = modelContext.undoManager
        let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled ?? false

        if wasUndoRegistrationEnabled {
            undoManager?.disableUndoRegistration()
        }

        update()

        if wasUndoRegistrationEnabled {
            undoManager?.enableUndoRegistration()
        }
    }
}
