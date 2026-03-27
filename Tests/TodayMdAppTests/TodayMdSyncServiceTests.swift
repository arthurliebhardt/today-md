import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdSyncServiceTests: XCTestCase {
    func testEnableSyncCreatesSyncSnapshotAndMarkdownArchive() throws {
        let context = try makeContext()
        _ = createTask(in: context.store, title: "Write release notes", note: "# Notes")

        try context.service.enableSync(at: context.syncFolderURL)

        let archiveURL = syncArchiveURL(in: context.syncFolderURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let archive = try readArchive(at: archiveURL)
        XCTAssertNotNil(archive.syncRevisionID)

        let markdownDirectoryURL = context.syncFolderURL.appendingPathComponent("Markdown Archive", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markdownDirectoryURL.path))

        let markdownFiles = try FileManager.default.contentsOfDirectory(
            at: markdownDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(markdownFiles.filter { $0.pathExtension == "md" }.count, 1)
        XCTAssertEqual(context.service.markdownArchivePath, markdownDirectoryURL.path)
    }

    func testEnableSyncExportsTaskWithoutNoteToMarkdownArchive() throws {
        let context = try makeContext()
        _ = createTask(in: context.store, title: "Title only")

        try context.service.enableSync(at: context.syncFolderURL)

        let markdownDirectoryURL = context.syncFolderURL.appendingPathComponent("Markdown Archive", isDirectory: true)
        let markdownFiles = try FileManager.default.contentsOfDirectory(
            at: markdownDirectoryURL,
            includingPropertiesForKeys: nil
        )

        XCTAssertEqual(markdownFiles.filter { $0.pathExtension == "md" }.count, 1)
    }

    func testExistingLegacyRemoteSnapshotPopulatesEmptyStoreWithoutShowcaseSeedData() throws {
        let sourceContext = try makeContext()
        _ = createTask(in: sourceContext.store, title: "Cloud task", note: "Pulled from remote")
        let sourceArchive = sourceContext.store.makeArchive()

        let destinationContext = try makeContext()
        try writeLegacyArchive(sourceArchive, to: syncArchiveURL(in: destinationContext.syncFolderURL))

        try destinationContext.service.enableSync(at: destinationContext.syncFolderURL)

        XCTAssertEqual(destinationContext.store.allTasks.count, 1)
        XCTAssertEqual(destinationContext.store.allTasks.first?.title, "Cloud task")
        XCTAssertFalse(destinationContext.store.lists.contains(where: { $0.name == "Private" || $0.name == "Work" }))
    }

    func testLocalMutationSchedulesDebouncedPushWithNewRevision() throws {
        let context = try makeContext(debounceInterval: 0.05)
        let task = createTask(in: context.store, title: "Initial title")

        try context.service.enableSync(at: context.syncFolderURL)
        let initialArchive = try readArchive(at: syncArchiveURL(in: context.syncFolderURL))

        context.store.updateTaskTitle(id: task.id, title: "Updated title")

        XCTAssertTrue(waitUntil(timeout: 2) {
            guard let latestRevision = try? self.readArchive(at: self.syncArchiveURL(in: context.syncFolderURL)).syncRevisionID else {
                return false
            }
            return latestRevision != initialArchive.syncRevisionID
        })

        let updatedArchive = try readArchive(at: syncArchiveURL(in: context.syncFolderURL))
        XCTAssertEqual(updatedArchive.lists.first?.tasks.first?.title, "Updated title")
        XCTAssertNotEqual(updatedArchive.syncRevisionID, initialArchive.syncRevisionID)
    }

    func testRemoteNewerPullsWhenNoLocalChanges() throws {
        let context = try makeContext(debounceInterval: 5)
        _ = createTask(in: context.store, title: "Local title")

        try context.service.enableSync(at: context.syncFolderURL)

        let archiveURL = syncArchiveURL(in: context.syncFolderURL)
        let initialArchive = try readArchive(at: archiveURL)
        try writeArchive(
            at: archiveURL,
            updating: initialArchive,
            title: "Cloud title",
            revisionID: "remote-revision-2",
            updatedByDeviceID: "cloud-device"
        )

        context.service.syncNow()

        XCTAssertEqual(context.store.allTasks.first?.title, "Cloud title")
        XCTAssertEqual(context.service.status, .idle)
    }

    func testRemoteMarkdownEditPullsWhenMarkdownArchiveIsNewerThanJSONSnapshot() throws {
        let context = try makeContext(debounceInterval: 5)
        let task = createTask(in: context.store, title: "Local title", note: "Original note")

        try context.service.enableSync(at: context.syncFolderURL)

        let markdownDirectoryURL = context.syncFolderURL.appendingPathComponent("Markdown Archive", isDirectory: true)
        let markdownFiles = try FileManager.default.contentsOfDirectory(
            at: markdownDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let markdownURL = try XCTUnwrap(markdownFiles.first(where: { $0.pathExtension == "md" }))

        let updatedMarkdown = """
        ---
        task_id: "\(task.id.uuidString)"
        title: "Edited in Obsidian"
        done: true
        list: "Remote"
        lane: "Backlog"
        lane_raw: "backlog"
        scheduling_state: "scheduled"
        created_at: "\(iso8601String(from: task.creationDate))"
        updated_at: "2000-01-01T00:00:00Z"
        ---

        New body from Obsidian
        """
        try updatedMarkdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: markdownURL.path
        )

        context.service.syncNow()

        let updatedTask = try XCTUnwrap(context.store.allTasks.first)
        XCTAssertEqual(updatedTask.title, "Edited in Obsidian")
        XCTAssertEqual(updatedTask.list?.name, "Remote")
        XCTAssertEqual(updatedTask.block, .backlog)
        XCTAssertTrue(updatedTask.isDone)
        XCTAssertTrue(updatedTask.isScheduled)
        XCTAssertEqual(updatedTask.note?.content, "New body from Obsidian")
    }

    func testMarkdownOnlyTaskInSyncFolderCreatesTaskWithoutJSONSnapshot() throws {
        let context = try makeContext()
        let markdownDirectoryURL = context.syncFolderURL.appendingPathComponent("Markdown Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: markdownDirectoryURL, withIntermediateDirectories: true)

        let markdownURL = markdownDirectoryURL.appendingPathComponent("new-obsidian-task.md")
        let markdown = """
        ---
        title: "Inbox from Obsidian"
        list: "Obsidian"
        lane_raw: "today"
        done: false
        scheduling_state: "unscheduled"
        created_at: "2026-03-26T10:00:00Z"
        ---

        - [ ] First imported checkbox
        """
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        try context.service.enableSync(at: context.syncFolderURL)

        let importedTask = try XCTUnwrap(context.store.allTasks.first)
        XCTAssertEqual(importedTask.title, "Inbox from Obsidian")
        XCTAssertEqual(importedTask.list?.name, "Obsidian")
        XCTAssertEqual(importedTask.block, .today)
        XCTAssertEqual(importedTask.note?.content, "- [ ] First imported checkbox")
        XCTAssertEqual(context.store.allTasks.count, 1)
    }

    func testRemoteNewerWithUnsyncedLocalChangesEntersConflict() throws {
        let context = try makeContext(debounceInterval: 5)
        let task = createTask(in: context.store, title: "Original")

        try context.service.enableSync(at: context.syncFolderURL)

        context.store.updateTaskTitle(id: task.id, title: "Local edit")

        let archiveURL = syncArchiveURL(in: context.syncFolderURL)
        let remoteArchive = try readArchive(at: archiveURL)
        try writeArchive(
            at: archiveURL,
            updating: remoteArchive,
            title: "Cloud edit",
            revisionID: "remote-revision-2",
            updatedByDeviceID: "cloud-device"
        )

        context.service.syncNow()

        XCTAssertEqual(context.service.status, .conflict)
        XCTAssertNotNil(context.service.conflict)
        XCTAssertEqual(context.store.allTasks.first?.title, "Local edit")
        XCTAssertEqual(try readArchive(at: archiveURL).lists.first?.tasks.first?.title, "Cloud edit")
    }

    func testKeepLocalConflictResolutionBacksUpCloudVersionAndPushesLocalVersion() throws {
        let context = try makeContext(debounceInterval: 5)
        let task = createTask(in: context.store, title: "Original")

        try context.service.enableSync(at: context.syncFolderURL)

        context.store.updateTaskTitle(id: task.id, title: "Local edit")

        let archiveURL = syncArchiveURL(in: context.syncFolderURL)
        let remoteArchive = try readArchive(at: archiveURL)
        try writeArchive(
            at: archiveURL,
            updating: remoteArchive,
            title: "Cloud edit",
            revisionID: "remote-revision-2",
            updatedByDeviceID: "cloud-device"
        )

        context.service.syncNow()
        context.service.resolveConflict(.keepLocal)

        XCTAssertEqual(context.service.status, .idle)
        XCTAssertNil(context.service.conflict)
        XCTAssertEqual(try readArchive(at: archiveURL).lists.first?.tasks.first?.title, "Local edit")

        let backupDirectoryURL = context.syncFolderURL.appendingPathComponent("Conflict Backups", isDirectory: true)
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDirectoryURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(backupFiles.filter { $0.pathExtension == "json" }.count, 1)
    }

    func testUseRemoteConflictResolutionBacksUpLocalVersionAndPullsCloudVersion() throws {
        let context = try makeContext(debounceInterval: 5)
        let task = createTask(in: context.store, title: "Original")

        try context.service.enableSync(at: context.syncFolderURL)

        context.store.updateTaskTitle(id: task.id, title: "Local edit")

        let archiveURL = syncArchiveURL(in: context.syncFolderURL)
        let remoteArchive = try readArchive(at: archiveURL)
        try writeArchive(
            at: archiveURL,
            updating: remoteArchive,
            title: "Cloud edit",
            revisionID: "remote-revision-2",
            updatedByDeviceID: "cloud-device"
        )

        context.service.syncNow()
        context.service.resolveConflict(.useRemote)

        XCTAssertEqual(context.service.status, .idle)
        XCTAssertNil(context.service.conflict)
        XCTAssertEqual(context.store.allTasks.first?.title, "Cloud edit")

        let backupDirectoryURL = context.syncFolderURL.appendingPathComponent("Conflict Backups", isDirectory: true)
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDirectoryURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(backupFiles.filter { $0.pathExtension == "json" }.count, 1)
    }

    func testCorruptRemoteJSONLeavesLocalDataUntouchedAndSetsError() throws {
        let context = try makeContext(debounceInterval: 5)
        _ = createTask(in: context.store, title: "Stable title")

        try context.service.enableSync(at: context.syncFolderURL)

        let archiveURL = syncArchiveURL(in: context.syncFolderURL)
        try Data("not-json".utf8).write(to: archiveURL, options: .atomic)

        context.service.syncNow()

        XCTAssertEqual(context.service.status, .error)
        XCTAssertNotNil(context.service.lastError)
        XCTAssertEqual(context.store.allTasks.first?.title, "Stable title")
    }

    func testInvalidBookmarkDisablesSyncUntilFolderIsChosenAgain() throws {
        let context = try makeContext()

        let invalidState: [String: Any] = [
            "deviceID": UUID().uuidString.lowercased(),
            "bookmarkData": Data([0x01, 0x02, 0x03]).base64EncodedString(),
            "lastKnownFolderPath": context.syncFolderURL.path,
            "lastSyncedRevision": NSNull(),
            "lastSyncAt": NSNull(),
            "lastError": NSNull(),
            "syncEnabled": true,
            "hasUnsyncedLocalChanges": false,
            "status": SyncStatus.idle.rawValue
        ]
        let defaultsData = try JSONSerialization.data(withJSONObject: invalidState, options: [.sortedKeys])
        context.defaults.set(defaultsData, forKey: "today-md.sync.state")

        let service = TodayMdSyncService(
            userDefaults: context.defaults,
            debounceInterval: 0.05
        )
        service.attach(store: context.store)
        service.syncNow()

        XCTAssertFalse(service.syncEnabled)
        XCTAssertEqual(service.status, .error)
        XCTAssertNotNil(service.lastError)
    }

    private func makeContext(debounceInterval: TimeInterval = 0.05) throws -> TestContext {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let defaultsSuiteName = "today-md.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        addTeardownBlock {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            try? fileManager.removeItem(at: rootURL)
        }

        let store = TodayMdStore(
            databaseURL: rootURL.appendingPathComponent("today-md.sqlite"),
            shouldSeedShowcaseData: false
        )
        let service = TodayMdSyncService(
            userDefaults: defaults,
            debounceInterval: debounceInterval
        )
        service.attach(store: store)

        return TestContext(
            rootURL: rootURL,
            syncFolderURL: rootURL.appendingPathComponent("Sync Folder", isDirectory: true),
            defaults: defaults,
            store: store,
            service: service
        )
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        return condition()
    }

    private func createTask(in store: TodayMdStore, title: String, note: String? = nil) -> TaskItem {
        let list = store.addList(name: "Sync", icon: "arrow.triangle.2.circlepath", color: .blue)
        let task = store.addTask(title: title, block: .today, listID: list.id)!
        if let note {
            store.updateTaskNote(id: task.id, content: note)
        }
        return task
    }

    private func syncArchiveURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("today-md-sync.json", isDirectory: false)
    }

    private func readArchive(at url: URL) throws -> TodayMdArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TodayMdArchive.self, from: Data(contentsOf: url))
    }

    private func writeLegacyArchive(_ archive: TodayMdArchive, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(archive)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "syncRevisionID")
        json.removeValue(forKey: "syncUpdatedAt")
        json.removeValue(forKey: "syncUpdatedByDeviceID")

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try legacyData.write(to: url, options: .atomic)
    }

    private func writeArchive(
        at url: URL,
        updating archive: TodayMdArchive,
        title: String,
        revisionID: String,
        updatedByDeviceID: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(archive)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["syncRevisionID"] = revisionID
        json["syncUpdatedAt"] = iso8601String(from: Date())
        json["syncUpdatedByDeviceID"] = updatedByDeviceID

        if var lists = json["lists"] as? [[String: Any]],
           var firstList = lists.first,
           var tasks = firstList["tasks"] as? [[String: Any]],
           var firstTask = tasks.first {
            firstTask["title"] = title
            tasks[0] = firstTask
            firstList["tasks"] = tasks
            lists[0] = firstList
            json["lists"] = lists
        } else if var tasks = json["unassignedTasks"] as? [[String: Any]],
                  var firstTask = tasks.first {
            firstTask["title"] = title
            tasks[0] = firstTask
            json["unassignedTasks"] = tasks
        }

        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: url, options: .atomic)
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct TestContext {
    let rootURL: URL
    let syncFolderURL: URL
    let defaults: UserDefaults
    let store: TodayMdStore
    let service: TodayMdSyncService
}
