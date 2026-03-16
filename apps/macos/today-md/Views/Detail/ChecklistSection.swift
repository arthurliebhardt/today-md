import SwiftUI

struct ChecklistSection: View {
    @Environment(TodayMdStore.self) private var store
    let task: TaskItem

    @State private var newItemTitle = ""
    @State private var isExpanded = true

    private struct CheckItem: Identifiable {
        let id: Int
        let title: String
        let isChecked: Bool
    }

    private var items: [CheckItem] {
        guard let content = task.note?.content else { return [] }
        return content.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                return CheckItem(id: index, title: String(trimmed.dropFirst(6)), isChecked: true)
            } else if trimmed.hasPrefix("- [ ] ") {
                return CheckItem(id: index, title: String(trimmed.dropFirst(6)), isChecked: false)
            }
            return nil
        }
    }

    private var doneCount: Int { items.filter(\.isChecked).count }
    private var activeItems: [CheckItem] { items.filter { !$0.isChecked } }
    private var doneItems: [CheckItem] { items.filter { $0.isChecked } }

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

    private func checkRow(_ item: CheckItem) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggleChecklistItem(taskID: task.id, lineIndex: item.id)
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
                store.removeChecklistItem(taskID: task.id, lineIndex: item.id)
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
