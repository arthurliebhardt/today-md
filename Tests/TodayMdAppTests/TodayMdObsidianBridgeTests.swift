import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdObsidianBridgeTests: XCTestCase {
    func testMergedArchiveUsesUpdatedAtForImportedTaskModifiedDate() throws {
        let markdownDirectoryURL = try makeMarkdownDirectory()
        defer { try? FileManager.default.removeItem(at: markdownDirectoryURL.deletingLastPathComponent()) }

        let taskID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_775_000_600)
        let scheduledAt = Date(timeIntervalSince1970: 1_775_086_400)

        try writeMarkdownTask(
            to: markdownDirectoryURL.appendingPathComponent("imported-task.md"),
            content: """
            ---
            task_id: "\(taskID.uuidString)"
            title: "Imported task"
            lane_raw: "today"
            created_at: "\(iso8601(createdAt))"
            updated_at: "\(iso8601(updatedAt))"
            scheduled_at: "\(iso8601(scheduledAt))"
            ---

            Imported from markdown
            """
        )

        let mergedArchive = try XCTUnwrap(
            TodayMdObsidianBridge.mergedArchive(
                baseArchive: nil,
                markdownDirectoryURL: markdownDirectoryURL
            )
        )
        let hydrated = mergedArchive.instantiate()
        let task = try XCTUnwrap(hydrated.unassignedTasks.first)

        XCTAssertEqual(task.id, taskID)
        XCTAssertEqual(task.modifiedDate, updatedAt)
        XCTAssertEqual(task.scheduledDate, scheduledAt)
        XCTAssertEqual(task.schedulingState, .scheduled)
    }

    func testMergedArchiveUpdatesExistingTaskModifiedDateAndSchedule() throws {
        let markdownDirectoryURL = try makeMarkdownDirectory()
        defer { try? FileManager.default.removeItem(at: markdownDirectoryURL.deletingLastPathComponent()) }

        let taskID = UUID()
        let originalCreatedAt = Date(timeIntervalSince1970: 1_775_000_000)
        let originalScheduledAt = Date(timeIntervalSince1970: 1_775_043_200)
        let updatedAt = Date(timeIntervalSince1970: 1_775_086_400)
        let updatedScheduledAt = Date(timeIntervalSince1970: 1_775_172_800)

        let task = TaskItem(
            id: taskID,
            title: "Existing task",
            block: .today,
            schedulingState: .scheduled,
            sortOrder: 0,
            creationDate: originalCreatedAt,
            modifiedDate: originalCreatedAt,
            scheduledDate: originalScheduledAt
        )

        try writeMarkdownTask(
            to: markdownDirectoryURL.appendingPathComponent("existing-task.md"),
            content: """
            ---
            task_id: "\(taskID.uuidString)"
            title: "Updated from markdown"
            lane_raw: "thisWeek"
            created_at: "\(iso8601(originalCreatedAt))"
            updated_at: "\(iso8601(updatedAt))"
            scheduled_at: "\(iso8601(updatedScheduledAt))"
            ---

            Updated body
            """
        )

        let mergedArchive = try XCTUnwrap(
            TodayMdObsidianBridge.mergedArchive(
                baseArchive: TodayMdArchive(lists: [], unassignedTasks: [task]),
                markdownDirectoryURL: markdownDirectoryURL
            )
        )
        let hydrated = mergedArchive.instantiate()
        let mergedTask = try XCTUnwrap(hydrated.unassignedTasks.first)

        XCTAssertEqual(mergedTask.title, "Updated from markdown")
        XCTAssertEqual(mergedTask.block, .thisWeek)
        XCTAssertEqual(mergedTask.modifiedDate, updatedAt)
        XCTAssertEqual(mergedTask.scheduledDate, updatedScheduledAt)
        XCTAssertEqual(mergedTask.schedulingState, .scheduled)
    }

    private func makeMarkdownDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let markdownDirectory = root.appendingPathComponent("Markdown Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: markdownDirectory, withIntermediateDirectories: true)
        return markdownDirectory
    }

    private func writeMarkdownTask(to url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
