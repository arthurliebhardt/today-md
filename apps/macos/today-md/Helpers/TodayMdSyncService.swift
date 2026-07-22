import AppKit
import Combine
import Foundation

enum SyncStatus: String, Codable {
    case disabled
    case idle
    case syncing
    case conflict
    case error

    var label: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .conflict:
            return "Conflict"
        case .error:
            return "Error"
        }
    }
}

enum SyncResolution {
    case useRemote
    case keepLocal
}

struct SyncConflict: Identifiable, Equatable {
    let id = UUID()
    let remoteRevisionID: String?
    let remoteUpdatedAt: Date?
    let remoteUpdatedByDeviceID: String?
}

private struct PendingSyncConflict {
    let localArchive: TodayMdArchive
    let remoteArchive: TodayMdArchive
}

private enum VersionVectorRelation {
    case equal
    case before
    case after
    case concurrent
}

private struct TodayMdSyncPersistedState: Codable {
    var deviceID: String
    var bookmarkData: Data?
    var lastKnownFolderPath: String?
    var lastSyncedRevision: String?
    var lastSyncedVersionVector: [String: Int]?
    var lastSyncAt: Date?
    var lastError: String?
    var syncEnabled: Bool
    var hasUnsyncedLocalChanges: Bool
    var status: SyncStatus

    static func initial() -> TodayMdSyncPersistedState {
        TodayMdSyncPersistedState(
            deviceID: UUID().uuidString.lowercased(),
            bookmarkData: nil,
            lastKnownFolderPath: nil,
            lastSyncedRevision: nil,
            lastSyncedVersionVector: [:],
            lastSyncAt: nil,
            lastError: nil,
            syncEnabled: false,
            hasUnsyncedLocalChanges: false,
            status: .disabled
        )
    }
}

