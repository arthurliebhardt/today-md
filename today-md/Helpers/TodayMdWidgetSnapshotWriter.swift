import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum TodayMdWidgetSnapshotWriter {
    static func sync(lists: [TaskList], unassignedTasks: [TaskItem], fileManager: FileManager = .default) {
        guard let snapshotURL = TodayMdWidgetSnapshotStore.snapshotURL(fileManager: fileManager) else {
            return
        }

        do {
            let snapshot = makeSnapshot(lists: lists, unassignedTasks: unassignedTasks)
            try TodayMdWidgetSnapshotStore.write(snapshot, to: snapshotURL)
            reloadWidgetTimelines()
        } catch {
            assertionFailure("Failed to update widget snapshot: \(error.localizedDescription)")
        }
    }

    static func makeSnapshot(
        lists: [TaskList],
        unassignedTasks: [TaskItem],
        generatedAt: Date = Date()
    ) -> TodayMdWidgetSnapshot {
        let listedTasks = lists.flatMap { list in
            list.items.map { (task: $0, listName: Optional(list.name)) }
        }

        let allTodayTasks = (listedTasks + unassignedTasks.map { (task: $0, listName: Optional<String>.none) })
            .filter { $0.task.block == .today }
            .sorted { lhs, rhs in
                taskSort(lhs: lhs.task, rhs: rhs.task)
            }
            .map { item in
                TodayMdWidgetSnapshot.Task(
                    id: item.task.id,
                    title: item.task.title,
                    isDone: item.task.isDone,
                    listName: item.listName,
                    sortOrder: item.task.sortOrder,
                    creationDate: item.task.creationDate
                )
            }

        return TodayMdWidgetSnapshot(
            generatedAt: generatedAt,
            tasks: allTodayTasks,
            completedCount: allTodayTasks.filter(\.isDone).count
        )
    }

    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayMdWidgetConfiguration.widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
