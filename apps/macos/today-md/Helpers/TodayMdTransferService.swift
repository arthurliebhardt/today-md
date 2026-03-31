import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum TodayMdTransferService {
    private static var activePanel: NSOpenPanel?

    static func exportData(from store: TodayMdStore) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Export Tasks"
        panel.message = "Choose where to create the export folder."
        panel.prompt = "Export"

        present(panel) { folderURL in
            guard let folderURL else { return }

            do {
                try exportData(from: store, to: folderURL)
            } catch {
                presentError(title: "Export Failed", error: error)
            }
        }
    }

    static func exportData(from store: TodayMdStore, to folderURL: URL) throws {
        try withSecurityScopedAccess(to: folderURL) {
            let timestamp = Date()
            let exportFolderURL = folderURL.appendingPathComponent(
                defaultExportFolderName(for: timestamp),
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: exportFolderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let exportBaseName = defaultExportBasename(for: timestamp)
            let exportURL = exportFolderURL.appendingPathComponent("\(exportBaseName).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(store.makeArchive())
            try data.write(to: exportURL, options: .atomic)

            let markdownFolderURL = exportFolderURL.appendingPathComponent("\(exportBaseName)-markdown", isDirectory: true)
            try TodayMdMarkdownArchiveService.exportNotes(for: store.allTasks, to: markdownFolderURL)
        }
    }

    static func importData(into store: TodayMdStore) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Import Tasks"
        panel.message = "Choose the JSON backup file to import."
        panel.prompt = "Import File"

        present(panel) { url in
            guard let url else { return }

            do {
                guard let mode = chooseImportMode() else { return }
                try importData(into: store, from: url, mode: mode)
            } catch {
                presentError(title: "Import Failed", error: error)
            }
        }
    }

    static func importData(into store: TodayMdStore, from url: URL, mode: ImportMode) throws {
        try withSecurityScopedAccess(to: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try Data(contentsOf: url)
            let archive = try decoder.decode(TodayMdArchive.self, from: data)
            store.applyImport(archive, mode: mode)
        }
    }

    private static func present(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
        activePanel = panel

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let url = response == .OK ? panel.url : nil
            activePanel = nil
            completion(url)
        }

        if let window = presentingWindow() {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: finish)
            return
        }

        finish(panel.runModal())
    }

    private static func presentingWindow() -> NSWindow? {
        NSApp.orderedWindows.first { window in
            window.isVisible && !(window is NSPanel)
        }
    }

    private static func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private static func chooseImportMode() -> ImportMode? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Import Tasks"
        alert.informativeText = "Choose whether to merge the imported data into your existing lists or replace everything currently in the app."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace Existing")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .replaceExisting
        default:
            return nil
        }
    }

    private static func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.runModal()
    }

    private static func defaultExportFolderName(for date: Date) -> String {
        "today-md-eport-\(exportDateString(from: date))"
    }

    private static func defaultExportBasename(for date: Date) -> String {
        "today-md-backup-\(exportDateString(from: date))"
    }

    private static func exportDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}

enum ImportMode {
    case merge
    case replaceExisting
}

@MainActor
enum TodayMdMarkdownArchiveService {
    static func reconcileArchive(with store: TodayMdStore) throws {
        let directoryURL = try archiveDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let currentArchive = store.makeArchive()
        if let mergedArchive = try TodayMdObsidianBridge.mergedArchive(
            baseArchive: currentArchive,
            markdownDirectoryURL: directoryURL
        ) {
            let currentRevision = try TodayMdObsidianBridge.contentRevisionID(for: currentArchive)
            let mergedRevision = try TodayMdObsidianBridge.contentRevisionID(for: mergedArchive)

            if currentRevision != mergedRevision {
                store.applyMarkdownArchive(mergedArchive)
            }
        }

        try writeNotes(store.allTasks, to: directoryURL, removeStaleFiles: true)
    }

    static func syncNotes(for tasks: [TaskItem]) throws {
        let directoryURL = try archiveDirectoryURL()
        try syncNotes(for: tasks, to: directoryURL)
    }

    static func syncNotes(for tasks: [TaskItem], to directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try writeNotes(tasks, to: directoryURL, removeStaleFiles: true)
    }

    static func exportNotes(for tasks: [TaskItem], to directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try writeNotes(tasks, to: directoryURL, removeStaleFiles: true)
    }

    private static func writeNotes(
        _ tasks: [TaskItem],
        to directoryURL: URL,
        removeStaleFiles: Bool
    ) throws {
        let fileManager = FileManager.default

        let noteFiles = tasks
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { task in
                (
                    filename: archiveFilename(for: task),
                    content: renderMarkdown(for: task)
                )
            }

        let expectedFilenames = Set(noteFiles.map(\.filename))
        if removeStaleFiles {
            let existingFiles = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for fileURL in existingFiles where fileURL.pathExtension.lowercased() == "md" {
                guard !expectedFilenames.contains(fileURL.lastPathComponent) else { continue }
                try? fileManager.removeItem(at: fileURL)
            }
        }

        for noteFile in noteFiles {
            let fileURL = directoryURL.appendingPathComponent(noteFile.filename, isDirectory: false)
            try noteFile.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static func archivePath() throws -> String {
        try archiveDirectoryURL().path
    }

    static func revealArchiveFolder() throws {
        let directoryURL = try archiveDirectoryURL()
        NSWorkspace.shared.open(directoryURL)
    }

    private static func archiveDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MarkdownArchiveError.applicationSupportUnavailable
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent("today-md", isDirectory: true)
            .appendingPathComponent("Markdown Archive", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }

    private static func archiveFilename(for task: TaskItem) -> String {
        let slug = slugify(task.title)
        return "\(slug)--\(task.id.uuidString.lowercased()).md"
    }

    private static func slugify(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.lowercased().unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }

        let collapsed = scalars.joined()
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let fallback = collapsed.isEmpty ? "untitled-task" : collapsed
        return String(fallback.prefix(60))
    }

    private static func renderMarkdown(for task: TaskItem) -> String {
        let lines = [
            "---",
            "task_id: \"\(task.id.uuidString)\"",
            "title: \"\(yamlEscaped(task.title))\"",
            "done: \(task.isDone ? "true" : "false")",
            "list: \"\(yamlEscaped(task.list?.name ?? "Unassigned"))\"",
            "list_id: \"\(task.list?.id.uuidString ?? "")\"",
            "lane: \"\(yamlEscaped(task.block.label))\"",
            "lane_raw: \"\(task.block.rawValue)\"",
            "scheduling_state: \"\(task.schedulingState.rawValue)\"",
            "created_at: \"\(iso8601String(from: task.creationDate))\"",
            "updated_at: \"\(iso8601String(from: task.note?.lastModified ?? task.creationDate))\"",
            "---",
            "",
            task.note?.content ?? ""
        ]

        return lines.joined(separator: "\n")
    }

    private static func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private enum MarkdownArchiveError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The Application Support folder is unavailable."
        }
    }
}
