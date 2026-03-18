import SwiftUI

struct SidebarView: View {
    @Environment(TodayMdStore.self) private var store
    @EnvironmentObject private var presentationState: AppPresentationState
    @Binding var selection: SidebarSelection

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
        store.allTasks.filter { !$0.isDone }.count
    }

    var body: some View {
        List {
            Section {
                Button(action: { selection = .all }) {
                    HStack(spacing: 12) {
                        Image(systemName: "tray.2")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 24)

                        Text(store.hasActiveSearch ? "Search Results" : "All Tasks")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                        Spacer()

                        Text("\(allActiveCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .listRowBackground(
                    selection == .all ? Color.blue.opacity(0.12) : Color.clear
                )
            }

            Section("Lists") {
                ForEach(store.lists.sorted(by: { $0.sortOrder < $1.sortOrder })) { list in
                    listRow(list)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            shortcutHintFooter
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { isAddingList = true }) {
                    Image(systemName: "plus")
                }
                .help("Add List")
            }
        }
        .sheet(isPresented: $isAddingList) { addListSheet }
        .sheet(item: $editingList) { list in renameListSheet(list) }
    }

    private var shortcutHintFooter: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: { presentationState.presentKeyboardShortcuts() }) {
                HStack(spacing: 8) {
                    ShortcutSequenceView(
                        shortcut: "Cmd + /",
                        tone: .secondary,
                        font: .system(size: 11, weight: .semibold, design: .rounded)
                    )

                    Text("to show keyboard shortcuts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
            .help("Open the keyboard shortcuts cheatsheet")
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listRow(_ list: TaskList) -> some View {
        let activeCount = list.items.filter { !$0.isDone }.count
        return Button(action: { selection = .list(list.id) }) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Spacer()

                Text("\(activeCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .listRowBackground(
            selection == .list(list.id) ? list.listColor.color.opacity(0.1) : Color.clear
        )
        .contextMenu {
            Button("Rename...") {
                startEditing(list)
            }
            Menu("Color") {
                ForEach(ListColor.allCases) { color in
                    Button(action: {
                        store.updateList(id: list.id, name: list.name, icon: list.icon, color: color)
                    }) {
                        Label(color.label, systemImage: list.listColor == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
            Menu("Icon") {
                ForEach(availableIcons, id: \.self) { icon in
                    Button(action: {
                        store.updateList(id: list.id, name: list.name, icon: icon, color: list.listColor)
                    }) {
                        Label(iconLabel(for: icon), systemImage: list.icon == icon ? "checkmark.circle.fill" : icon)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                if case .list(let selectedID) = selection, selectedID == list.id {
                    selection = .all
                }
                store.deleteList(id: list.id)
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
                ForEach(ListColor.allCases) { color in
                    Button(action: { newListColor = color }) {
                        Circle()
                            .fill(color.color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: newListColor == color ? 2 : 0)
                            )
                            .shadow(color: newListColor == color ? color.color.opacity(0.5) : .clear, radius: 3)
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
                ForEach(ListColor.allCases) { color in
                    Button(action: { editColor = color }) {
                        Circle()
                            .fill(color.color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: editColor == color ? 2 : 0)
                            )
                            .shadow(color: editColor == color ? color.color.opacity(0.5) : .clear, radius: 3)
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
        let list = store.addList(name: name, icon: newListIcon, color: newListColor)
        selection = .list(list.id)
        newListName = ""
        newListIcon = "checklist"
        isAddingList = false

        let allColors = ListColor.allCases
        if let idx = allColors.firstIndex(of: newListColor) {
            newListColor = allColors[(idx + 1) % allColors.count]
        }
    }

    private func renameList(_ list: TaskList) {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.updateList(id: list.id, name: name, icon: editIcon, color: editColor)
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
