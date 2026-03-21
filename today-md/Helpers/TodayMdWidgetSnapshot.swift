import Foundation

enum TodayMdWidgetConfiguration {
    static let appGroupIdentifier = "group.com.today-md.shared"
    static let widgetKind = "TodayMdTodayWidget"
    static let snapshotFilename = "today-widget-snapshot.json"
    static let snapshotDefaultsKey = "today-widget-snapshot"
}

struct TodayMdWidgetSnapshot: Codable, Equatable {
    struct Task: Codable, Equatable, Identifiable {
        let id: UUID
        let title: String
        let isDone: Bool
        let listName: String?
        let sortOrder: Int
        let creationDate: Date
    }

    let generatedAt: Date
    let tasks: [Task]
    let completedCount: Int

    var remainingTasks: [Task] {
        tasks.filter { !$0.isDone }
    }

    var remainingCount: Int {
        remainingTasks.count
    }

    static let empty = TodayMdWidgetSnapshot(
        generatedAt: .distantPast,
        tasks: [],
        completedCount: 0
    )
}

struct TodayMdWidgetLoadDiagnostics: Equatable {
    let source: String
    let details: [String]
}

struct TodayMdWidgetLoadResult: Equatable {
    let snapshot: TodayMdWidgetSnapshot
    let diagnostics: TodayMdWidgetLoadDiagnostics
}

enum TodayMdWidgetSnapshotStore {
    static func loadResult(fileManager: FileManager = .default) -> TodayMdWidgetLoadResult {
        var details: [String] = []

        if let defaultsResult = loadFromDefaults() {
            details.append("defaults \(defaultsResult.data.count)b")
            return TodayMdWidgetLoadResult(
                snapshot: defaultsResult.snapshot,
                diagnostics: TodayMdWidgetLoadDiagnostics(
                    source: "defaults",
                    details: details
                )
            )
        }

        details.append("defaults miss")

        guard let url = snapshotURL(fileManager: fileManager) else {
            details.append("url nil")
            return TodayMdWidgetLoadResult(
                snapshot: .empty,
                diagnostics: TodayMdWidgetLoadDiagnostics(
                    source: "empty",
                    details: details
                )
            )
        }

        details.append(url.lastPathComponent)
        return load(from: url, details: details)
    }

    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TodayMdWidgetConfiguration.appGroupIdentifier
        ) {
            return containerURL
                .appendingPathComponent(TodayMdWidgetConfiguration.snapshotFilename, isDirectory: false)
        }

        #if os(macOS)
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(TodayMdWidgetConfiguration.appGroupIdentifier, isDirectory: true)
            .appendingPathComponent(TodayMdWidgetConfiguration.snapshotFilename, isDirectory: false)
        #else
        return nil
        #endif
    }

    static func load(fileManager: FileManager = .default) -> TodayMdWidgetSnapshot {
        loadResult(fileManager: fileManager).snapshot
    }

    static func load(from url: URL) -> TodayMdWidgetSnapshot {
        load(from: url, details: []).snapshot
    }

    private static func load(from url: URL, details: [String]) -> TodayMdWidgetLoadResult {
        var details = details

        do {
            let data = try Data(contentsOf: url)
            details.append("file \(data.count)b")

            let snapshot = try decoder().decode(TodayMdWidgetSnapshot.self, from: data)
            return TodayMdWidgetLoadResult(
                snapshot: snapshot,
                diagnostics: TodayMdWidgetLoadDiagnostics(
                    source: "file",
                    details: details
                )
            )
        } catch {
            details.append("file \(error.localizedDescription)")
            return TodayMdWidgetLoadResult(
                snapshot: .empty,
                diagnostics: TodayMdWidgetLoadDiagnostics(
                    source: "empty",
                    details: details
                )
            )
        }
    }

    static func write(_ snapshot: TodayMdWidgetSnapshot, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder().encode(snapshot)
        saveToDefaults(data: data)
        try data.write(to: url, options: .atomic)
    }

    private static func loadFromDefaults() -> (snapshot: TodayMdWidgetSnapshot, data: Data)? {
        guard
            let defaults = UserDefaults(suiteName: TodayMdWidgetConfiguration.appGroupIdentifier),
            let data = defaults.data(forKey: TodayMdWidgetConfiguration.snapshotDefaultsKey),
            let snapshot = try? decoder().decode(TodayMdWidgetSnapshot.self, from: data)
        else {
            return nil
        }

        return (snapshot, data)
    }

    private static func saveToDefaults(data: Data) {
        guard let defaults = UserDefaults(suiteName: TodayMdWidgetConfiguration.appGroupIdentifier) else {
            return
        }

        defaults.set(data, forKey: TodayMdWidgetConfiguration.snapshotDefaultsKey)
        defaults.synchronize()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
