import XCTest
@testable import TodayMdApp

@MainActor
final class TodayMdPurchaseManagerTests: XCTestCase {
    func testOpenSourceBuildIncludesProAccessWithoutCommerce() {
        let manager = TodayMdPurchaseManager(environment: [:])

        XCTAssertFalse(manager.isCommerceEnabled)
        XCTAssertEqual(manager.accessState, .pro)
        XCTAssertTrue(manager.hasProAccess)
    }

    func testStoreKitTestingEnvironmentEnablesCommerceMode() {
        let manager = TodayMdPurchaseManager(
            environment: [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"]
        )

        XCTAssertTrue(manager.isCommerceEnabled)
        XCTAssertEqual(manager.accessState, .checking)
        XCTAssertFalse(manager.hasProAccess)
    }

    func testLifetimeProductIdentifierMatchesSubmissionMetadata() {
        XCTAssertEqual(
            TodayMdPurchaseManager.lifetimeProductID,
            "com.todaymd.app.pro.lifetime"
        )
    }

    func testFreeTierAllowsOneListAndFiveTasks() {
        XCTAssertTrue(
            TodayMdFreeTierPolicy.allows(listCount: 1, taskCount: 5, hasProAccess: false)
        )
        XCTAssertFalse(
            TodayMdFreeTierPolicy.allows(listCount: 2, taskCount: 5, hasProAccess: false)
        )
        XCTAssertFalse(
            TodayMdFreeTierPolicy.allows(listCount: 1, taskCount: 6, hasProAccess: false)
        )
    }

    func testProTierIgnoresListAndTaskLimits() {
        XCTAssertTrue(
            TodayMdFreeTierPolicy.allows(listCount: 50, taskCount: 5_000, hasProAccess: true)
        )
    }

    func testSixthTaskPresentsLifetimeUpgrade() {
        let manager = TodayMdPurchaseManager(
            environment: [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"]
        )

        XCTAssertTrue(manager.authorizeTaskCreation(currentListCount: 1, currentTaskCount: 4))
        XCTAssertFalse(manager.authorizeTaskCreation(currentListCount: 1, currentTaskCount: 5))
        XCTAssertTrue(manager.isPaywallPresented)
        XCTAssertTrue(manager.message?.contains("5 total tasks") == true)
    }

    func testSecondListPresentsLifetimeUpgrade() {
        let manager = TodayMdPurchaseManager(
            environment: [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"]
        )

        XCTAssertTrue(manager.authorizeListCreation(currentListCount: 0, currentTaskCount: 5))
        XCTAssertFalse(manager.authorizeListCreation(currentListCount: 1, currentTaskCount: 5))
        XCTAssertTrue(manager.isPaywallPresented)
        XCTAssertTrue(manager.message?.contains("1 list") == true)
    }

    func testExistingOverLimitLibraryCannotCreateMoreFreeContent() {
        let manager = TodayMdPurchaseManager(
            environment: [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"]
        )

        XCTAssertFalse(manager.authorizeTaskCreation(currentListCount: 2, currentTaskCount: 1))
        XCTAssertTrue(manager.message?.contains("above the free limit of 1 list") == true)

        manager.isPaywallPresented = false
        XCTAssertFalse(manager.authorizeListCreation(currentListCount: 0, currentTaskCount: 6))
        XCTAssertTrue(manager.message?.contains("above the free limit of 5 total tasks") == true)
    }

    func testReceiptOrTestingEnvironmentEnablesCommerce() {
        XCTAssertTrue(
            TodayMdPurchaseManager.commerceIsEnabled(
                environment: [:],
                appStoreReceiptURL: URL(fileURLWithPath: "/tmp/receipt"),
                fileExists: { _ in true }
            )
        )
        XCTAssertTrue(
            TodayMdPurchaseManager.commerceIsEnabled(
                environment: [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"],
                appStoreReceiptURL: nil,
                fileExists: { _ in false }
            )
        )
    }
}
