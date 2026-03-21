import SwiftUI
import WidgetKit

struct TodayMdWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayMdWidgetSnapshot
    let diagnostics: TodayMdWidgetLoadDiagnostics
}

struct TodayMdWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayMdWidgetEntry {
        TodayMdWidgetEntry(
            date: Date(),
            snapshot: TodayMdWidgetSnapshot(
                generatedAt: Date(),
                tasks: [
                    .init(
                        id: UUID(),
                        title: "Review onboarding polish PR",
                        isDone: false,
                        listName: "Work",
                        sortOrder: 0,
                        creationDate: Date()
                    ),
                    .init(
                        id: UUID(),
                        title: "Book dentist appointment",
                        isDone: false,
                        listName: "Private",
                        sortOrder: 1,
                        creationDate: Date()
                    )
                ],
                completedCount: 1
            ),
            diagnostics: TodayMdWidgetLoadDiagnostics(
                source: "placeholder",
                details: ["preview"]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayMdWidgetEntry) -> Void) {
        let result = TodayMdWidgetSnapshotStore.loadResult()
        completion(
            TodayMdWidgetEntry(
                date: Date(),
                snapshot: result.snapshot,
                diagnostics: result.diagnostics
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayMdWidgetEntry>) -> Void) {
        let result = TodayMdWidgetSnapshotStore.loadResult()
        let entry = TodayMdWidgetEntry(
            date: Date(),
            snapshot: result.snapshot,
            diagnostics: result.diagnostics
        )

        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct TodayMdTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TodayMdWidgetEntry

    private var visibleTasks: [TodayMdWidgetSnapshot.Task] {
        let limit: Int
        switch family {
        case .systemSmall:
            limit = 3
        case .systemMedium:
            limit = 5
        default:
            limit = 8
        }

        return Array(entry.snapshot.remainingTasks.prefix(limit))
    }

    private var hiddenTaskCount: Int {
        max(entry.snapshot.remainingCount - visibleTasks.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if visibleTasks.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                    }

                    if hiddenTaskCount > 0 {
                        Text("+\(hiddenTaskCount) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            footer
        }
        .containerBackground(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 1.0),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.headline)
                Text(entry.snapshot.remainingCount == 1 ? "1 task left" : "\(entry.snapshot.remainingCount) tasks left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "sun.max.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.completedCount == 0 ? "No tasks scheduled." : "Everything is done.")
                .font(.subheadline.weight(.semibold))
            Text(
                entry.snapshot.completedCount == 0
                    ? "Move tasks into Today in the app and they will appear here."
                    : "Today's list is clear."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func taskRow(_ task: TodayMdWidgetSnapshot.Task) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(2)

                if let listName = task.listName {
                    Text(listName.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.10))
                        )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if entry.snapshot.completedCount > 0 {
                Label(
                    "\(entry.snapshot.completedCount) done",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct TodayMdTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TodayMdWidgetConfiguration.widgetKind,
            provider: TodayMdWidgetProvider()
        ) { entry in
            TodayMdTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Tasks")
        .description("Shows the tasks currently in your Today column.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TodayMdWidgets: WidgetBundle {
    var body: some Widget {
        TodayMdTodayWidget()
    }
}
