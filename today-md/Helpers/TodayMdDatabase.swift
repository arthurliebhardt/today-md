import Foundation
import SQLite3

final class TodayMdDatabase: @unchecked Sendable {
    private let db: OpaquePointer

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            defer { if let handle { sqlite3_close(handle) } }
            throw DatabaseError.openFailed(message: String(cString: sqlite3_errmsg(handle)))
        }

        db = handle
        try execute("PRAGMA foreign_keys = ON;")
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadArchive() throws -> TodayMdArchive {
        let lists = try fetchLists()
        let unassignedTasks = try fetchTasks(listID: nil)
        return TodayMdArchive(lists: lists, unassignedTasks: unassignedTasks)
    }

    func replaceAll(with archive: TodayMdArchive) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try execute("DELETE FROM task_notes;")
            try execute("DELETE FROM subtasks;")
            try execute("DELETE FROM tasks_fts;")
            try execute("DELETE FROM tasks;")
            try execute("DELETE FROM task_lists;")

            try insertLists(archive.lists)
            try insertTasks(archive.lists.flatMap(\.tasks), listLookup: Dictionary(uniqueKeysWithValues: archive.lists.flatMap { list in
                list.tasks.map { ($0.id, list.id) }
            }))
            try insertTasks(archive.unassignedTasks, listLookup: [:])

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func searchTaskIDs(matching query: String) throws -> [UUID] {
        let normalized = query
            .split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                let cleaned = token.replacingOccurrences(of: "\"", with: "")
                return cleaned.isEmpty ? cleaned : "\(cleaned)*"
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty else { return [] }

        let statement = try prepare(
            """
            SELECT task_id
            FROM tasks_fts
            WHERE tasks_fts MATCH ?
            ORDER BY bm25(tasks_fts), rowid;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(normalized, at: 1, in: statement)

        var ids: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let taskID = columnText(statement, index: 0), let uuid = UUID(uuidString: taskID) else { continue }
            ids.append(uuid)
        }
        return ids
    }

    private func createSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS task_lists (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                icon TEXT NOT NULL,
                color_name TEXT NOT NULL,
                sort_order INTEGER NOT NULL
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY NOT NULL,
                list_id TEXT REFERENCES task_lists(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                is_done INTEGER NOT NULL,
                block_raw TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                creation_date REAL NOT NULL,
                scheduling_state_raw TEXT NOT NULL DEFAULT 'unscheduled',
                modified_date REAL NOT NULL DEFAULT 0,
                scheduled_date REAL
            );
            """
        )

        try ensureColumn(
            named: "scheduling_state_raw",
            in: "tasks",
            definition: "TEXT NOT NULL DEFAULT 'unscheduled'"
        )
        try ensureColumn(
            named: "modified_date",
            in: "tasks",
            definition: "REAL NOT NULL DEFAULT 0"
        )
        try ensureColumn(
            named: "scheduled_date",
            in: "tasks",
            definition: "REAL"
        )
        try execute("UPDATE tasks SET modified_date = creation_date WHERE modified_date <= 0;")

        try execute(
            """
            CREATE TABLE IF NOT EXISTS task_notes (
                task_id TEXT PRIMARY KEY NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                content TEXT NOT NULL,
                last_modified REAL NOT NULL
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS subtasks (
                id TEXT PRIMARY KEY NOT NULL,
                task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                is_completed INTEGER NOT NULL,
                sort_order INTEGER NOT NULL
            );
            """
        )

        try execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
                task_id UNINDEXED,
                title,
                note_markdown,
                subtask_text
            );
            """
        )

        try execute("CREATE INDEX IF NOT EXISTS idx_task_lists_sort ON task_lists(sort_order);")
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_list_block_sort ON tasks(list_id, block_raw, sort_order);")
        try execute("CREATE INDEX IF NOT EXISTS idx_subtasks_task_sort ON subtasks(task_id, sort_order);")
    }

    private func fetchLists() throws -> [TodayMdArchive.ListArchive] {
        let statement = try prepare(
            """
            SELECT id, name, icon, color_name, sort_order
            FROM task_lists
            ORDER BY sort_order, id;
            """
        )
        defer { sqlite3_finalize(statement) }

        var lists: [TodayMdArchive.ListArchive] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idString = columnText(statement, index: 0),
                let id = UUID(uuidString: idString),
                let name = columnText(statement, index: 1),
                let icon = columnText(statement, index: 2),
                let colorName = columnText(statement, index: 3)
            else {
                continue
            }

            let sortOrder = Int(sqlite3_column_int64(statement, 4))
            lists.append(
                TodayMdArchive.ListArchive(
                    id: id,
                    name: name,
                    icon: icon,
                    colorName: colorName,
                    sortOrder: sortOrder,
                    tasks: try fetchTasks(listID: id)
                )
            )
        }
        return lists
    }

    private func fetchTasks(listID: UUID?) throws -> [TodayMdArchive.TaskArchive] {
        let sql: String
        if listID == nil {
            sql =
                """
                SELECT id, title, is_done, block_raw, sort_order, creation_date, scheduling_state_raw, modified_date, scheduled_date
                FROM tasks
                WHERE list_id IS NULL
                ORDER BY
                    CASE block_raw
                        WHEN 'today' THEN 0
                        WHEN 'thisWeek' THEN 1
                        ELSE 2
                    END,
                    sort_order,
                    creation_date,
                    id;
                """
        } else {
            sql =
                """
                SELECT id, title, is_done, block_raw, sort_order, creation_date, scheduling_state_raw, modified_date, scheduled_date
                FROM tasks
                WHERE list_id = ?
                ORDER BY
                    CASE block_raw
                        WHEN 'today' THEN 0
                        WHEN 'thisWeek' THEN 1
                        ELSE 2
                    END,
                    sort_order,
                    creation_date,
                    id;
                """
        }

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        if let listID {
            try bind(listID.uuidString, at: 1, in: statement)
        }

        var tasks: [TodayMdArchive.TaskArchive] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idString = columnText(statement, index: 0),
                let id = UUID(uuidString: idString),
                let title = columnText(statement, index: 1),
                let blockRaw = columnText(statement, index: 3)
            else {
                continue
            }

            let isDone = sqlite3_column_int(statement, 2) != 0
            let sortOrder = Int(sqlite3_column_int64(statement, 4))
            let creationDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let schedulingStateRaw = columnText(statement, index: 6) ?? TaskSchedulingState.unscheduled.rawValue
            let modifiedDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
            let scheduledDate: Date? =
                sqlite3_column_type(statement, 8) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))

            tasks.append(
                TodayMdArchive.TaskArchive(
                    id: id,
                    title: title,
                    isDone: isDone,
                    blockRaw: blockRaw,
                    schedulingStateRaw: schedulingStateRaw,
                    sortOrder: sortOrder,
                    creationDate: creationDate,
                    modifiedDate: modifiedDate,
                    scheduledDate: scheduledDate,
                    note: try fetchNote(taskID: id),
                    subtasks: try fetchSubtasks(taskID: id)
                )
            )
        }
        return tasks
    }

    private func fetchNote(taskID: UUID) throws -> TodayMdArchive.NoteArchive? {
        let statement = try prepare(
            """
            SELECT content, last_modified
            FROM task_notes
            WHERE task_id = ?
            LIMIT 1;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(taskID.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let content = columnText(statement, index: 0)
        else {
            return nil
        }

        return TodayMdArchive.NoteArchive(
            content: content,
            lastModified: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    private func fetchSubtasks(taskID: UUID) throws -> [TodayMdArchive.SubTaskArchive] {
        let statement = try prepare(
            """
            SELECT id, title, is_completed, sort_order
            FROM subtasks
            WHERE task_id = ?
            ORDER BY sort_order, id;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(taskID.uuidString, at: 1, in: statement)

        var subtasks: [TodayMdArchive.SubTaskArchive] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idString = columnText(statement, index: 0),
                let id = UUID(uuidString: idString),
                let title = columnText(statement, index: 1)
            else {
                continue
            }

            subtasks.append(
                TodayMdArchive.SubTaskArchive(
                    id: id,
                    title: title,
                    isCompleted: sqlite3_column_int(statement, 2) != 0,
                    sortOrder: Int(sqlite3_column_int64(statement, 3))
                )
            )
        }
        return subtasks
    }

    private func insertLists(_ lists: [TodayMdArchive.ListArchive]) throws {
        let statement = try prepare(
            """
            INSERT INTO task_lists (id, name, icon, color_name, sort_order)
            VALUES (?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }

        for list in lists {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            try bind(list.id.uuidString, at: 1, in: statement)
            try bind(list.name, at: 2, in: statement)
            try bind(list.icon, at: 3, in: statement)
            try bind(list.colorName, at: 4, in: statement)
            try bind(Int64(list.sortOrder), at: 5, in: statement)

            try stepDone(statement)
        }
    }

    private func insertTasks(
        _ tasks: [TodayMdArchive.TaskArchive],
        listLookup: [UUID: UUID]
    ) throws {
        let taskStatement = try prepare(
            """
            INSERT INTO tasks (id, list_id, title, is_done, block_raw, sort_order, creation_date, scheduling_state_raw, modified_date, scheduled_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(taskStatement) }

        let noteStatement = try prepare(
            """
            INSERT INTO task_notes (task_id, content, last_modified)
            VALUES (?, ?, ?);
            """
        )
        defer { sqlite3_finalize(noteStatement) }

        let subtaskStatement = try prepare(
            """
            INSERT INTO subtasks (id, task_id, title, is_completed, sort_order)
            VALUES (?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(subtaskStatement) }

        let ftsStatement = try prepare(
            """
            INSERT INTO tasks_fts (task_id, title, note_markdown, subtask_text)
            VALUES (?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(ftsStatement) }

        for task in tasks {
            sqlite3_reset(taskStatement)
            sqlite3_clear_bindings(taskStatement)

            try bind(task.id.uuidString, at: 1, in: taskStatement)
            if let listID = listLookup[task.id] {
                try bind(listID.uuidString, at: 2, in: taskStatement)
            } else {
                try bindNull(at: 2, in: taskStatement)
            }
            try bind(task.title, at: 3, in: taskStatement)
            try bind(Int32(task.isDone ? 1 : 0), at: 4, in: taskStatement)
            try bind(task.blockRaw, at: 5, in: taskStatement)
            try bind(Int64(task.sortOrder), at: 6, in: taskStatement)
            try bind(task.creationDate.timeIntervalSince1970, at: 7, in: taskStatement)
            try bind(task.schedulingStateRaw, at: 8, in: taskStatement)
            try bind(task.modifiedDate.timeIntervalSince1970, at: 9, in: taskStatement)
            if let scheduledDate = task.scheduledDate {
                try bind(scheduledDate.timeIntervalSince1970, at: 10, in: taskStatement)
            } else {
                try bindNull(at: 10, in: taskStatement)
            }
            try stepDone(taskStatement)

            if let note = task.note {
                sqlite3_reset(noteStatement)
                sqlite3_clear_bindings(noteStatement)
                try bind(task.id.uuidString, at: 1, in: noteStatement)
                try bind(note.content, at: 2, in: noteStatement)
                try bind(note.lastModified.timeIntervalSince1970, at: 3, in: noteStatement)
                try stepDone(noteStatement)
            }

            for subtask in task.subtasks {
                sqlite3_reset(subtaskStatement)
                sqlite3_clear_bindings(subtaskStatement)
                try bind(subtask.id.uuidString, at: 1, in: subtaskStatement)
                try bind(task.id.uuidString, at: 2, in: subtaskStatement)
                try bind(subtask.title, at: 3, in: subtaskStatement)
                try bind(Int32(subtask.isCompleted ? 1 : 0), at: 4, in: subtaskStatement)
                try bind(Int64(subtask.sortOrder), at: 5, in: subtaskStatement)
                try stepDone(subtaskStatement)
            }

            sqlite3_reset(ftsStatement)
            sqlite3_clear_bindings(ftsStatement)
            try bind(task.id.uuidString, at: 1, in: ftsStatement)
            try bind(task.title, at: 2, in: ftsStatement)
            try bind(task.note?.content ?? "", at: 3, in: ftsStatement)
            try bind(task.subtasks.map(\.title).joined(separator: "\n"), at: 4, in: ftsStatement)
            try stepDone(ftsStatement)
        }
    }

    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw DatabaseError.executeFailed(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }
    }

    private func ensureColumn(named column: String, in table: String, definition: String) throws {
        let statement = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, index: 1) == column {
                return
            }
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw DatabaseError.prepareFailed(message: String(cString: sqlite3_errmsg(db)), sql: sql)
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        guard result == SQLITE_OK else {
            throw DatabaseError.bindFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: Int64, at index: Int32, in statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else {
            throw DatabaseError.bindFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: Int32, at index: Int32, in statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int(statement, index, value)
        guard result == SQLITE_OK else {
            throw DatabaseError.bindFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: Double, at index: Int32, in statement: OpaquePointer?) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw DatabaseError.bindFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bindNull(at index: Int32, in statement: OpaquePointer?) throws {
        let result = sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else {
            throw DatabaseError.bindFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw DatabaseError.stepFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

private enum DatabaseError: LocalizedError {
    case openFailed(message: String)
    case executeFailed(message: String, sql: String)
    case prepareFailed(message: String, sql: String)
    case bindFailed(message: String)
    case stepFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Failed to open the database: \(message)"
        case .executeFailed(let message, let sql):
            return "Failed to execute SQL (\(sql)): \(message)"
        case .prepareFailed(let message, let sql):
            return "Failed to prepare SQL (\(sql)): \(message)"
        case .bindFailed(let message):
            return "Failed to bind a SQLite value: \(message)"
        case .stepFailed(let message):
            return "Failed to step a SQLite statement: \(message)"
        }
    }
}
