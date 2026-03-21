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
        XCTAssertTrue(configuration.shouldRunSyncLifecycle)
        XCTAssertNil(configuration.databaseURL)

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
        XCTAssertTrue(configuration.shouldRunSyncLifecycle)
    }

    func testSwiftRunUsesDedicatedShowcaseDatabaseAndSkipsSyncLifecycle() {
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
        XCTAssertFalse(configuration.shouldRunSyncLifecycle)
        XCTAssertEqual(
            configuration.databaseURL,
            URL(fileURLWithPath: "/Users/test/dev/today-md/.build/debug/today-md-showcase.sqlite")
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
