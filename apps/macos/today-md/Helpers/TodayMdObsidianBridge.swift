import CryptoKit
import Foundation

enum TodayMdObsidianBridge {
    static func mergedArchive(
        baseArchive: TodayMdArchive?,
        markdownDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> TodayMdArchive? {
        let documents = try loadDocuments(from: markdownDirectoryURL, fileManager: fileManager)

        guard let baseArchive else {
            guard !documents.isEmpty else { return nil }
            return merge(documents: documents, into: TodayMdArchive(lists: [], unassignedTasks: []))
        }

        guard !documents.isEmpty else { return baseArchive }
        return merge(documents: documents, into: baseArchive)
    }

    static func contentRevisionID(for archive: TodayMdArchive) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(ContentSnapshot(archive: archive))
        let digest = SHA256.hash(data: payload)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func merge(
        documents: [MarkdownTaskDocument],
        into archive: TodayMdArchive
    ) -> TodayMdArchive {
        let hydrated = archive.instantiate()
        var lists = hydrated.lists
        var unassignedTasks = hydrated.unassignedTasks
        let archiveUpdatedAt = archive.syncUpdatedAt

        for document in documents {
            let resolvedTaskID = document.taskID ?? UUID()
            let existingTask = locateTask(id: resolvedTaskID, lists: lists, unassignedTasks: unassignedTasks)
            if let existingTask,
               let documentUpdatedAt = document.updatedAt,
               let existingUpdatedAt = archiveUpdatedAt ?? existingReferenceDate(for: existingTask),
               documentUpdatedAt.timeIntervalSince(existingUpdatedAt) <= 1 {
                continue
            }

            let targetList = resolveList(for: document, lists: &lists)
            let task = existingTask ?? makeTask(from: document, taskID: resolvedTaskID, targetList: targetList)

            let sourceListID = task.list?.id
            let targetListID = targetList?.id
            let targetBlock = document.block ?? task.block

            if existingTask == nil {
                attach(task: task, to: targetList, lists: &lists, unassignedTasks: &unassignedTasks)
                task.sortOrder = nextSortOrder(for: targetList, block: targetBlock, lists: lists, unassignedTasks: unassignedTasks)
            }

            if existingTask != nil, sourceListID != targetListID {
                detach(task: task, from: &lists, unassignedTasks: &unassignedTasks)
                attach(task: task, to: targetList, lists: &lists, unassignedTasks: &unassignedTasks)
                task.sortOrder = nextSortOrder(for: targetList, block: targetBlock, lists: lists, unassignedTasks: unassignedTasks)
            } else if existingTask != nil, task.block != targetBlock {
                task.sortOrder = nextSortOrder(for: targetList, block: targetBlock, lists: lists, unassignedTasks: unassignedTasks)
            }

            task.title = document.resolvedTitle(for: task.title)
            task.block = targetBlock
            task.isDone = document.isDone ?? task.isDone
            task.schedulingState = document.schedulingState ?? task.schedulingState
            task.creationDate = document.createdAt ?? task.creationDate
            task.list = targetList
            task.note = note(from: document, existing: task.note)
        }

        normalizeListSortOrder(&lists)
        normalizeTaskSortOrder(in: &lists, unassignedTasks: &unassignedTasks)

        return TodayMdArchive(lists: lists, unassignedTasks: unassignedTasks)
    }

    private static func loadDocuments(
        from directoryURL: URL,
        fileManager: FileManager
    ) throws -> [MarkdownTaskDocument] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        return try fileURLs.map { fileURL in
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let attributes = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            return MarkdownTaskDocument(
                fileURL: fileURL,
                rawContent: content,
                fileModifiedAt: attributes?.contentModificationDate
            )
        }
    }

