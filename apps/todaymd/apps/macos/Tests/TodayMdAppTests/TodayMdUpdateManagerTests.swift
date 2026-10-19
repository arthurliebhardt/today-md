import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdUpdateManagerTests: XCTestCase {
    func testReleaseAppRequiresAValidFeedAndPublicKey() {
        XCTAssertNil(configuration().unavailableReason)

        for feed in ["http://example.com/appcast.xml", "", "$(SPARKLE_FEED_URL)", "https://user:password@example.com/appcast.xml"] {
            XCTAssertNotNil(configuration(overrides: ["SUFeedURL": feed]).unavailableReason)
        }
        for key in ["", "$(SPARKLE_PUBLIC_ED_KEY)", Data(repeating: 1, count: 31).base64EncodedString(), "invalid-key"] {
            XCTAssertNotNil(configuration(overrides: ["SUPublicEDKey": key]).unavailableReason)
        }
    }

    func testUpdatesNeverStartForAppStoreOrDevelopmentDistributions() {
        for distribution in [TodayMdUpdateConfiguration.Distribution.appStore, .development] {
            let configuration = configuration(distribution: distribution)
            XCTAssertNotNil(configuration.unavailableReason)
            let manager = TodayMdUpdateManager(configuration: configuration)
            manager.start()
            manager.checkForUpdates()
            manager.setAutomaticallyChecksForUpdates(true)
            XCTAssertFalse(manager.isUpdaterReady)
            XCTAssertFalse(manager.canCheckForUpdates)
            XCTAssertFalse(manager.automaticallyChecksForUpdates)
        }
    }

    func testDebugAndSwiftPackageExecutablesCannotStartUpdates() {
        XCTAssertNotNil(configuration(isDebugBuild: true).unavailableReason)
        XCTAssertNotNil(configuration(bundleURL: URL(fileURLWithPath: "/tmp/.build/debug/today-md")).unavailableReason)
    }

    func testMissingOrUnexpandedVersionMetadataDisablesUpdates() {
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            XCTAssertNotNil(configuration(overrides: [key: ""]).unavailableReason)
            XCTAssertNotNil(configuration(overrides: [key: "$(CURRENT_PROJECT_VERSION)"]).unavailableReason)
        }
    }

    func testCurrentVersionIncludesMarketingAndBuildVersions() {
        XCTAssertEqual(configuration().versionDescription, "Version 1.2.3 (42)")
        XCTAssertEqual(configuration(overrides: ["CFBundleVersion": ""]).versionDescription, "Version 1.2.3")
        XCTAssertEqual(configuration(overrides: ["CFBundleShortVersionString": ""]).versionDescription, "Development build")
    }

    func testAppStoreAndSwiftPackageBuildsHaveNoUpdatesSettingsSection() {
#if TODAYMD_GITHUB && !TODAYMD_APP_STORE
        XCTAssertTrue(SettingsSection.allCases.contains { $0.rawValue == "updates" })
#else
        XCTAssertFalse(SettingsSection.allCases.contains { $0.rawValue == "updates" })
#endif
    }

    private func configuration(
        distribution: TodayMdUpdateConfiguration.Distribution = .github,
        bundleURL: URL = URL(fileURLWithPath: "/Applications/today-md.app"),
        isDebugBuild: Bool = false,
        overrides: [String: String] = [:]
    ) -> TodayMdUpdateConfiguration {
        var info = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42"
        ]
        info.merge(overrides) { _, override in override }
        return TodayMdUpdateConfiguration(
            distribution: distribution,
            bundleURL: bundleURL,
            infoDictionary: info,
            isDebugBuild: isDebugBuild
        )
    }
}