@MainActor
final class TodayMdSyncService: ObservableObject {
    @Published private(set) var syncEnabled = false
    @Published private(set) var status: SyncStatus = .disabled
    @Published private(set) var folderPath: String?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var hasUnsyncedLocalChanges = false
    @Published private(set) var conflict: SyncConflict?

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let debounceInterval: TimeInterval
    private var persistedState: TodayMdSyncPersistedState
    private weak var store: TodayMdStore?
    private var pushWorkItem: DispatchWorkItem?
    private var pendingConflict: PendingSyncConflict?
    private var hasHandledInitialLaunch = false
    private var isSyncInProgress = false
    private var isSyncLifecycleActive: Bool

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        debounceInterval: TimeInterval = 2,
        syncLifecycleActive: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.debounceInterval = debounceInterval
        self.isSyncLifecycleActive = syncLifecycleActive
        self.persistedState = Self.loadState(from: userDefaults)
        applyPersistedState()
    }

    var statusLabel: String {
        status.label
    }

    var hasFolderSelection: Bool {
        folderPath != nil
    }

    var markdownArchivePath: String? {
        guard let folderPath else { return nil }
        return Self.markdownArchiveDirectoryURL(in: URL(fileURLWithPath: folderPath)).path
    }

    func attach(store: TodayMdStore) {
        self.store = store
        store.configureSyncHandler { [weak self] in
            self?.handleLocalStoreChange()
        }
    }

    func setSyncLifecycleActive(_ isActive: Bool) {
        guard isSyncLifecycleActive != isActive else { return }
        isSyncLifecycleActive = isActive

        guard isActive else {
            cancelPendingPush()
            return
        }

        if hasHandledInitialLaunch {
            syncNow()
        } else {
            handleAppLaunchIfNeeded()
        }
    }

    func handleAppLaunchIfNeeded() {
        guard isSyncLifecycleActive else { return }
        guard !hasHandledInitialLaunch else { return }
        hasHandledInitialLaunch = true
        syncNow()
    }

    func handleAppDidBecomeActive() {
        syncNow()
    }

    func promptForFolderSelection() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Sync Folder"
        panel.message = "Choose a folder inside iCloud Drive, OneDrive, or another synced location."
        panel.prompt = "Use Folder"

        present(panel) { [weak self] folderURL in
            guard let self, let folderURL else { return }

            do {
                try self.enableSync(at: folderURL)
            } catch {
                self.recordError(error)
            }
        }
    }

    func enableSync(at folderURL: URL) throws {
        guard let store else { throw TodayMdSyncError.storeUnavailable }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let bookmarkData = try folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        cancelPendingPush()
        pendingConflict = nil
        conflict = nil

        updatePersistedState { state in
            state.bookmarkData = bookmarkData
            state.lastKnownFolderPath = folderURL.path
            state.lastSyncedRevision = nil
            state.lastSyncedVersionVector = [:]
            state.lastSyncAt = nil
            state.lastError = nil
            state.syncEnabled = true
            state.hasUnsyncedLocalChanges = !store.isEmpty
            state.status = .idle
        }

        syncNow()
    }

    func disableSync() {
        cancelPendingPush()
        pendingConflict = nil
        conflict = nil

        updatePersistedState { state in
            state.bookmarkData = nil
            state.lastKnownFolderPath = nil
            state.lastSyncedRevision = nil
            state.lastSyncedVersionVector = [:]
            state.lastSyncAt = nil
            state.lastError = nil
            state.syncEnabled = false
            state.hasUnsyncedLocalChanges = false
            state.status = .disabled
        }
    }

    func openSyncFolder() {
        do {
            let folderURL = try resolvedFolderURL()
            _ = try withSecurityScopedAccess(to: folderURL) {
                NSWorkspace.shared.open(folderURL)
            }
        } catch {
            recordError(error)
        }
    }

    func openMarkdownArchiveFolder() {
        do {
            let folderURL = try resolvedFolderURL()
            _ = try withSecurityScopedAccess(to: folderURL) {
                let archiveURL = Self.markdownArchiveDirectoryURL(in: folderURL)
                try fileManager.createDirectory(at: archiveURL, withIntermediateDirectories: true)
                NSWorkspace.shared.open(archiveURL)
            }
        } catch {
            recordError(error)
        }
    }

    func syncNow() {
        guard isSyncLifecycleActive else { return }
        guard syncEnabled else { return }
        guard !isSyncInProgress else { return }
        guard store != nil else { return }
        guard pendingConflict == nil else {
            updatePersistedState { $0.status = .conflict }
            return
        }

        isSyncInProgress = true
        updatePersistedState { state in
            state.status = .syncing
            state.lastError = nil
        }

        do {
            try performSync()
        } catch {
            recordError(error)
        }

        isSyncInProgress = false
    }

    func resolveConflict(_ resolution: SyncResolution) {
        guard syncEnabled else { return }
        guard let pendingConflict, let store else { return }

        do {
            let folderURL = try resolvedFolderURL()
            let didResolve = try withSecurityScopedAccess(to: folderURL) { () -> Bool in
                let latestRemoteArchive = try loadRemoteArchiveIfPresent(from: folderURL)
                guard try remoteArchive(latestRemoteArchive, matches: pendingConflict.remoteArchive) else {
                    guard let latestRemoteArchive else {
                        throw TodayMdSyncError.remoteSnapshotChanged
                    }
                    enterConflict(
                        localArchive: localArchiveSnapshot(from: store),
                        remoteArchive: latestRemoteArchive
                    )
                    return false
                }

                switch resolution {
                case .useRemote:
                    try writeConflictBackup(for: pendingConflict.localArchive, prefix: "local", in: folderURL)
                    store.applyRemoteArchive(pendingConflict.remoteArchive)
                    updatePersistedState { state in
                        state.lastSyncedRevision = try? TodayMdObsidianBridge.contentRevisionID(for: pendingConflict.remoteArchive)
                        state.lastSyncedVersionVector = pendingConflict.remoteArchive.syncVersionVector ?? [:]
                        state.lastSyncAt = Date()
                        state.lastError = nil
                        state.hasUnsyncedLocalChanges = false
                        state.status = .idle
                    }
                    return true
                case .keepLocal:
                    try writeConflictBackup(for: pendingConflict.remoteArchive, prefix: "cloud", in: folderURL)
                    return try pushLocalSnapshot(
                        from: store,
                        to: folderURL,
                        expectedRemoteArchive: pendingConflict.remoteArchive,
                        mergingVersionVector: pendingConflict.remoteArchive.syncVersionVector ?? [:]
                    )
                }
            }

            guard didResolve else { return }
            self.pendingConflict = nil
            conflict = nil
        } catch {
            recordError(error)
        }
    }

    private func handleLocalStoreChange() {
        guard syncEnabled else { return }

        updatePersistedState { state in
            state.hasUnsyncedLocalChanges = true
            if state.status == .disabled {
                state.status = .idle
            }
        }

        guard isSyncLifecycleActive else { return }
        guard pendingConflict == nil else { return }
        scheduleDebouncedPush()
    }

    private func performSync() throws {
        guard let store else { throw TodayMdSyncError.storeUnavailable }

        let folderURL = try resolvedFolderURL()
        try withSecurityScopedAccess(to: folderURL) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let remoteArchive = try loadRemoteArchiveIfPresent(from: folderURL)
            if let remoteArchive, remoteArchiveIsNew(remoteArchive) {
                // Descendants are ordinary later edits. An ancestor or incomparable
                // vector means another writer replaced or branched from our revision.
                let versionRelation = Self.compareVersionVector(
                    remoteArchive.syncVersionVector ?? [:],
                    to: persistedState.lastSyncedVersionVector ?? [:]
                )
                if persistedState.hasUnsyncedLocalChanges
                    || versionRelation == .before
                    || versionRelation == .concurrent {
                    enterConflict(localArchive: localArchiveSnapshot(from: store), remoteArchive: remoteArchive)
                    return
                }

                store.applyRemoteArchive(remoteArchive)
                pendingConflict = nil
                conflict = nil
                let effectiveRevisionID = try TodayMdObsidianBridge.contentRevisionID(for: remoteArchive)
                updatePersistedState { state in
                    state.lastSyncedRevision = effectiveRevisionID
                    state.lastSyncedVersionVector = remoteArchive.syncVersionVector ?? [:]
                    state.lastSyncAt = Date()
                    state.lastError = nil
                    state.hasUnsyncedLocalChanges = false
                    state.status = .idle
                }
                return
            }

            if persistedState.hasUnsyncedLocalChanges {
                _ = try pushLocalSnapshot(
                    from: store,
                    to: folderURL,
                    expectedRemoteArchive: remoteArchive
                )
                return
            }

            updatePersistedState { state in
                state.lastError = nil
                state.status = .idle
            }
        }
    }

    @discardableResult
    private func pushLocalSnapshot(
        from store: TodayMdStore,
        to folderURL: URL,
        expectedRemoteArchive: TodayMdArchive?,
        mergingVersionVector: [String: Int] = [:]
    ) throws -> Bool {
        // Cloud-backed folders do not provide a reliable cross-device lock. Re-read
        // immediately before replacing the shared snapshot as an optimistic CAS.
        let latestRemoteArchive = try loadRemoteArchiveIfPresent(from: folderURL)
        guard try remoteArchive(latestRemoteArchive, matches: expectedRemoteArchive) else {
            guard let latestRemoteArchive else {
                throw TodayMdSyncError.remoteSnapshotChanged
            }
            enterConflict(
                localArchive: localArchiveSnapshot(from: store),
                remoteArchive: latestRemoteArchive
            )
            return false
        }

        let revisionID = UUID().uuidString.lowercased()
        let syncDate = Date()
        var versionVector = Self.mergeVersionVectors(
            persistedState.lastSyncedVersionVector ?? [:],
            latestRemoteArchive?.syncVersionVector ?? [:],
            mergingVersionVector
        )
        versionVector[persistedState.deviceID, default: 0] += 1
        let archive = store.makeArchive(
            syncRevisionID: revisionID,
            syncUpdatedAt: syncDate,
            syncUpdatedByDeviceID: persistedState.deviceID,
            syncVersionVector: versionVector
        )

        let remoteURL = Self.syncArchiveURL(in: folderURL)
        try writeArchive(archive, to: remoteURL)
        try TodayMdMarkdownArchiveService.exportNotes(
            for: store.allTasks,
            to: Self.markdownArchiveDirectoryURL(in: folderURL)
        )

        // Catch a writer that became visible during our write. If it appears later,
        // the version-vector comparison on the next sync detects the sibling revision.
        let verifiedRemoteArchive = try loadRemoteArchiveIfPresent(from: folderURL)
        guard try remoteArchive(verifiedRemoteArchive, matches: archive) else {
            guard let verifiedRemoteArchive else {
                throw TodayMdSyncError.remoteSnapshotChanged
            }
            enterConflict(localArchive: archive, remoteArchive: verifiedRemoteArchive)
            return false
        }

        pendingConflict = nil
        conflict = nil
        let effectiveRevisionID = try TodayMdObsidianBridge.contentRevisionID(for: archive)
        updatePersistedState { state in
            state.lastSyncedRevision = effectiveRevisionID
            state.lastSyncedVersionVector = versionVector
            state.lastSyncAt = syncDate
            state.lastError = nil
            state.hasUnsyncedLocalChanges = false
            state.status = .idle
        }
        return true
    }

    private func localArchiveSnapshot(from store: TodayMdStore) -> TodayMdArchive {
        store.makeArchive(
            syncRevisionID: persistedState.lastSyncedRevision,
            syncUpdatedAt: persistedState.lastSyncAt,
            syncUpdatedByDeviceID: persistedState.deviceID,
            syncVersionVector: persistedState.lastSyncedVersionVector ?? [:]
        )
    }

    private func enterConflict(localArchive: TodayMdArchive, remoteArchive: TodayMdArchive) {
        pendingConflict = PendingSyncConflict(localArchive: localArchive, remoteArchive: remoteArchive)
        conflict = SyncConflict(
            remoteRevisionID: remoteArchive.syncRevisionID,
            remoteUpdatedAt: remoteArchive.syncUpdatedAt,
            remoteUpdatedByDeviceID: remoteArchive.syncUpdatedByDeviceID
        )

        updatePersistedState { state in
            state.lastError = nil
            state.status = .conflict
        }
    }

    private func remoteArchiveIsNew(_ remoteArchive: TodayMdArchive) -> Bool {
        guard let effectiveRevisionID = try? TodayMdObsidianBridge.contentRevisionID(for: remoteArchive) else {
            return true
        }

        return effectiveRevisionID != persistedState.lastSyncedRevision
    }

    private func remoteArchive(
        _ currentArchive: TodayMdArchive?,
        matches expectedArchive: TodayMdArchive?
    ) throws -> Bool {
        switch (currentArchive, expectedArchive) {
        case (nil, nil):
            return true
        case (.some(let currentArchive), .some(let expectedArchive)):
            return try TodayMdObsidianBridge.contentRevisionID(for: currentArchive)
                == TodayMdObsidianBridge.contentRevisionID(for: expectedArchive)
                && (currentArchive.syncVersionVector ?? [:]) == (expectedArchive.syncVersionVector ?? [:])
        case (.some, nil), (nil, .some):
            return false
        }
    }

    private static func compareVersionVector(
        _ lhs: [String: Int],
        to rhs: [String: Int]
    ) -> VersionVectorRelation {
        let deviceIDs = Set(lhs.keys).union(rhs.keys)
        let lhsIsBeforeOrEqual = deviceIDs.allSatisfy { lhs[$0, default: 0] <= rhs[$0, default: 0] }
        let rhsIsBeforeOrEqual = deviceIDs.allSatisfy { rhs[$0, default: 0] <= lhs[$0, default: 0] }

        switch (lhsIsBeforeOrEqual, rhsIsBeforeOrEqual) {
        case (true, true):
            return .equal
        case (true, false):
            return .before
        case (false, true):
            return .after
        case (false, false):
            return .concurrent
        }
    }

    private static func mergeVersionVectors(_ vectors: [String: Int]...) -> [String: Int] {
        vectors.reduce(into: [:]) { merged, vector in
            for (deviceID, counter) in vector {
                merged[deviceID] = max(merged[deviceID, default: 0], counter)
            }
        }
    }

    private func loadRemoteArchiveIfPresent(from folderURL: URL) throws -> TodayMdArchive? {
        let remoteURL = Self.syncArchiveURL(in: folderURL)
        let baseArchive: TodayMdArchive?
        if fileManager.fileExists(atPath: remoteURL.path) {
            let data = try Data(contentsOf: remoteURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            baseArchive = try decoder.decode(TodayMdArchive.self, from: data)
        } else {
            baseArchive = nil
        }

        return try TodayMdObsidianBridge.mergedArchive(
            baseArchive: baseArchive,
            markdownDirectoryURL: Self.markdownArchiveDirectoryURL(in: folderURL),
            fileManager: fileManager
        )
    }

    private func writeArchive(_ archive: TodayMdArchive, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        try data.write(to: url, options: .atomic)
    }

    private func writeConflictBackup(for archive: TodayMdArchive, prefix: String, in folderURL: URL) throws {
        let backupDirectoryURL = Self.conflictBackupsDirectoryURL(in: folderURL)
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = backupDirectoryURL.appendingPathComponent(
            "today-md-\(prefix)-conflict-\(timestamp).json",
            isDirectory: false
        )

        try writeArchive(archive, to: backupURL)
    }

    private func resolvedFolderURL() throws -> URL {
        guard let bookmarkData = persistedState.bookmarkData else {
            throw TodayMdSyncError.folderNotConfigured
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard !isStale else {
                throw TodayMdSyncError.folderRequiresReselection
            }

            return url
        } catch let syncError as TodayMdSyncError {
            disableSyncBecauseFolderBecameUnavailable(syncError)
            throw syncError
        } catch {
            let syncError = TodayMdSyncError.folderRequiresReselection
            disableSyncBecauseFolderBecameUnavailable(syncError)
            throw syncError
        }
    }

    private func disableSyncBecauseFolderBecameUnavailable(_ error: Error) {
        cancelPendingPush()
        pendingConflict = nil
        conflict = nil

        updatePersistedState { state in
            state.bookmarkData = nil
            state.lastKnownFolderPath = nil
            state.lastSyncedRevision = nil
            state.lastSyncedVersionVector = [:]
            state.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state.syncEnabled = false
            state.hasUnsyncedLocalChanges = false
            state.status = .error
        }
    }

    private func scheduleDebouncedPush() {
        cancelPendingPush()

        let workItem = DispatchWorkItem { [weak self] in
            self?.syncNow()
        }

        pushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func cancelPendingPush() {
        pushWorkItem?.cancel()
        pushWorkItem = nil
    }

    private func recordError(_ error: Error) {
        pendingConflict = nil
        conflict = nil

        updatePersistedState { state in
            state.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state.status = .error
        }
    }

    private func updatePersistedState(_ mutate: (inout TodayMdSyncPersistedState) -> Void) {
        mutate(&persistedState)
        applyPersistedState()
        saveState()
    }

    private func applyPersistedState() {
        if persistedState.status == .syncing {
            persistedState.status = persistedState.syncEnabled ? .idle : .disabled
            saveState()
        }

        syncEnabled = persistedState.syncEnabled
        status = persistedState.status
        folderPath = persistedState.lastKnownFolderPath
        lastSyncAt = persistedState.lastSyncAt
        lastError = persistedState.lastError
        hasUnsyncedLocalChanges = persistedState.hasUnsyncedLocalChanges
    }

    private func saveState() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(persistedState) else { return }
        userDefaults.set(data, forKey: Self.persistedStateDefaultsKey)
    }

    private static func loadState(from userDefaults: UserDefaults) -> TodayMdSyncPersistedState {
        guard
            let data = userDefaults.data(forKey: persistedStateDefaultsKey),
            let state = try? JSONDecoder().decode(TodayMdSyncPersistedState.self, from: data)
        else {
            return .initial()
        }

        if state.deviceID.isEmpty {
            return .initial()
        }

        return state
    }

    private func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private func present(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }

        if let window = NSApp.orderedWindows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: finish)
            return
        }

        finish(panel.runModal())
    }

    private static func syncArchiveURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("today-md-sync.json", isDirectory: false)
    }

    private static func markdownArchiveDirectoryURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("Markdown Archive", isDirectory: true)
    }

    private static func conflictBackupsDirectoryURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("Conflict Backups", isDirectory: true)
    }

    private static let persistedStateDefaultsKey = "today-md.sync.state"
}

private enum TodayMdSyncError: LocalizedError {
    case folderNotConfigured
    case folderRequiresReselection
    case remoteSnapshotChanged
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .folderNotConfigured:
            return "Choose a sync folder before trying to sync."
        case .folderRequiresReselection:
            return "The sync folder is no longer available. Choose the folder again to continue syncing."
        case .remoteSnapshotChanged:
            return "The sync snapshot changed while today-md was saving. Your local changes were kept; sync again to resolve the conflict."
        case .storeUnavailable:
            return "The app store is unavailable."
        }
    }
}
