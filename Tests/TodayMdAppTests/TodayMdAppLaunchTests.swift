import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdAppLaunchTests: XCTestCase {
    func testFirstLaunchSeedsWhenSyncIsDisabled() {
        let userDefaults = makeUserDefaults()
        let configuration = TodayMdApp.makeLaunchConfiguration(
            syncEnabled: false,
            userDefaults: userDefaults,
            bundleURL: appBundleURL(),
            executableURL: appExecutableURL()
        )

        XCTAssertTrue(configuration.shouldSeedShowcaseData)
        XCTAssertFalse(configuration.shouldResetShowcaseData)
        XCTAssertFalse(configuration.shouldResetLocalMarkdownArchive)
        XCTAssertTrue(configuration.shouldRunSyncLifecycle)
        XCTAssertNil(configuration.databaseURL)
        XCTAssertNil(configuration.localMarkdownArchiveDirectoryURL)

        TodayMdApp.markHasLaunchedBefore(userDefaults: userDefaults)
        let secondLaunchConfiguration = TodayMdApp.makeLaunchConfiguration(
            syncEnabled: false,
            userDefaults: userDefaults,
            bundleURL: appBundleURL(),
            executableURL: appExecutableURL()
        )

        XCTAssertFalse(secondLaunchConfiguration.shouldSeedShowcaseData)
    }

    func testFirstLaunchDoesNotSeedWhenSyncIsEnabled() {
        let userDefaults = makeUserDefaults()
        let configuration = TodayMdApp.makeLaunchConfiguration(
            syncEnabled: true,
            userDefaults: userDefaults,
            bundleURL: appBundleURL(),
            executableURL: appExecutableURL()
        )

        XCTAssertFalse(configuration.shouldSeedShowcaseData)
        XCTAssertFalse(configuration.shouldResetShowcaseData)
        XCTAssertFalse(configuration.shouldResetLocalMarkdownArchive)
        XCTAssertTrue(configuration.shouldRunSyncLifecycle)
        XCTAssertNil(configuration.localMarkdownArchiveDirectoryURL)
    }

    func testSwiftRunUsesDedicatedShowcaseStorageAndSkipsSyncLifecycle() {
        let userDefaults = makeUserDefaults()
        TodayMdApp.markHasLaunchedBefore(userDefaults: userDefaults)
        let configuration = TodayMdApp.makeLaunchConfiguration(
            syncEnabled: false,
            userDefaults: userDefaults,
            bundleURL: swiftRunBundleURL(),
            executableURL: swiftRunExecutableURL()
        )

        XCTAssertTrue(configuration.shouldSeedShowcaseData)
        XCTAssertTrue(configuration.shouldResetShowcaseData)
        XCTAssertTrue(configuration.shouldResetLocalMarkdownArchive)
        XCTAssertFalse(configuration.shouldRunSyncLifecycle)
        XCTAssertEqual(
            configuration.databaseURL,
            URL(fileURLWithPath: "/Users/test/dev/today-md/.build/debug/today-md-showcase.sqlite")
        )
        XCTAssertEqual(
            configuration.localMarkdownArchiveDirectoryURL,
            URL(fileURLWithPath: "/Users/test/dev/today-md/.build/debug/today-md-showcase-markdown", isDirectory: true)
        )
    }

    func testSwiftRunDetectionRequiresSwiftPackageBuildPath() {
        XCTAssertFalse(
            TodayMdApp.isRunningLocallyFromSwiftRun(
                bundleURL: swiftRunBundleURL(),
                executableURL: URL(fileURLWithPath: "/tmp/today-md")
            )
        )
    }

    func testSwiftRunShowcaseDatabaseRequiresExecutableURL() {
        XCTAssertNil(TodayMdApp.localSwiftRunShowcaseDatabaseURL(executableURL: nil))
    }

    func testSwiftRunShowcaseMarkdownArchiveRequiresExecutableURL() {
        XCTAssertNil(TodayMdApp.localSwiftRunShowcaseMarkdownArchiveDirectoryURL(executableURL: nil))
    }

    func testPrepareLocalMarkdownArchiveResetsExistingDirectoryWhenRequested() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveURL = rootURL.appendingPathComponent("today-md-showcase-markdown", isDirectory: true)

        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        let staleFileURL = archiveURL.appendingPathComponent("stale.md", isDirectory: false)
        try "stale".write(to: staleFileURL, atomically: true, encoding: .utf8)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try TodayMdApp.prepareLocalMarkdownArchive(at: archiveURL, shouldReset: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFileURL.path))
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "TodayMdAppLaunchTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        return userDefaults
    }

    private func appBundleURL() -> URL {
        URL(fileURLWithPath: "/Applications/today-md.app")
    }

    private func appExecutableURL() -> URL {
        appBundleURL().appendingPathComponent("Contents/MacOS/today-md")
    }

    private func swiftRunBundleURL() -> URL {
        URL(fileURLWithPath: "/Users/test/dev/today-md/.build/debug")
    }

    private func swiftRunExecutableURL() -> URL {
        swiftRunBundleURL().appendingPathComponent("today-md")
    }
}
