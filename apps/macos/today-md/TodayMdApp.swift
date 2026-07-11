import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct TodayMdApp: App {
    struct LaunchConfiguration {
        let databaseURL: URL?
        let shouldSeedShowcaseData: Bool
        let shouldResetShowcaseData: Bool
        let shouldRunSyncLifecycle: Bool
    }

    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(TodayMdPreferenceKey.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @StateObject private var undoController = AppUndoController()
    @StateObject private var presentationState = AppPresentationState()
    @StateObject private var syncService: TodayMdSyncService
    @StateObject private var calendarService = TodayMdCalendarService()
    @StateObject private var dynamicIslandController = GlobalDynamicIslandController()
    @State private var store: TodayMdStore
    private let shouldRunSyncLifecycle: Bool
    static let hasLaunchedBeforeDefaultsKey = "TodayMdHasLaunchedBefore"

    init() {
        let syncService = TodayMdSyncService()
        let userDefaults = UserDefaults.standard
        let launchConfiguration = Self.makeLaunchConfiguration(
            syncEnabled: syncService.syncEnabled,
            userDefaults: userDefaults,
            bundleURL: Bundle.main.bundleURL,
            executableURL: Bundle.main.executableURL
        )
        shouldRunSyncLifecycle = launchConfiguration.shouldRunSyncLifecycle
        Self.markHasLaunchedBefore(userDefaults: userDefaults)
        _syncService = StateObject(wrappedValue: syncService)
        _store = State(
            initialValue: TodayMdStore(
                databaseURL: launchConfiguration.databaseURL,
                shouldSeedShowcaseData: launchConfiguration.shouldSeedShowcaseData,
                shouldResetShowcaseData: launchConfiguration.shouldResetShowcaseData
            )
        )
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup("today-md", id: TodayMdSceneID.mainWindow) {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
                .environmentObject(syncService)
                .environmentObject(calendarService)
                .environmentObject(undoController)
                .environmentObject(presentationState)
                .environmentObject(dynamicIslandController)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .onAppear {
                    store.configureUndoManager(undoController.manager)
                    dynamicIslandController.attach(store: store)
                    calendarService.refreshIfNeeded()

                    guard shouldRunSyncLifecycle else { return }
                    syncService.attach(store: store)
                    syncService.handleAppLaunchIfNeeded()
                }
        }
        .defaultSize(width: 1500, height: 920)
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                calendarService.refreshIfNeeded()

                guard shouldRunSyncLifecycle else { return }
                syncService.handleAppDidBecomeActive()
            case .inactive, .background:
                store.flushPendingPersistence()
            @unknown default:
                break
            }
        }
        .commands {
            WorkspaceCommands()

            CommandGroup(after: .saveItem) {
                Button("Import...") {
                    TodayMdTransferService.importData(into: store)
                }

                Button("Export...") {
                    TodayMdTransferService.exportData(from: store)
                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    undoController.undo()
                }
                .keyboardShortcut("z")

                Button("Redo") {
                    undoController.redo()
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            }

            CommandGroup(after: .help) {
                Button("Quick Add Task") {
                    dynamicIslandController.presentQuickAdd()
                }
                .keyboardShortcut(KeyEquivalent(QuickAddShortcut.keyEquivalent), modifiers: [.command, .shift])

                Button("Keyboard Shortcuts") {
                    presentationState.presentKeyboardShortcuts()
                }
                .keyboardShortcut("/", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environmentObject(syncService)
                .environmentObject(calendarService)
                .environmentObject(presentationState)
                .environmentObject(dynamicIslandController)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
        }

        MenuBarExtra {
            TodayMdMenuBarExtraView()
                .environment(store)
                .environmentObject(syncService)
                .environmentObject(presentationState)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
        } label: {
            Image(nsImage: TodayMdMenuBarIcon.image)
                .accessibilityLabel("today-md")
        }
        .menuBarExtraStyle(.window)
    }

    static func makeLaunchConfiguration(
        syncEnabled: Bool,
        userDefaults: UserDefaults,
        bundleURL: URL,
        executableURL: URL?
    ) -> LaunchConfiguration {
        if isRunningLocallyFromSwiftRun(bundleURL: bundleURL, executableURL: executableURL) {
            return LaunchConfiguration(
                databaseURL: localSwiftRunShowcaseDatabaseURL(executableURL: executableURL),
                shouldSeedShowcaseData: true,
                shouldResetShowcaseData: true,
                shouldRunSyncLifecycle: false
            )
        }

        return LaunchConfiguration(
            databaseURL: nil,
            shouldSeedShowcaseData: !syncEnabled && !userDefaults.bool(forKey: hasLaunchedBeforeDefaultsKey),
            shouldResetShowcaseData: false,
            shouldRunSyncLifecycle: true
        )
    }

    static func markHasLaunchedBefore(userDefaults: UserDefaults) {
        userDefaults.set(true, forKey: hasLaunchedBeforeDefaultsKey)
    }

    static func isRunningLocallyFromSwiftRun(bundleURL: URL, executableURL: URL?) -> Bool {
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") != .orderedSame else {
            return false
        }

        guard let executableURL else { return false }
        return executableURL.path.contains("/.build/")
    }

    static func localSwiftRunShowcaseDatabaseURL(executableURL: URL?) -> URL? {
        guard let executableURL else { return nil }
        return executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("today-md-showcase.sqlite", isDirectory: false)
    }
}
