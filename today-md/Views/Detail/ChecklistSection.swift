import SwiftUI

struct ChecklistSection: View {
    @Environment(TodayMdStore.self) private var store
    let task: TaskItem

    @State private var newItemTitle = ""
    @State private var isExpanded = true

    private var items: [MarkdownChecklistItem] { task.checklistItems }

    private var doneCount: Int { items.filter(\.isChecked).count }
    private var activeItems: [MarkdownChecklistItem] { items.filter { !$0.isChecked } }
    private var doneItems: [MarkdownChecklistItem] { items.filter { $0.isChecked } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text("Tasks")
                            .font(.subheadline.bold())
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if !items.isEmpty {
                    Text("\(doneCount)/\(items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                ForEach(activeItems) { item in
                    checkRow(item)
                }

                if !doneItems.isEmpty {
                    ForEach(doneItems) { item in
                        checkRow(item)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    TextField("Add task…", text: $newItemTitle)
                        .textFieldStyle(.plain)
                        .onSubmit { addItem() }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func checkRow(_ item: MarkdownChecklistItem) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggleChecklistItem(taskID: task.id, lineIndex: item.lineIndex)
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .strikethrough(item.isChecked)
                .foregroundStyle(item.isChecked ? .secondary : .primary)

            Spacer()

            Button {
                store.removeChecklistItem(taskID: task.id, lineIndex: item.lineIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.vertical, 2)
    }

    private func addItem() {
        store.addChecklistItem(taskID: task.id, title: newItemTitle)
        newItemTitle = ""
    }
}
