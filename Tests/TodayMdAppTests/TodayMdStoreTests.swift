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

    func testWidgetSnapshotIncludesOnlyTodayTasksAndKeepsDoneCount() throws {
        let store = try makeStore()
        let workList = store.addList(name: "Work", icon: "briefcase", color: .blue)

        let todayTask = try XCTUnwrap(store.addTask(title: "Ship widget", block: .today, listID: workList.id))
        _ = store.addTask(title: "Later this week", block: .thisWeek, listID: workList.id)
        let inboxTask = store.addUnassignedTask(title: "Inbox today", block: .today)
        store.setTaskCompletion(id: inboxTask.id, isDone: true)

        let snapshot = TodayMdWidgetSnapshotWriter.makeSnapshot(
            lists: store.lists,
            unassignedTasks: store.unassignedTasks,
            generatedAt: Date(timeIntervalSince1970: 123)
        )

        XCTAssertEqual(snapshot.generatedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Ship widget", "Inbox today"])
        XCTAssertEqual(snapshot.tasks.first?.listName, "Work")
        XCTAssertNil(snapshot.tasks.last?.listName)
        XCTAssertEqual(snapshot.remainingTasks.map(\.title), ["Ship widget"])
        XCTAssertEqual(snapshot.completedCount, 1)
        XCTAssertEqual(todayTask.title, "Ship widget")
    }

    private func makeStore() throws -> TodayMdStore {
        let databaseURL = try makeDatabaseURL()
        return TodayMdStore(
            databaseURL: databaseURL,
            shouldSeedShowcaseData: false
        )
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
