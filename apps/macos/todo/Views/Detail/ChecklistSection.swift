import SwiftUI
import SwiftData

struct ChecklistSection: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @State private var newItemTitle = ""
    @State private var isExpanded = true

    private struct CheckItem: Identifiable {
        let id: Int // line index
        let title: String
        let isChecked: Bool
    }

    private var items: [CheckItem] {
        guard let content = task.note?.content else { return [] }
        return content.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                return CheckItem(id: index, title: String(t.dropFirst(6)), isChecked: true)
            } else if t.hasPrefix("- [ ] ") {
                return CheckItem(id: index, title: String(t.dropFirst(6)), isChecked: false)
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
                toggleItem(at: item.id)
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
                removeItem(at: item.id)
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

    private func toggleItem(at lineIndex: Int) {
        guard let note = task.note else { return }
        var lines = note.content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        let line = lines[lineIndex]
        if line.contains("- [ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else {
            lines[lineIndex] = line
                .replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
        }
        note.content = lines.joined(separator: "\n")
        note.lastModified = Date()
    }

    private func removeItem(at lineIndex: Int) {
        guard let note = task.note else { return }
        var lines = note.content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        lines.remove(at: lineIndex)
        note.content = lines.joined(separator: "\n")
        note.lastModified = Date()
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let entry = "- [ ] \(title)"

        if let note = task.note {
            if note.content.isEmpty {
                note.content = entry
            } else {
                note.content += "\n" + entry
            }
            note.lastModified = Date()
        } else {
            let note = TaskNote(content: entry)
            note.parentTask = task
            modelContext.insert(note)
        }
        newItemTitle = ""
    }
}