    private static func resolveList(
        for document: MarkdownTaskDocument,
        lists: inout [TaskList]
    ) -> TaskList? {
        if let listID = document.listID, let existing = lists.first(where: { $0.id == listID }) {
            return existing
        }

        guard let listName = document.listName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !listName.isEmpty,
              listName.caseInsensitiveCompare("Unassigned") != .orderedSame
        else {
            return nil
        }

        if let existing = lists.first(where: { $0.name.compare(listName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }

        let newList = TaskList(
            id: document.listID ?? UUID(),
            name: listName,
            icon: "checklist",
            color: .blue,
            sortOrder: lists.count
        )
        lists.append(newList)
        return newList
    }

    private static func locateTask(
        id: UUID,
        lists: [TaskList],
        unassignedTasks: [TaskItem]
    ) -> TaskItem? {
        (lists.flatMap(\.items) + unassignedTasks).first(where: { $0.id == id })
    }

    private static func makeTask(
        from document: MarkdownTaskDocument,
        taskID: UUID,
        targetList: TaskList?
    ) -> TaskItem {
        let title = document.resolvedTitle(for: "")
        let block = document.block ?? .backlog
        let task = TaskItem(
            id: taskID,
            title: title,
            block: block,
            schedulingState: document.schedulingState ?? .unscheduled,
            sortOrder: 0,
            creationDate: document.createdAt ?? Date(),
            isDone: document.isDone ?? false,
            note: note(from: document, existing: nil)
        )
        task.list = targetList
        return task
    }

    private static func note(
        from document: MarkdownTaskDocument,
        existing: TaskNote?
    ) -> TaskNote? {
        let normalizedBody = MarkdownInlineDisplay.canonicalMarkdown(from: document.body)
        guard !normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let existing {
            existing.content = normalizedBody
            existing.lastModified = document.updatedAt ?? existing.lastModified
            return existing
        }

        return TaskNote(
            content: normalizedBody,
            lastModified: document.updatedAt ?? Date()
        )
    }

    private static func existingReferenceDate(for task: TaskItem) -> Date? {
        if let noteLastModified = task.note?.lastModified {
            return noteLastModified
        }
        return task.creationDate
    }

    private static func detach(
        task: TaskItem,
        from lists: inout [TaskList],
        unassignedTasks: inout [TaskItem]
    ) {
        if let sourceListID = task.list?.id,
           let listIndex = lists.firstIndex(where: { $0.id == sourceListID }) {
            lists[listIndex].items.removeAll { $0.id == task.id }
        } else {
            unassignedTasks.removeAll { $0.id == task.id }
        }
    }

    private static func attach(
        task: TaskItem,
        to list: TaskList?,
        lists: inout [TaskList],
        unassignedTasks: inout [TaskItem]
    ) {
        if let list, let listIndex = lists.firstIndex(where: { $0.id == list.id }) {
            lists[listIndex].items.append(task)
            task.list = lists[listIndex]
        } else {
            unassignedTasks.append(task)
            task.list = nil
        }
    }

    private static func nextSortOrder(
        for list: TaskList?,
        block: TimeBlock,
        lists: [TaskList],
        unassignedTasks: [TaskItem]
    ) -> Int {
        let tasks: [TaskItem]
        if let list {
            tasks = lists.first(where: { $0.id == list.id })?.items ?? []
        } else {
            tasks = unassignedTasks
        }

        return (tasks.filter { $0.block == block }.map(\.sortOrder).max() ?? -1) + 1
    }

    private static func normalizeListSortOrder(_ lists: inout [TaskList]) {
        let ordered = lists.sorted { $0.sortOrder < $1.sortOrder }
        for (index, list) in ordered.enumerated() {
            list.sortOrder = index
        }
        lists = ordered
    }

    private static func normalizeTaskSortOrder(
        in lists: inout [TaskList],
        unassignedTasks: inout [TaskItem]
    ) {
        for list in lists {
            normalizeTaskSortOrder(in: list.items)
        }
        normalizeTaskSortOrder(in: unassignedTasks)
    }

    private static func normalizeTaskSortOrder(in tasks: [TaskItem]) {
        for block in TimeBlock.allCases {
            let ordered = tasks
                .filter { $0.block == block }
                .sorted(by: taskSort)

            for (index, task) in ordered.enumerated() {
                task.sortOrder = index
            }
        }
    }
}

private struct MarkdownTaskDocument {
    let taskID: UUID?
    let listID: UUID?
    let listName: String?
    let title: String?
    let block: TimeBlock?
    let isDone: Bool?
    let schedulingState: TaskSchedulingState?
    let createdAt: Date?
    let updatedAt: Date?
    let body: String
    let fallbackTitle: String

    init(fileURL: URL, rawContent: String, fileModifiedAt: Date?) {
        let parsed = Self.parseFrontmatter(in: rawContent)
        let frontmatter = parsed.frontmatter
        let body = parsed.body

        self.taskID = Self.uuidValue(frontmatter["task_id"]) ?? Self.uuidFromFilename(fileURL)
        self.listID = Self.uuidValue(frontmatter["list_id"])
        self.listName = Self.stringValue(frontmatter["list"])
        self.title = Self.stringValue(frontmatter["title"])
        self.block = Self.blockValue(raw: frontmatter["lane_raw"] ?? frontmatter["lane"] ?? frontmatter["block"])
        self.isDone = Self.boolValue(frontmatter["done"])
        self.schedulingState = Self.schedulingStateValue(frontmatter["scheduling_state"] ?? frontmatter["scheduled"])
        self.createdAt = Self.dateValue(frontmatter["created_at"])
        let frontmatterUpdatedAt = Self.dateValue(frontmatter["updated_at"])
        if let frontmatterUpdatedAt, let fileModifiedAt {
            self.updatedAt = max(frontmatterUpdatedAt, fileModifiedAt)
        } else {
            self.updatedAt = frontmatterUpdatedAt ?? fileModifiedAt
        }
        self.body = body
        self.fallbackTitle = Self.fallbackTitle(from: fileURL, body: body)
    }

    func resolvedTitle(for existingTitle: String) -> String {
        let candidates = [
            title?.trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            existingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        return candidates.compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Untitled Task"
    }

    private static func parseFrontmatter(in content: String) -> (frontmatter: [String: String], body: String) {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return ([:], normalized)
        }

        let lines = normalized.components(separatedBy: "\n")
        guard lines.count >= 3 else { return ([:], normalized) }

        var frontmatter: [String: String] = [:]
        var closingLineIndex: Int?

        for index in 1..<lines.count {
            let line = lines[index]
            if line == "---" {
                closingLineIndex = index
                break
            }

            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                frontmatter[key] = value
            }
        }

        guard let closingLineIndex else {
            return ([:], normalized)
        }

        let bodyLines = Array(lines.dropFirst(closingLineIndex + 1))
        let body = bodyLines.joined(separator: "\n")
        return (frontmatter, body.hasPrefix("\n") ? String(body.dropFirst()) : body)
    }

    private static func stringValue(_ raw: String?) -> String? {
        guard var raw else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
            raw = String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        return raw
    }

    private static func uuidValue(_ raw: String?) -> UUID? {
        stringValue(raw).flatMap(UUID.init(uuidString:))
    }

    private static func boolValue(_ raw: String?) -> Bool? {
        guard let value = stringValue(raw)?.lowercased() else { return nil }
        switch value {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private static func blockValue(raw: String?) -> TimeBlock? {
        guard let value = stringValue(raw)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }

        switch value {
        case TimeBlock.today.rawValue.lowercased(), "today":
            return .today
        case TimeBlock.thisWeek.rawValue.lowercased(), "this week", "this_week":
            return .thisWeek
        case TimeBlock.backlog.rawValue.lowercased(), "backlog":
            return .backlog
        default:
            return nil
        }
    }

    private static func schedulingStateValue(_ raw: String?) -> TaskSchedulingState? {
        guard let value = stringValue(raw)?.lowercased() else { return nil }

        switch value {
        case TaskSchedulingState.scheduled.rawValue:
            return .scheduled
        case TaskSchedulingState.unscheduled.rawValue:
            return .unscheduled
        case "true", "yes", "1":
            return .scheduled
        case "false", "no", "0":
            return .unscheduled
        default:
            return nil
        }
    }

    private static func dateValue(_ raw: String?) -> Date? {
        guard let value = stringValue(raw) else { return nil }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func uuidFromFilename(_ fileURL: URL) -> UUID? {
        let basename = fileURL.deletingPathExtension().lastPathComponent
        guard let separatorRange = basename.range(of: "--", options: .backwards) else { return nil }
        let suffix = basename[separatorRange.upperBound...]
        return UUID(uuidString: String(suffix))
    }

    private static func fallbackTitle(from fileURL: URL, body: String) -> String {
        if let heading = body
            .components(separatedBy: "\n")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix("#") && $0.drop { $0 == "#" }.first == " " }) {
            return heading
                .drop(while: { $0 == "#" || $0 == " " })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let basename = fileURL.deletingPathExtension().lastPathComponent
        let rawTitle: String
        if let separatorRange = basename.range(of: "--", options: .backwards) {
            rawTitle = String(basename[..<separatorRange.lowerBound])
        } else {
            rawTitle = basename
        }

        let cleaned = rawTitle
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Untitled Task" : cleaned.capitalized
    }
}

private struct ContentSnapshot: Codable {
    let lists: [ListSnapshot]
    let unassignedTasks: [TaskSnapshot]

    init(archive: TodayMdArchive) {
        self.lists = archive.lists
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(ListSnapshot.init)
        self.unassignedTasks = archive.unassignedTasks
            .sorted { ($0.blockRaw, $0.sortOrder, $0.creationDate, $0.id.uuidString) < ($1.blockRaw, $1.sortOrder, $1.creationDate, $1.id.uuidString) }
            .map(TaskSnapshot.init)
    }

    struct ListSnapshot: Codable {
        let id: UUID
        let name: String
        let icon: String
        let colorName: String
        let sortOrder: Int
        let tasks: [TaskSnapshot]

        init(archive: TodayMdArchive.ListArchive) {
            self.id = archive.id
            self.name = archive.name
            self.icon = archive.icon
            self.colorName = archive.colorName
            self.sortOrder = archive.sortOrder
            self.tasks = archive.tasks
                .sorted { ($0.blockRaw, $0.sortOrder, $0.creationDate, $0.id.uuidString) < ($1.blockRaw, $1.sortOrder, $1.creationDate, $1.id.uuidString) }
                .map(TaskSnapshot.init)
        }
    }

    struct TaskSnapshot: Codable {
        let id: UUID
        let title: String
        let isDone: Bool
        let blockRaw: String
        let schedulingStateRaw: String
        let sortOrder: Int
        let creationDate: Date
        let noteContent: String?

        init(archive: TodayMdArchive.TaskArchive) {
            self.id = archive.id
            self.title = archive.title
            self.isDone = archive.isDone
            self.blockRaw = archive.blockRaw
            self.schedulingStateRaw = archive.schedulingStateRaw
            self.sortOrder = archive.sortOrder
            self.creationDate = archive.creationDate
            self.noteContent = archive.note?.content
        }
    }
}
