import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var editingList: TaskList?
    @State private var editName = ""
    @State private var newListColor: ListColor = .blue

    private var allActiveCount: Int {
        lists.reduce(0) { $0 + $1.items.filter { !$0.isDone }.count }
    }

    var body: some View {
        List {
            Section {
                Button(action: { selection = .all }) {
                    Label {
                        HStack {
                            Text("All Tasks")
                            Spacer()
                            Text("\(allActiveCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tray.2")
                    }
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
        .onAppear {
            if lists.isEmpty {
                let l = TaskList(name: "Private", icon: "person", color: .blue, sortOrder: 0)
                modelContext.insert(l)
            }
        }
    }

    private func listRow(_ list: TaskList) -> some View {
        let activeCount = list.items.filter { !$0.isDone }.count
        return Button(action: { selection = .list(list) }) {
            Label {
                HStack {
                    Text(list.name)
                    Spacer()
                    Text("\(activeCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(list.listColor.color)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selection == .list(list) ? list.listColor.color.opacity(0.1) : Color.clear
        )
        .contextMenu {
            Button("Rename...") {
                editName = list.name
                editingList = list
            }
            Menu("Color") {
                ForEach(ListColor.allCases) { c in
                    Button(action: { list.listColor = c }) {
                        Label(c.label, systemImage: list.listColor == c ? "checkmark.circle.fill" : "circle.fill")
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
                .frame(width: 250)
                .onSubmit { addList() }
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
                Button("Cancel") { newListName = ""; isAddingList = false }
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
            Text("Rename List").font(.headline)
            TextField("List name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit { renameList(list) }
            HStack {
                Button("Cancel") { editingList = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { renameList(list) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func addList() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let list = TaskList(name: name, color: newListColor, sortOrder: lists.count)
        modelContext.insert(list)
        selection = .list(list)
        newListName = ""
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
        editingList = nil
    }
}
