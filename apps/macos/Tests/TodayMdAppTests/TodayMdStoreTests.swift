import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdStoreTests: XCTestCase {
    func testAddUnassignedTaskCreatesTaskWithoutList() throws {
        let store = try makeStore()

        let task = store.addUnassignedTask(title: "Inbox task", block: .today)

        XCTAssertEqual(store.unassignedTasks.count, 1)
        XCTAssertEqual(store.unassignedTasks.first?.id, task.id)
        XCTAssertEqual(store.allTasks.first?.id, task.id)
        XCTAssertEqual(task.block, .today)
        XCTAssertNil(task.list)
    }

    func testAssignTaskMovesUnassignedTaskIntoSelectedList() throws {
        let store = try makeStore()
        let list = store.addList(name: "Work", icon: "briefcase", color: .blue)
        let task = store.addUnassignedTask(title: "Inbox task", block: .today)

        store.assignTask(id: task.id, toListID: list.id)

        XCTAssertTrue(store.unassignedTasks.isEmpty)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items.first?.id, task.id)
        XCTAssertEqual(task.list?.id, list.id)
    }

    private func makeStore() throws -> TodayMdStore {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return TodayMdStore(
            databaseURL: rootURL.appendingPathComponent("today-md.sqlite"),
            shouldSeedShowcaseData: false
        )
    }
}
