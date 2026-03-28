import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdReminderSyncServiceTests: XCTestCase {
    func testResolvedAuthorizationStatusFallsBackToFullAccessWhenManagedCalendarExists() {
        let resolved = TodayMdReminderSyncService.resolvedAuthorizationStatus(
            reported: .notDetermined,
            syncEnabled: true,
            lastSyncAt: Date(),
            hasManagedCalendar: true,
            hasVisibleReminderData: false
        )

        XCTAssertEqual(resolved, .fullAccess)
    }

    func testResolvedAuthorizationStatusFallsBackToFullAccessWhenReminderDataIsVisible() {
        let resolved = TodayMdReminderSyncService.resolvedAuthorizationStatus(
            reported: .notDetermined,
            syncEnabled: true,
            lastSyncAt: Date(),
            hasManagedCalendar: false,
            hasVisibleReminderData: true
        )

        XCTAssertEqual(resolved, .fullAccess)
    }

    func testResolvedAuthorizationStatusDoesNotFallbackToFullAccessWithoutManagedCalendarOrReminderData() {
        let resolved = TodayMdReminderSyncService.resolvedAuthorizationStatus(
            reported: .notDetermined,
            syncEnabled: true,
            lastSyncAt: Date(),
            hasManagedCalendar: false,
            hasVisibleReminderData: false
        )

        XCTAssertEqual(resolved, .notDetermined)
    }

    func testResolvedAuthorizationStatusKeepsExplicitDeniedState() {
        let resolved = TodayMdReminderSyncService.resolvedAuthorizationStatus(
            reported: .denied,
            syncEnabled: true,
            lastSyncAt: Date(),
            hasManagedCalendar: true,
            hasVisibleReminderData: true
        )

        XCTAssertEqual(resolved, .denied)
    }

    func testManagedCalendarIdentifierChangeResetsSnapshots() {
        XCTAssertTrue(
            TodayMdReminderSyncService.shouldResetSnapshots(
                currentIdentifier: "old-list",
                newIdentifier: "new-list"
            )
        )
        XCTAssertTrue(
            TodayMdReminderSyncService.shouldResetSnapshots(
                currentIdentifier: "old-list",
                newIdentifier: nil
            )
        )
    }

    func testManagedCalendarIdentifierStabilityKeepsSnapshots() {
        XCTAssertFalse(
            TodayMdReminderSyncService.shouldResetSnapshots(
                currentIdentifier: "same-list",
                newIdentifier: "same-list"
            )
        )
        XCTAssertFalse(
            TodayMdReminderSyncService.shouldResetSnapshots(
                currentIdentifier: nil,
                newIdentifier: nil
            )
        )
    }

    func testShouldAttachReturnsFalseForSameStore() {
        let store = TodayMdStore()

        XCTAssertFalse(TodayMdReminderSyncService.shouldAttach(currentStore: store, newStore: store))
    }

    func testShouldAttachReturnsTrueForDifferentStore() {
        XCTAssertTrue(
            TodayMdReminderSyncService.shouldAttach(
                currentStore: TodayMdStore(),
                newStore: TodayMdStore()
            )
        )
    }

    func testSyncRequestDispositionQueuesFollowUpWhenSyncIsInProgress() {
        XCTAssertEqual(
            TodayMdReminderSyncService.syncRequestDisposition(
                syncEnabled: true,
                isSyncInProgress: true
            ),
            .queueFollowUp
        )
    }

    func testSyncRequestDispositionSchedulesWhenEnabledAndIdle() {
        XCTAssertEqual(
            TodayMdReminderSyncService.syncRequestDisposition(
                syncEnabled: true,
                isSyncInProgress: false
            ),
            .schedule
        )
    }

    func testSyncRequestDispositionIgnoresWhenDisabled() {
        XCTAssertEqual(
            TodayMdReminderSyncService.syncRequestDisposition(
                syncEnabled: false,
                isSyncInProgress: true
            ),
            .ignore
        )
    }

    func testShouldScheduleFollowUpSyncRequiresPendingFlagAndEnabledSync() {
        XCTAssertTrue(
            TodayMdReminderSyncService.shouldScheduleFollowUpSync(
                syncEnabled: true,
                needsResyncAfterCurrentRun: true
            )
        )
        XCTAssertFalse(
            TodayMdReminderSyncService.shouldScheduleFollowUpSync(
                syncEnabled: false,
                needsResyncAfterCurrentRun: true
            )
        )
        XCTAssertFalse(
            TodayMdReminderSyncService.shouldScheduleFollowUpSync(
                syncEnabled: true,
                needsResyncAfterCurrentRun: false
            )
        )
    }

    func testLegacyReminderNotesAreStrippedAndMarkedForRefresh() {
        let taskID = UUID()
        let parsed = TodayMdReminderMetadata.parse(
            url: nil,
            notes: """
            today-md reminder

            Task ID: \(taskID.uuidString)

            Block: today

            List ID: \(UUID().uuidString)

            Pick up oat milk
            """,
            dueDateComponents: nil,
            fallback: nil,
            calendar: Calendar(identifier: .gregorian),
            referenceDate: Date(timeIntervalSinceReferenceDate: 0)
        )

        XCTAssertEqual(parsed.taskID, taskID)
        XCTAssertEqual(parsed.block, .today)
        XCTAssertEqual(parsed.visibleNote, "Pick up oat milk")
        XCTAssertTrue(parsed.needsMetadataRefresh)
    }

    func testDueDateMappingUsesTodayAndEndOfWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = Date(timeIntervalSince1970: 1_711_344_000) // 2024-03-25 00:00:00 UTC, Monday

        let todayComponents = TodayMdReminderMetadata.dueDateComponents(
            for: .today,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let thisWeekComponents = TodayMdReminderMetadata.dueDateComponents(
            for: .thisWeek,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let expectedEndOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            .flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }
        let expectedEndOfWeekComponents = expectedEndOfWeek.map {
            calendar.dateComponents([.year, .month, .day], from: $0)
        }

        XCTAssertEqual(todayComponents?.year, 2024)
        XCTAssertEqual(todayComponents?.month, 3)
        XCTAssertEqual(todayComponents?.day, 25)

        XCTAssertEqual(thisWeekComponents?.year, expectedEndOfWeekComponents?.year)
        XCTAssertEqual(thisWeekComponents?.month, expectedEndOfWeekComponents?.month)
        XCTAssertEqual(thisWeekComponents?.day, expectedEndOfWeekComponents?.day)
    }

    func testDueDateMappingPreservesScheduledTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scheduledDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 14, minute: 30))!
        let task = TodayMdReminderTaskSnapshot(
            id: UUID(),
            title: "Timed task",
            isDone: false,
            noteContent: nil,
            block: .today,
            listID: nil,
            creationDate: scheduledDate,
            modifiedDate: scheduledDate,
            scheduledDate: scheduledDate
        )

        let components = TodayMdReminderMetadata.dueDateComponents(for: task, calendar: calendar)

        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 3)
        XCTAssertEqual(components?.day, 27)
        XCTAssertEqual(components?.hour, 14)
        XCTAssertEqual(components?.minute, 30)
    }

    func testRemoteOnlyReminderImportsIntoUnassignedBacklogAndRefreshesMetadata() {
        let remoteTaskID = UUID()
        let remoteTask = TodayMdReminderTaskSnapshot(
            id: remoteTaskID,
            title: "Buy milk",
            isDone: false,
            noteContent: "2 liters",
            block: .backlog,
            listID: nil,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
        )
        let remoteRecord = TodayMdReminderRecord(
            identifier: "reminder-1",
            task: remoteTask,
            needsMetadataRefresh: true
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [], unassignedTasks: []),
            remoteRecords: [remoteRecord],
            snapshots: []
        )

        XCTAssertEqual(outcome.archive.unassignedTasks.count, 1)
        XCTAssertEqual(outcome.archive.unassignedTasks.first?.title, "Buy milk")
        XCTAssertEqual(outcome.archive.unassignedTasks.first?.blockRaw, TimeBlock.backlog.rawValue)

        guard case let .update(reminderIdentifier, task)? = outcome.mutations.first else {
            return XCTFail("Expected a metadata refresh update for the imported reminder.")
        }

        XCTAssertEqual(reminderIdentifier, "reminder-1")
        XCTAssertEqual(task.id, remoteTaskID)
    }

    func testLocalOnlyTaskCreatesReminder() {
        let task = TaskItem(
            id: UUID(),
            title: "Draft proposal",
            block: .today,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 15)
        )
        let archive = TodayMdArchive(lists: [], unassignedTasks: [task])

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: archive,
            remoteRecords: [],
            snapshots: []
        )

        guard case let .create(createdTask)? = outcome.mutations.first else {
            return XCTFail("Expected a create mutation for the unsynced local task.")
        }

        XCTAssertEqual(createdTask.id, task.id)
        XCTAssertEqual(createdTask.title, "Draft proposal")
    }

    func testMissingUnchangedReminderDeletesLocalTask() {
        let taskID = UUID()
        let task = TaskItem(
            id: taskID,
            title: "Unchanged",
            block: .today,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 10)
        )
        let archive = TodayMdArchive(lists: [], unassignedTasks: [task])
        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "reminder-unchanged",
            canonicalHash: TodayMdReminderTaskSnapshot(task: task).canonicalHash(),
            blockRaw: TimeBlock.today.rawValue,
            listID: nil
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: archive,
            remoteRecords: [],
            snapshots: [snapshot]
        )

        XCTAssertTrue(outcome.archive.unassignedTasks.isEmpty)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }

    func testConcurrentRemoteEditWinsWhenReminderIsNewer() {
        let taskID = UUID()
        let baseTask = TaskItem(
            id: taskID,
            title: "Original",
            block: .today,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 10)
        )
        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "reminder-2",
            canonicalHash: TodayMdReminderTaskSnapshot(task: baseTask).canonicalHash(),
            blockRaw: TimeBlock.today.rawValue,
            listID: nil
        )

        let locallyEditedTask = TaskItem(
            id: taskID,
            title: "Local edit",
            block: .today,
            creationDate: baseTask.creationDate,
            modifiedDate: Date(timeIntervalSinceReferenceDate: 12)
        )
        let remoteRecord = TodayMdReminderRecord(
            identifier: "reminder-2",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: "Remote edit",
                isDone: false,
                noteContent: nil,
                block: .today,
                listID: nil,
                creationDate: baseTask.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
            ),
            needsMetadataRefresh: false
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [], unassignedTasks: [locallyEditedTask]),
            remoteRecords: [remoteRecord],
            snapshots: [snapshot]
        )

        XCTAssertEqual(outcome.archive.unassignedTasks.first?.title, "Remote edit")
        XCTAssertTrue(outcome.mutations.isEmpty)
    }

    func testRemoteEditsDoNotReassignExistingTaskList() {
        let taskID = UUID()
        let list = TaskList(name: "Work")
        let task = TaskItem(
            id: taskID,
            title: "Review PR",
            block: .today,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 10)
        )
        task.list = list
        list.items = [task]

        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "reminder-3",
            canonicalHash: TodayMdReminderTaskSnapshot(task: task).canonicalHash(),
            blockRaw: TimeBlock.today.rawValue,
            listID: list.id
        )
        let remoteRecord = TodayMdReminderRecord(
            identifier: "reminder-3",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: "Review launch checklist",
                isDone: false,
                noteContent: nil,
                block: .thisWeek,
                listID: nil,
                creationDate: task.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
            ),
            needsMetadataRefresh: false
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [list], unassignedTasks: []),
            remoteRecords: [remoteRecord],
            snapshots: [snapshot]
        )
        let hydrated = outcome.archive.instantiate()

        XCTAssertEqual(hydrated.lists.first?.items.first?.title, "Review launch checklist")
        XCTAssertEqual(hydrated.lists.first?.items.first?.blockRaw, TimeBlock.thisWeek.rawValue)
        XCTAssertEqual(hydrated.lists.first?.items.first?.list?.id, list.id)
        XCTAssertTrue(hydrated.unassignedTasks.isEmpty)
    }

    func testRemoteScheduleChangeUpdatesExistingTaskSchedule() {
        let taskID = UUID()
        let originalScheduledDate = Date(timeIntervalSinceReferenceDate: 100)
        let updatedScheduledDate = Date(timeIntervalSinceReferenceDate: 200)
        let task = TaskItem(
            id: taskID,
            title: "Book dentist",
            block: .today,
            schedulingState: .scheduled,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 10),
            scheduledDate: originalScheduledDate
        )
        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "reminder-schedule-change",
            canonicalHash: TodayMdReminderTaskSnapshot(task: task).canonicalHash(),
            blockRaw: TimeBlock.today.rawValue,
            listID: nil,
            scheduledDate: originalScheduledDate
        )
        let remoteRecord = TodayMdReminderRecord(
            identifier: "reminder-schedule-change",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: task.title,
                isDone: false,
                noteContent: nil,
                block: .thisWeek,
                listID: nil,
                creationDate: task.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20),
                scheduledDate: updatedScheduledDate
            ),
            needsMetadataRefresh: false
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [], unassignedTasks: [task]),
            remoteRecords: [remoteRecord],
            snapshots: [snapshot]
        )
        let hydrated = outcome.archive.instantiate()

        XCTAssertEqual(hydrated.unassignedTasks.first?.scheduledDate, updatedScheduledDate)
        XCTAssertEqual(hydrated.unassignedTasks.first?.schedulingState, .scheduled)
        XCTAssertEqual(hydrated.unassignedTasks.first?.blockRaw, TimeBlock.thisWeek.rawValue)
    }

    func testSnapshotBackedRemoteReminderRehydratesIntoOriginalList() {
        let taskID = UUID()
        let list = TaskList(name: "Private")
        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "reminder-restore-list",
            canonicalHash: "snapshot-hash",
            blockRaw: TimeBlock.today.rawValue,
            listID: list.id
        )
        let remoteRecord = TodayMdReminderRecord(
            identifier: "reminder-restore-list",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: "Plan weekend trip",
                isDone: false,
                noteContent: "Book train",
                block: .today,
                listID: list.id,
                creationDate: Date(timeIntervalSinceReferenceDate: 10),
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
            ),
            needsMetadataRefresh: false
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [list], unassignedTasks: []),
            remoteRecords: [remoteRecord],
            snapshots: [snapshot]
        )
        let hydrated = outcome.archive.instantiate()

        XCTAssertEqual(hydrated.lists.first?.items.count, 1)
        XCTAssertEqual(hydrated.lists.first?.items.first?.title, "Plan weekend trip")
        XCTAssertEqual(hydrated.lists.first?.items.first?.list?.id, list.id)
        XCTAssertTrue(hydrated.unassignedTasks.isEmpty)
    }

    func testDuplicateRemoteTaskIDsPreferNewestRecordInsteadOfCrashing() {
        let taskID = UUID()
        let localTask = TaskItem(
            id: taskID,
            title: "Original",
            block: .today,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 10)
        )
        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "stale-reminder-id",
            canonicalHash: TodayMdReminderTaskSnapshot(task: localTask).canonicalHash(),
            blockRaw: TimeBlock.today.rawValue,
            listID: nil
        )
        let olderRemoteRecord = TodayMdReminderRecord(
            identifier: "reminder-older",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: "Older remote",
                isDone: false,
                noteContent: nil,
                block: .today,
                listID: nil,
                creationDate: localTask.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
            ),
            needsMetadataRefresh: false
        )
        let newerRemoteRecord = TodayMdReminderRecord(
            identifier: "reminder-newer",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: "Newest remote",
                isDone: false,
                noteContent: nil,
                block: .thisWeek,
                listID: nil,
                creationDate: localTask.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 30)
            ),
            needsMetadataRefresh: false
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [], unassignedTasks: [localTask]),
            remoteRecords: [olderRemoteRecord, newerRemoteRecord],
            snapshots: [snapshot]
        )

        XCTAssertEqual(outcome.archive.unassignedTasks.first?.title, "Newest remote")
        XCTAssertEqual(outcome.archive.unassignedTasks.first?.blockRaw, TimeBlock.thisWeek.rawValue)
        XCTAssertFalse(outcome.mutations.contains { mutation in
            if case .create = mutation {
                return true
            }
            return false
        })
    }

    func testNewerMarkdownNoteBeatsOlderReminderCopy() {
        let taskID = UUID()
        let task = TaskItem(
            id: taskID,
            title: "Review onboarding polish PR",
            block: .today,
            creationDate: Date(timeIntervalSinceReferenceDate: 10),
            modifiedDate: Date(timeIntervalSinceReferenceDate: 10),
            note: TaskNote(
                content: """
                - [x] Verify empty states
                - [ ] Check keyboard shortcuts
                - [ ] Confirm analytics events
                """,
                lastModified: Date(timeIntervalSinceReferenceDate: 30)
            )
        )
        let snapshot = TodayMdReminderSyncSnapshot(
            taskID: taskID,
            reminderIdentifier: "reminder-4",
            canonicalHash: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: task.title,
                isDone: false,
                noteContent: "Older reminder body",
                block: .today,
                listID: nil,
                creationDate: task.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
            ).canonicalHash(),
            blockRaw: TimeBlock.today.rawValue,
            listID: nil
        )
        let remoteRecord = TodayMdReminderRecord(
            identifier: "reminder-4",
            task: TodayMdReminderTaskSnapshot(
                id: taskID,
                title: task.title,
                isDone: false,
                noteContent: "Older reminder body",
                block: .today,
                listID: nil,
                creationDate: task.creationDate,
                modifiedDate: Date(timeIntervalSinceReferenceDate: 20)
            ),
            needsMetadataRefresh: false
        )

        let outcome = TodayMdReminderSyncEngine.sync(
            localArchive: TodayMdArchive(lists: [], unassignedTasks: [task]),
            remoteRecords: [remoteRecord],
            snapshots: [snapshot]
        )

        guard case let .update(reminderIdentifier, updatedTask)? = outcome.mutations.first else {
            return XCTFail("Expected local markdown note to win and push an update to Reminders.")
        }

        XCTAssertEqual(reminderIdentifier, "reminder-4")
        XCTAssertEqual(updatedTask.noteContent, task.note?.content)
        XCTAssertEqual(outcome.archive.unassignedTasks.first?.note?.content, task.note?.content)
    }
}
