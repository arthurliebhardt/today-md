import SwiftUI
import SwiftData

@main
struct TodoApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([TaskList.self, TaskItem.self, SubTask.self, TaskNote.self])
        let config = ModelConfiguration("TodoStore3", schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-wal"))
            container = try! ModelContainer(for: schema, configurations: [config])
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
