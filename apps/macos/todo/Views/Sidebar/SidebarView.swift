import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var newListIcon = "checklist"
    @State private var editingList: TaskList?
    @State private var editName = ""
    @State private var editIcon = "checklist"
    @State private var newListColor: ListColor = .blue
    @State private var editColor: ListColor = .blue

    private let availableIcons = [
        "checklist", "person", "briefcase", "house", "folder",
        "calendar", "book", "graduationcap", "heart", "star",
        "bolt", "cart", "fork.knife", "leaf", "music.note",
        "gamecontroller", "dumbbell", "airplane", "tag", "paintpalette"
    ]

    private var allActiveCount: Int {
        lists.reduce(0) { $0 + $1.items.filter { !$0.isDone }.count }
    }

    var body: some View {
        List {
            Section {
                Button(action: { selection = .all }) {
                    HStack(spacing: 12) {
                        Image(systemName: "tray.2")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 24)

                        Text("All Tasks")

                        Spacer()

                        Text("\(allActiveCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selection == .all ? Color.blue.opacity(0.12) : Color.clear
                )
            }

            Section("Lists") {
                ForEach(lists) { list in
                    listRow(list)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button(action: { isAddingList = true }) {
                    Label("Add List", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingList) { addListSheet }
        .sheet(item: $editingList) { list in renameListSheet(list) }
    }

    private func listRow(_ list: TaskList) -> some View {
        let activeCount = list.items.filter { !$0.isDone }.count
        return Button(action: { selection = .list(list) }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(list.listColor.color.opacity(0.18))
                        .frame(width: 26, height: 26)

                    Image(systemName: list.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(list.listColor.color)
                }

                Text(list.name)
                    .lineLimit(1)

                Spacer()

                Text("\(activeCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selection == .list(list) ? list.listColor.color.opacity(0.1) : Color.clear
        )
        .contextMenu {
            Button("Rename...") {
                startEditing(list)
            }
            Menu("Color") {
                ForEach(ListColor.allCases) { c in
                    Button(action: { list.listColor = c }) {
                        Label(c.label, systemImage: list.listColor == c ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
            Menu("Icon") {
                ForEach(availableIcons, id: \.self) { icon in
                    Button(action: { list.icon = icon }) {
                        Label(iconLabel(for: icon), systemImage: list.icon == icon ? "checkmark.circle.fill" : icon)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                if case .list(let sel) = selection, sel == list {
                    selection = .all
                }
                modelContext.delete(list)
            }
        }
    }

    private var addListSheet: some View {
        VStack(spacing: 16) {
            Text("New List").font(.headline)
            TextField("List name", text: $newListName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { addList() }
            iconPicker(selection: $newListIcon)
            HStack(spacing: 6) {
                ForEach(ListColor.allCases) { c in
                    Button(action: { newListColor = c }) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: newListColor == c ? 2 : 0)
                            )
                            .shadow(color: newListColor == c ? c.color.opacity(0.5) : .clear, radius: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Cancel") {
                    newListName = ""
                    newListIcon = "checklist"
                    isAddingList = false
                }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addList() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func renameListSheet(_ list: TaskList) -> some View {
        VStack(spacing: 16) {
            Text("Edit List").font(.headline)
            TextField("List name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { renameList(list) }
            iconPicker(selection: $editIcon)
            HStack(spacing: 6) {
                ForEach(ListColor.allCases) { c in
                    Button(action: { editColor = c }) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: editColor == c ? 2 : 0)
                            )
                            .shadow(color: editColor == c ? c.color.opacity(0.5) : .clear, radius: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Cancel") { editingList = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { renameList(list) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func addList() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let list = TaskList(name: name, icon: newListIcon, color: newListColor, sortOrder: lists.count)
        modelContext.insert(list)
        selection = .list(list)
        newListName = ""
        newListIcon = "checklist"
        isAddingList = false
        // Cycle to next color for the next list
        let allColors = ListColor.allCases
        if let idx = allColors.firstIndex(of: newListColor) {
            newListColor = allColors[(idx + 1) % allColors.count]
        }
    }

    private func renameList(_ list: TaskList) {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        list.name = name
        list.icon = editIcon
        list.listColor = editColor
        editingList = nil
    }

    private func startEditing(_ list: TaskList) {
        editName = list.name
        editIcon = list.icon
        editColor = list.listColor
        editingList = list
    }

    @ViewBuilder
    private func iconPicker(selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 5), spacing: 8) {
                ForEach(availableIcons, id: \.self) { icon in
                    Button(action: { selection.wrappedValue = icon }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection.wrappedValue == icon ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))

                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selection.wrappedValue == icon ? Color.accentColor : Color.primary)
                        }
                        .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 222, alignment: .leading)
    }

    private func iconLabel(for icon: String) -> String {
        switch icon {
        case "checklist": return "Checklist"
        case "person": return "Personal"
        case "briefcase": return "Work"
        case "house": return "Home"
        case "folder": return "Folder"
        case "calendar": return "Calendar"
        case "book": return "Book"
        case "graduationcap": return "Study"
        case "heart": return "Health"
        case "star": return "Star"
        case "bolt": return "Urgent"
        case "cart": return "Shopping"
        case "fork.knife": return "Food"
        case "leaf": return "Nature"
        case "music.note": return "Music"
        case "gamecontroller": return "Games"
        case "dumbbell": return "Fitness"
        case "airplane": return "Travel"
        case "tag": return "Tagged"
        case "paintpalette": return "Creative"
        default: return icon
        }
    }
}
