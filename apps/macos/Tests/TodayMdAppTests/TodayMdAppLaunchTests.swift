import Foundation
import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdAppLaunchTests: XCTestCase {
    func testFirstLaunchSeedsWhenSyncIsDisabled() {
        let userDefaults = makeUserDefaults()

        XCTAssertTrue(TodayMdApp.shouldSeedShowcaseData(syncEnabled: false, userDefaults: userDefaults))

        TodayMdApp.markHasLaunchedBefore(userDefaults: userDefaults)

        XCTAssertFalse(TodayMdApp.shouldSeedShowcaseData(syncEnabled: false, userDefaults: userDefaults))
    }

    func testFirstLaunchDoesNotSeedWhenSyncIsEnabled() {
        let userDefaults = makeUserDefaults()

        XCTAssertFalse(TodayMdApp.shouldSeedShowcaseData(syncEnabled: true, userDefaults: userDefaults))
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
}
