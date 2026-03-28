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

    func testNewUnassignedTasksAreInsertedAtTopOfBlock() throws {
        let store = try makeStore()

        let first = store.addUnassignedTask(title: "First", block: .today)
        let second = store.addUnassignedTask(title: "Second", block: .today)

        let tasks = store.allTasks.filter { $0.block == .today }
        XCTAssertEqual(tasks.map(\.title), ["Second", "First"])
        XCTAssertEqual(second.sortOrder, 0)
        XCTAssertEqual(first.sortOrder, 1)
    }

    func testNewListTasksAreInsertedAtTopOfBlock() throws {
        let store = try makeStore()
        let list = store.addList(name: "Work", icon: "briefcase", color: .blue)

        let first = try XCTUnwrap(store.addTask(title: "First", block: .today, listID: list.id))
        let second = try XCTUnwrap(store.addTask(title: "Second", block: .today, listID: list.id))

        let tasks = list.items
            .filter { $0.block == .today }
            .sorted(by: taskSort)
        XCTAssertEqual(tasks.map(\.title), ["Second", "First"])
        XCTAssertEqual(second.sortOrder, 0)
        XCTAssertEqual(first.sortOrder, 1)
    }

    func testNewerTaskWinsGlobalOrderingWhenSortOrdersMatch() throws {
        let store = try makeStore()
        let list = store.addList(name: "Work", icon: "briefcase", color: .blue)

        let older = try XCTUnwrap(store.addTask(title: "Older", block: .today, listID: list.id))
        older.sortOrder = 0
        older.creationDate = Date(timeIntervalSinceReferenceDate: 100)

        let newer = store.addUnassignedTask(title: "Newer", block: .today)
        newer.sortOrder = 0
        newer.creationDate = Date(timeIntervalSinceReferenceDate: 200)

        let tasks = store.allTasks.filter { $0.block == .today }
        XCTAssertEqual(tasks.map(\.title), ["Newer", "Older"])
    }

    func testQuickAddTaskTrimsWhitespaceBeforeCreatingTodayTask() throws {
        let store = try makeStore()

        let task = try XCTUnwrap(store.quickAddTask(title: "  Inbox task  ", to: .today))

        XCTAssertEqual(task.title, "Inbox task")
        XCTAssertEqual(task.block, .today)
        XCTAssertEqual(store.unassignedTasks.map(\.id), [task.id])
    }

    func testQuickAddTaskCanCreateTaskInSelectedList() throws {
        let store = try makeStore()
        let list = store.addList(name: "Work", icon: "briefcase", color: .blue)

        let task = try XCTUnwrap(store.quickAddTask(title: "  Inbox task  ", to: .today, listID: list.id))

        XCTAssertEqual(task.title, "Inbox task")
        XCTAssertEqual(task.block, .today)
        XCTAssertEqual(task.list?.id, list.id)
        XCTAssertEqual(list.items.map(\.id), [task.id])
    }

    func testQuickAddTaskRejectsBlankTitles() throws {
        let store = try makeStore()

        let task = store.quickAddTask(title: " \n\t ", to: .today)

        XCTAssertNil(task)
        XCTAssertTrue(store.allTasks.isEmpty)
    }

    func testQuickAddTaskRejectsUnknownListID() throws {
        let store = try makeStore()

        let task = store.quickAddTask(title: "Inbox task", to: .today, listID: UUID())

        XCTAssertNil(task)
        XCTAssertTrue(store.allTasks.isEmpty)
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

    func testTaskVisibilityScopeFiltersTasksToSelectedList() throws {
        let store = try makeStore()
        let work = store.addList(name: "Work", icon: "briefcase", color: .blue)
        let personal = store.addList(name: "Personal", icon: "person", color: .green)

        let workTask = try XCTUnwrap(store.addTask(title: "Work task", block: .today, listID: work.id))
        _ = try XCTUnwrap(store.addTask(title: "Personal task", block: .today, listID: personal.id))
        _ = store.addUnassignedTask(title: "Inbox task", block: .today)

        let visibleTasks = TaskVisibilityScope.tasks(for: .list(work.id), store: store)

        XCTAssertEqual(visibleTasks.map(\.id), [workTask.id])
    }

    func testAssignTaskPreservesPositionWhenMovingIntoList() throws {
        let store = try makeStore()
        let list = store.addList(name: "Work", icon: "briefcase", color: .blue)

        _ = try XCTUnwrap(store.addTask(title: "Dest second", block: .today, listID: list.id))
        let destinationTop = try XCTUnwrap(store.addTask(title: "Dest top", block: .today, listID: list.id))

        let taskToMove = store.addUnassignedTask(title: "Move me", block: .today)
        _ = store.addUnassignedTask(title: "Stay above", block: .today)

        XCTAssertEqual(taskToMove.sortOrder, 1)
        XCTAssertEqual(destinationTop.sortOrder, 0)

        store.assignTask(id: taskToMove.id, toListID: list.id)

        let tasks = list.items
            .filter { $0.block == .today }
            .sorted(by: taskSort)
        XCTAssertEqual(tasks.map(\.title), ["Dest top", "Move me", "Dest second"])
    }

    func testAssignTaskPreservesPositionWhenMovingToUnassigned() throws {
        let store = try makeStore()
        let sourceList = store.addList(name: "Work", icon: "briefcase", color: .blue)

        _ = try XCTUnwrap(store.addTask(title: "Source second", block: .today, listID: sourceList.id))
        let taskToMove = try XCTUnwrap(store.addTask(title: "Move me", block: .today, listID: sourceList.id))

        _ = store.addUnassignedTask(title: "Unassigned second", block: .today)
        let unassignedTop = store.addUnassignedTask(title: "Unassigned top", block: .today)

        XCTAssertEqual(taskToMove.sortOrder, 0)
        XCTAssertEqual(unassignedTop.sortOrder, 0)

        store.assignTask(id: taskToMove.id, toListID: nil)

        let tasks = store.allTasks
            .filter { $0.list == nil && $0.block == .today }
            .sorted(by: taskSort)
        XCTAssertEqual(tasks.map(\.title), ["Move me", "Unassigned top", "Unassigned second"])
    }

    func testAssignTaskBetweenListsPreservesGlobalAllTasksPosition() throws {
        let store = try makeStore()
        let work = store.addList(name: "Work", icon: "briefcase", color: .blue)
        let privateList = store.addList(name: "Private", icon: "person", color: .green)

        let workBottom = try XCTUnwrap(store.addTask(title: "Work bottom", block: .today, listID: work.id))
        let moveMe = try XCTUnwrap(store.addTask(title: "Move me", block: .today, listID: work.id))
        let workTop = try XCTUnwrap(store.addTask(title: "Work top", block: .today, listID: work.id))

        let privateSecond = try XCTUnwrap(store.addTask(title: "Private second", block: .today, listID: privateList.id))
        let privateTop = try XCTUnwrap(store.addTask(title: "Private top", block: .today, listID: privateList.id))

        workTop.creationDate = Date(timeIntervalSinceReferenceDate: 100)
        privateTop.creationDate = Date(timeIntervalSinceReferenceDate: 50)
        moveMe.creationDate = Date(timeIntervalSinceReferenceDate: 200)
        privateSecond.creationDate = Date(timeIntervalSinceReferenceDate: 150)
        workBottom.creationDate = Date(timeIntervalSinceReferenceDate: 300)

        let beforeTasks = store.allTasks.filter { $0.block == .today }
        let beforeIndex = try XCTUnwrap(beforeTasks.firstIndex(where: { $0.id == moveMe.id }))
        XCTAssertEqual(beforeTasks.map(\.title), ["Work top", "Private top", "Move me", "Private second", "Work bottom"])

        store.assignTask(id: moveMe.id, toListID: privateList.id)

        let afterTasks = store.allTasks.filter { $0.block == .today }
        let afterIndex = try XCTUnwrap(afterTasks.firstIndex(where: { $0.id == moveMe.id }))
        XCTAssertEqual(afterTasks.map(\.title), ["Work top", "Private top", "Move me", "Work bottom", "Private second"])
        XCTAssertEqual(afterIndex, beforeIndex)
    }

    func testMoveActiveTaskOnBoardMovesTaskIntoTargetLaneBeforeDroppedTask() throws {
        let store = try makeStore()

        let todayBottom = store.addUnassignedTask(title: "Today bottom", block: .today)
        _ = store.addUnassignedTask(title: "Today top", block: .today)
        let moveMe = store.addUnassignedTask(title: "Move me", block: .backlog)

        store.moveActiveTaskOnBoard(moveMe.id, to: .today, before: todayBottom.id)

        XCTAssertEqual(moveMe.block, .today)
        let todayTasks = store.allTasks
            .filter { $0.block == .today && !$0.isDone }
            .sorted(by: taskSort)
        XCTAssertEqual(todayTasks.map(\.title), ["Today top", "Move me", "Today bottom"])
    }

    func testMoveActiveTaskOnBoardAppendsTaskToTargetLaneWhenDroppedPastLastCard() throws {
        let store = try makeStore()

        _ = store.addUnassignedTask(title: "Today bottom", block: .today)
        _ = store.addUnassignedTask(title: "Today top", block: .today)
        let moveMe = store.addUnassignedTask(title: "Move me", block: .backlog)

        store.moveActiveTaskOnBoard(moveMe.id, to: .today, before: nil)

        XCTAssertEqual(moveMe.block, .today)
        let todayTasks = store.allTasks
            .filter { $0.block == .today && !$0.isDone }
            .sorted(by: taskSort)
        XCTAssertEqual(todayTasks.map(\.title), ["Today top", "Today bottom", "Move me"])
    }

    func testFlushPendingPersistencePersistsDeferredMove() throws {
        let databaseURL = try makeDatabaseURL()
        let store = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        let task = store.addUnassignedTask(title: "Move me", block: .backlog)

        store.moveTask(id: task.id, to: .today)
        store.flushPendingPersistence()

        let reloaded = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        let persistedTask = try XCTUnwrap(reloaded.allTasks.first(where: { $0.id == task.id }))
        XCTAssertEqual(persistedTask.block, .today)
    }

    func testMoveTaskUnschedulesTaskWhenChangingLane() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Scheduled task", block: .thisWeek)
        store.setTaskSchedulingState(id: task.id, isScheduled: true)

        store.moveTask(id: task.id, to: .today)

        XCTAssertEqual(task.block, .today)
        XCTAssertFalse(task.isScheduled)
    }

    func testMoveActiveTaskOnBoardUnschedulesTaskWhenChangingLane() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Scheduled task", block: .thisWeek)
        store.setTaskSchedulingState(id: task.id, isScheduled: true)

        store.moveActiveTaskOnBoard(task.id, to: .today, before: nil)

        XCTAssertEqual(task.block, .today)
        XCTAssertFalse(task.isScheduled)
    }

    func testMoveActiveTaskOnBoardTouchesMovedTask() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Move me", block: .backlog)
        let originalModifiedDate = task.modifiedDate

        Thread.sleep(forTimeInterval: 0.01)
        store.moveActiveTaskOnBoard(task.id, to: .today, before: nil)

        XCTAssertGreaterThan(task.modifiedDate, originalModifiedDate)
    }

    func testReorderTaskInListBlockTouchesMovedTask() throws {
        let store = try makeStore()
        let list = store.addList(name: "Work", icon: "briefcase", color: .blue)
        let task = try XCTUnwrap(store.addTask(title: "Move me", block: .backlog, listID: list.id))
        let originalModifiedDate = task.modifiedDate

        Thread.sleep(forTimeInterval: 0.01)
        store.reorderTaskInListBlock(listID: list.id, draggedID: task.id, block: .today, before: nil)

        XCTAssertGreaterThan(task.modifiedDate, originalModifiedDate)
    }

    func testSyncTaskBlockWithScheduledDateMovesTaskToTodayForTodayDate() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Inbox task", block: .backlog)

        store.syncTaskBlockWithScheduledDate(id: task.id, scheduledDate: Date())

        XCTAssertEqual(task.block, .today)
        XCTAssertTrue(task.isScheduled)
    }

    func testSyncTaskBlockWithScheduledDateStoresExactScheduledDate() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Inbox task", block: .backlog)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scheduledDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 14, minute: 30))
        )

        store.syncTaskBlockWithScheduledDate(id: task.id, scheduledDate: scheduledDate, calendar: calendar)

        XCTAssertEqual(task.scheduledDate, scheduledDate)
        XCTAssertTrue(task.isScheduled)
    }

    func testSyncTaskBlockWithScheduledDateMovesTaskToThisWeekForDateInCurrentWeek() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Inbox task", block: .today)
        let calendar = Calendar.current
        let currentWeek = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        let dateInCurrentWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentWeek.start))

        store.syncTaskBlockWithScheduledDate(id: task.id, scheduledDate: dateInCurrentWeek, calendar: calendar)

        XCTAssertEqual(task.block, .thisWeek)
        XCTAssertTrue(task.isScheduled)
    }

    func testSyncTaskBlockWithScheduledDateMovesTaskToThisWeekForTomorrowAcrossWeekBoundary() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Inbox task", block: .today)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2

        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 10)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 10)))

        store.syncTaskBlockWithScheduledDate(
            id: task.id,
            scheduledDate: monday,
            calendar: calendar,
            referenceDate: sunday
        )

        XCTAssertEqual(task.block, .thisWeek)
        XCTAssertTrue(task.isScheduled)
    }

    func testSyncTaskBlockWithScheduledDateMovesTaskToBacklogForDateInNextWeek() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Inbox task", block: .today)
        let calendar = Calendar.current
        let currentWeek = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        let dateInNextWeek = currentWeek.end

        store.syncTaskBlockWithScheduledDate(id: task.id, scheduledDate: dateInNextWeek, calendar: calendar)

        XCTAssertEqual(task.block, .backlog)
        XCTAssertTrue(task.isScheduled)
    }

    func testPromoteScheduledTasksToTodayPreservesSchedulingState() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Scheduled task", block: .thisWeek)
        store.setTaskSchedulingState(id: task.id, isScheduled: true)

        store.promoteScheduledTasksToToday(ids: Set([task.id]))

        XCTAssertEqual(task.block, .today)
        XCTAssertTrue(task.isScheduled)
    }

    func testSetTaskSchedulingStatePersistsScheduledFlag() throws {
        let databaseURL = try makeDatabaseURL()
        let store = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        let task = store.addUnassignedTask(title: "Inbox task", block: .backlog)

        store.setTaskSchedulingState(id: task.id, isScheduled: true)
        store.flushPendingPersistence()

        let reloaded = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        let persistedTask = try XCTUnwrap(reloaded.allTasks.first(where: { $0.id == task.id }))
        XCTAssertTrue(persistedTask.isScheduled)
    }

    func testSetTaskSchedulingStateClearsScheduledFlag() throws {
        let store = try makeStore()
        let task = store.addUnassignedTask(title: "Inbox task", block: .backlog)

        store.setTaskSchedulingState(id: task.id, isScheduled: true)
        store.setTaskSchedulingState(id: task.id, isScheduled: false)

        XCTAssertFalse(task.isScheduled)
    }

    func testMarkdownAutoContinuationCreatesChecklistFromInitialEmptyItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "- [ ]", new: "- [ ]\n"),
            MarkdownAutoContinuation.Edit(
                text: "- [ ]\n- [ ] ",
                cursorLocation: ("- [ ]\n- [ ] " as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationKeepsChecklistMarkerOnNonEmptyItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "- [ ] Ship update", new: "- [ ] Ship update\n"),
            MarkdownAutoContinuation.Edit(
                text: "- [ ] Ship update\n- [ ] ",
                cursorLocation: ("- [ ] Ship update\n- [ ] " as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationExitsChecklistOnSecondEmptyItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "- [ ]\n- [ ] ", new: "- [ ]\n- [ ] \n"),
            MarkdownAutoContinuation.Edit(
                text: "- [ ]\n\n",
                cursorLocation: ("- [ ]\n\n" as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationCreatesBulletFromInitialEmptyItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "- ", new: "- \n"),
            MarkdownAutoContinuation.Edit(
                text: "- \n- ",
                cursorLocation: ("- \n- " as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationKeepsBulletMarkerOnNonEmptyItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "- agenda", new: "- agenda\n"),
            MarkdownAutoContinuation.Edit(
                text: "- agenda\n- ",
                cursorLocation: ("- agenda\n- " as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationExitsBulletOnSecondEmptyItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "- \n- ", new: "- \n- \n"),
            MarkdownAutoContinuation.Edit(
                text: "- \n\n",
                cursorLocation: ("- \n\n" as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationAdvancesNumberedList() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "1. First", new: "1. First\n"),
            MarkdownAutoContinuation.Edit(
                text: "1. First\n2. ",
                cursorLocation: ("1. First\n2. " as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationAdvancesEmptyInitialNumberedListItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "1. ", new: "1. \n"),
            MarkdownAutoContinuation.Edit(
                text: "1. \n2. ",
                cursorLocation: ("1. \n2. " as NSString).length
            )
        )
    }

    func testMarkdownAutoContinuationAdvancesToThirdNumberedListItem() {
        XCTAssertEqual(
            MarkdownAutoContinuation.edit(old: "1. First\n2. Second", new: "1. First\n2. Second\n"),
            MarkdownAutoContinuation.Edit(
                text: "1. First\n2. Second\n3. ",
                cursorLocation: ("1. First\n2. Second\n3. " as NSString).length
            )
        )
    }

    func testMarkdownListFormattingNumbersSelectedLines() {
        XCTAssertEqual(
            MarkdownListFormatting.numberLines(in: "First\nSecond\nThird"),
            "1. First\n2. Second\n3. Third"
        )
    }

    func testMarkdownListFormattingUsesPreviousNumberForNewLine() {
        XCTAssertEqual(
            MarkdownListFormatting.nextNumberedListPrefix(in: "1. First\n2. Second\n", at: ("1. First\n2. Second\n" as NSString).length),
            "3. "
        )
    }

    func testMarkdownListFormattingIndentsBulletListItem() {
        XCTAssertEqual(
            MarkdownListFormatting.indentListLines(
                in: "• Ship update",
                selection: NSRange(location: ("• " as NSString).length, length: 0)
            ),
            MarkdownListFormatting.Edit(
                text: "    • Ship update",
                selection: NSRange(location: ("    • " as NSString).length, length: 0)
            )
        )
    }

    func testMarkdownListFormattingCapsIndentAtThreeLevels() {
        XCTAssertNil(
            MarkdownListFormatting.indentListLines(
                in: "            • Ship update",
                selection: NSRange(location: ("            • " as NSString).length, length: 0)
            )
        )
    }

    func testMarkdownListFormattingIndentsSelectedListLinesOnly() {
        XCTAssertEqual(
            MarkdownListFormatting.indentListLines(
                in: "• First\nPlain paragraph\n☐ Second",
                selection: NSRange(location: 0, length: ("• First\nPlain paragraph\n☐ Second" as NSString).length)
            ),
            MarkdownListFormatting.Edit(
                text: "    • First\nPlain paragraph\n    ☐ Second",
                selection: NSRange(
                    location: 0,
                    length: ("    • First\nPlain paragraph\n    ☐ Second" as NSString).length
                )
            )
        )
    }

    func testMarkdownListFormattingOutdentsListItem() {
        XCTAssertEqual(
            MarkdownListFormatting.outdentListLines(
                in: "        • Ship update",
                selection: NSRange(location: ("        • " as NSString).length, length: 0)
            ),
            MarkdownListFormatting.Edit(
                text: "    • Ship update",
                selection: NSRange(location: ("    • " as NSString).length, length: 0)
            )
        )
    }

    func testMarkdownInlineDisplayRendersChecklistAndBullets() {
        XCTAssertEqual(
            MarkdownInlineDisplay.display(from: "- [ ] Ship update\n- Prep release\n* Follow up"),
            "☐ Ship update\n• Prep release\n• Follow up"
        )
    }

    func testMarkdownInlineDisplayDoesNotRenderBareHyphenAsBullet() {
        XCTAssertEqual(
            MarkdownInlineDisplay.display(from: "-"),
            "-"
        )
    }

    func testMarkdownInlineDisplayKeepsDividerMarkdownIntact() {
        XCTAssertEqual(
            MarkdownInlineDisplay.display(from: "---"),
            "---"
        )
    }

    func testMarkdownInlineDisplayRecognizesDividerSyntax() {
        XCTAssertTrue(MarkdownInlineDisplay.isDividerMarkdownLine("---"))
        XCTAssertTrue(MarkdownInlineDisplay.isDividerMarkdownLine(" *** "))
        XCTAssertTrue(MarkdownInlineDisplay.isDividerMarkdownLine("___"))
        XCTAssertFalse(MarkdownInlineDisplay.isDividerMarkdownLine("--"))
        XCTAssertFalse(MarkdownInlineDisplay.isDividerMarkdownLine("- "))
    }

    func testMarkdownInlineDisplayNormalizesLegacyRenderedChecklistWithoutSpace() {
        XCTAssertEqual(
            MarkdownInlineDisplay.display(from: "☐Ship update"),
            "☐ Ship update"
        )
        XCTAssertEqual(
            MarkdownInlineDisplay.markdown(from: "☐Ship update"),
            "- [ ] Ship update"
        )
    }

    func testMarkdownInlineDisplayNormalizesLegacyRenderedBulletWithoutSpace() {
        XCTAssertEqual(
            MarkdownInlineDisplay.display(from: "•Ship update"),
            "• Ship update"
        )
        XCTAssertEqual(
            MarkdownInlineDisplay.markdown(from: "•Ship update"),
            "- Ship update"
        )
    }

    func testMarkdownInlineDisplayConvertsRenderedMarkersBackToMarkdown() {
        XCTAssertEqual(
            MarkdownInlineDisplay.markdown(from: "☐ Ship update\n• Prep release\n☑ Done"),
            "- [ ] Ship update\n- Prep release\n- [x] Done"
        )
    }

    func testMarkdownInlineDisplayCanonicalizesLegacyMarkdownSpacing() {
        XCTAssertEqual(
            MarkdownInlineDisplay.canonicalMarkdown(from: "- [X]Ship\n*  Bullet\n1.Test"),
            "- [x] Ship\n- Bullet\n1. Test"
        )
    }

    func testMarkdownInlineDisplayNormalizesTypedChecklistMarkerAndSelection() {
        let state = MarkdownInlineDisplay.normalizeEditorState(
            text: "- [ ] ",
            selection: NSRange(location: ("- [ ] " as NSString).length, length: 0)
        )

        XCTAssertEqual(state.text, "☐ ")
        XCTAssertEqual(state.markdown, "- [ ] ")
        XCTAssertEqual(state.selection, NSRange(location: ("☐ " as NSString).length, length: 0))
    }

    func testMarkdownInlineDisplayMapsChecklistAutoContinuationBackToRenderedText() {
        XCTAssertEqual(
            MarkdownInlineDisplay.editForAutoContinuation(
                oldDisplay: "☐ Ship update",
                newDisplay: "☐ Ship update\n"
            ),
            MarkdownAutoContinuation.Edit(
                text: "☐ Ship update\n☐ ",
                cursorLocation: ("☐ Ship update\n☐ " as NSString).length
            )
        )
    }

    func testMarkdownInlineDisplayMapsChecklistAutoContinuationForLegacyCRLFText() {
        XCTAssertEqual(
            MarkdownInlineDisplay.editForAutoContinuation(
                oldDisplay: "☐ Ship update\r\n☐ asdsa",
                newDisplay: "☐ Ship update\r\n☐ asdsa\n"
            ),
            MarkdownAutoContinuation.Edit(
                text: "☐ Ship update\n☐ asdsa\n☐ ",
                cursorLocation: ("☐ Ship update\n☐ asdsa\n☐ " as NSString).length
            )
        )
    }

    func testMarkdownInlineDisplayMapsBulletAutoContinuationBackToRenderedText() {
        XCTAssertEqual(
            MarkdownInlineDisplay.editForAutoContinuation(
                oldDisplay: "• Ship update",
                newDisplay: "• Ship update\n"
            ),
            MarkdownAutoContinuation.Edit(
                text: "• Ship update\n• ",
                cursorLocation: ("• Ship update\n• " as NSString).length
            )
        )
    }

    func testMarkdownInlineDisplayMapsOrderedListAutoContinuationBackToRenderedText() {
        XCTAssertEqual(
            MarkdownInlineDisplay.editForAutoContinuation(
                oldDisplay: "1. Ship update",
                newDisplay: "1. Ship update\n"
            ),
            MarkdownAutoContinuation.Edit(
                text: "1. Ship update\n2. ",
                cursorLocation: ("1. Ship update\n2. " as NSString).length
            )
        )
    }

    func testMarkdownInlineDisplayMapsChecklistAutoContinuationWithinLegacyMultilineNote() {
        let oldDisplay = """
        1. a

        • 

        ☐ asdsad
        ☐ asd
        ☐ asd
        """

        let newDisplay = """
        1. a

        • 

        ☐ asdsad
        ☐ asd
        ☐ asd
        
        """

        XCTAssertEqual(
            MarkdownInlineDisplay.editForAutoContinuation(oldDisplay: oldDisplay, newDisplay: newDisplay),
            MarkdownAutoContinuation.Edit(
                text: """
                1. a

                • 

                ☐ asdsad
                ☐ asd
                ☐ asd
                ☐ 
                """,
                cursorLocation: 33
            )
        )
    }

    func testMarkdownInlineDisplayContinuesChecklistFromCaretWithinOlderLoadedNote() {
        let display = """
        Huffman, Keith <keith.huffman@sap.com>

        # asdasd
        ☐ asda

        ☐ asdasd
        """

        let offset = ("Huffman, Keith <keith.huffman@sap.com>\n\n# asdasd\n☐ asda" as NSString).length

        XCTAssertEqual(
            MarkdownInlineDisplay.editForInsertedNewline(in: display, atEditorOffset: offset),
            MarkdownAutoContinuation.Edit(
                text: """
                Huffman, Keith <keith.huffman@sap.com>

                # asdasd
                ☐ asda
                ☐ 

                ☐ asdasd
                """,
                cursorLocation: ("Huffman, Keith <keith.huffman@sap.com>\n\n# asdasd\n☐ asda\n☐ " as NSString).length
            )
        )
    }

    func testMarkdownInlineDisplayContinuesChecklistFromCaretForLegacyEmptyChecklistBlock() {
        let display = """
        ☐ 
        ☐ asd
        ☐ asd
        ☐ 
        """

        let offset = ("☐ \n☐ asd" as NSString).length

        XCTAssertEqual(
            MarkdownInlineDisplay.editForInsertedNewline(in: display, atEditorOffset: offset),
            MarkdownAutoContinuation.Edit(
                text: """
                ☐ 
                ☐ asd
                ☐ 
                ☐ asd
                ☐ 
                """,
                cursorLocation: ("☐ \n☐ asd\n☐ " as NSString).length
            )
        )
    }

    func testMarkdownInlineDisplayTogglesChecklistFromUncheckedToChecked() {
        XCTAssertEqual(
            MarkdownInlineDisplay.toggledCheckbox(in: "☐ Ship update", atEditorOffset: 0),
            "☑ Ship update"
        )
    }

    func testMarkdownInlineDisplayTogglesChecklistFromCheckedToUnchecked() {
        XCTAssertEqual(
            MarkdownInlineDisplay.toggledCheckbox(in: "☑ Ship update", atEditorOffset: 0),
            "☐ Ship update"
        )
    }

    func testStoreNormalizesLegacyNoteMarkdownWhenReloaded() throws {
        let databaseURL = try makeDatabaseURL()
        let store = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        let task = store.addUnassignedTask(title: "Legacy", block: .today)
        store.updateTaskNote(id: task.id, content: "- [X]Ship\n*  Bullet\n1.Test")

        let reloaded = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        let reloadedTask = try XCTUnwrap(reloaded.allTasks.first(where: { $0.id == task.id }))
        XCTAssertEqual(reloadedTask.note?.content, "- [x] Ship\n- Bullet\n1. Test")
    }

    func testApplyRemoteArchiveNormalizesLegacyNoteMarkdown() throws {
        let store = try makeStore()
        let taskID = UUID()
        let archive = TodayMdArchive(
            lists: [],
            unassignedTasks: [
                .init(
                    id: taskID,
                    title: "Remote legacy",
                    isDone: false,
                    blockRaw: TimeBlock.today.rawValue,
                    sortOrder: 0,
                    creationDate: Date(),
                    note: .init(content: "- [X]Ship\n*  Bullet\n1.Test", lastModified: Date()),
                    subtasks: []
                )
            ]
        )

        store.applyRemoteArchive(archive)

        let task = try XCTUnwrap(store.allTasks.first(where: { $0.id == taskID }))
        XCTAssertEqual(task.note?.content, "- [x] Ship\n- Bullet\n1. Test")
    }

    func testApplyRemoteArchivePreservesChecklistMarkdownWhenLegacySubtasksExist() throws {
        let store = try makeStore()
        let taskID = UUID()
        let archive = TodayMdArchive(
            lists: [],
            unassignedTasks: [
                .init(
                    id: taskID,
                    title: "Remote reminder task",
                    isDone: false,
                    blockRaw: TimeBlock.today.rawValue,
                    sortOrder: 0,
                    creationDate: Date(),
                    note: .init(
                        content: """
                        Keep this lightweight and easy to book.

                        - [ ] Test
                        - [ ] to obsidian
                        """,
                        lastModified: Date()
                    ),
                    subtasks: [
                        .init(id: UUID(), title: "Test", isCompleted: false, sortOrder: 0),
                        .init(id: UUID(), title: "to obsidian", isCompleted: false, sortOrder: 1)
                    ]
                )
            ]
        )

        store.applyRemoteArchive(archive)

        let task = try XCTUnwrap(store.allTasks.first(where: { $0.id == taskID }))
        XCTAssertEqual(
            task.note?.content,
            """
            Keep this lightweight and easy to book.

            - [ ] Test
            - [ ] to obsidian
            """
        )
        XCTAssertEqual(task.checklistItems.map(\.title), ["Test", "to obsidian"])
    }

    func testApplyRemoteArchiveNotifiesPersistenceObserversWhenRequested() throws {
        let store = try makeStore()
        var cloudNotificationCount = 0
        var reminderNotificationCount = 0
        store.addCloudSyncObserver {
            cloudNotificationCount += 1
        }
        store.addReminderSyncObserver {
            reminderNotificationCount += 1
        }

        let archive = TodayMdArchive(
            lists: [],
            unassignedTasks: [
                .init(
                    id: UUID(),
                    title: "Reminder edit",
                    isDone: false,
                    blockRaw: TimeBlock.today.rawValue,
                    sortOrder: 0,
                    creationDate: Date(),
                    note: nil,
                    subtasks: []
                )
            ]
        )

        store.applyRemoteArchive(archive, notifyTargets: [.cloudSync])

        XCTAssertEqual(cloudNotificationCount, 1)
        XCTAssertEqual(reminderNotificationCount, 0)
    }

    func testApplyRemoteArchiveStaysSilentByDefault() throws {
        let store = try makeStore()
        var cloudNotificationCount = 0
        var reminderNotificationCount = 0
        store.addCloudSyncObserver {
            cloudNotificationCount += 1
        }
        store.addReminderSyncObserver {
            reminderNotificationCount += 1
        }

        let archive = TodayMdArchive(
            lists: [],
            unassignedTasks: [
                .init(
                    id: UUID(),
                    title: "Cloud sync edit",
                    isDone: false,
                    blockRaw: TimeBlock.today.rawValue,
                    sortOrder: 0,
                    creationDate: Date(),
                    note: nil,
                    subtasks: []
                )
            ]
        )

        store.applyRemoteArchive(archive)

        XCTAssertEqual(cloudNotificationCount, 0)
        XCTAssertEqual(reminderNotificationCount, 0)
    }

    func testApplyRemoteArchiveCanNotifyReminderObserversWithoutCloudObservers() throws {
        let store = try makeStore()
        var cloudNotificationCount = 0
        var reminderNotificationCount = 0
        store.addCloudSyncObserver {
            cloudNotificationCount += 1
        }
        store.addReminderSyncObserver {
            reminderNotificationCount += 1
        }

        let archive = TodayMdArchive(
            lists: [],
            unassignedTasks: [
                .init(
                    id: UUID(),
                    title: "Obsidian edit",
                    isDone: false,
                    blockRaw: TimeBlock.today.rawValue,
                    sortOrder: 0,
                    creationDate: Date(),
                    note: nil,
                    subtasks: []
                )
            ]
        )

        store.applyRemoteArchive(archive, notifyTargets: [.reminders])

        XCTAssertEqual(cloudNotificationCount, 0)
        XCTAssertEqual(reminderNotificationCount, 1)
    }

    func testStoreCanResetToShowcaseDataOnLaunch() throws {
        let databaseURL = try makeDatabaseURL()
        let store = TodayMdStore(databaseURL: databaseURL, shouldSeedShowcaseData: false)
        _ = store.addUnassignedTask(title: "Existing task", block: .today)

        let resetStore = TodayMdStore(
            databaseURL: databaseURL,
            shouldSeedShowcaseData: false,
            shouldResetShowcaseData: true
        )

        XCTAssertFalse(resetStore.allTasks.contains(where: { $0.title == "Existing task" }))
        XCTAssertEqual(Set(resetStore.lists.map(\.name)), ["Private", "Work"])
        XCTAssertEqual(resetStore.allTasks.count, 8)
    }

    private func makeStore() throws -> TodayMdStore {
        let databaseURL = try makeDatabaseURL()
        let store = TodayMdStore(
            databaseURL: databaseURL,
            shouldSeedShowcaseData: false
        )
        addTeardownBlock {
            store.flushPendingPersistence()
        }
        return store
    }

    private func makeDatabaseURL() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return rootURL.appendingPathComponent("today-md.sqlite")
    }
}
