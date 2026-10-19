import XCTest
import ToolsToKeepKit
@testable import TodayMdApp

private struct OfflineError: Error {}

@MainActor
final class TodayMdLicenseTests: XCTestCase {
    private var store: LicenseStore!

    override func setUp() async throws {
        // A Keychain service of its own per test, removed afterwards.
        store = LicenseStore(service: "com.today-md.app.license.tests.\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        store.remove(tool: TodayMdPurchaseManager.licenseTool)
    }

    private func manager(
        environment: [String: String],
        activation: ToolsToKeepAPI.ActivationResult? = .init(ok: true, error: nil, tool: "todaymd", updates_until: "2027-10-18", max_devices: 3)
    ) -> TodayMdPurchaseManager {
        TodayMdPurchaseManager(
            environment: environment,
            licensePublicKey: LicenseFixture.publicKey,
            licenseStore: store,
            activate: { _ in
                guard let activation else { throw OfflineError() }
                return activation
            }
        )
    }

    private let licensedBuild = [TodayMdPurchaseManager.licensedEnvironmentKey: "1"]
    private let appStoreBuild = [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"]

    func testOpenSourceBuildStaysFullyUnlocked() {
        let manager = manager(environment: [:])
        XCTAssertEqual(manager.edition, .openSource)
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertFalse(manager.canUseLicenseKeys)
    }

    func testLicensedBuildStartsFreeWithoutAKey() {
        let manager = manager(environment: licensedBuild)
        XCTAssertEqual(manager.edition, .licensed)
        XCTAssertEqual(manager.accessState, .free)
        XCTAssertTrue(manager.canUseLicenseKeys)
    }

    func testValidKeyUnlocksProAndIsRemembered() async {
        let manager = manager(environment: licensedBuild)
        await manager.enterLicense("  \(LicenseFixture.todaymdKey)\n")

        XCTAssertTrue(manager.hasProAccess)
        XCTAssertEqual(manager.license?.email, "buyer@example.com")

        // A new launch reads the key back from the Keychain and checks it offline.
        let relaunched = self.manager(environment: licensedBuild)
        XCTAssertTrue(relaunched.hasProAccess)
    }

    func testKeyUnlocksTheAppStoreEditionToo() async {
        let manager = manager(environment: appStoreBuild)
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertTrue(manager.hasProAccess)
    }

    func testAppStoreEditionNeverContactsToolstokeep() async {
        // A revoking server would refuse the key; the App Store edition must not ask it at all.
        let manager = manager(environment: appStoreBuild, activation: .init(ok: false, error: "revoked", tool: nil, updates_until: nil, max_devices: nil))
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertTrue(manager.hasProAccess)
    }

    func testKeyForAnotherToolIsRefused() async {
        let manager = manager(environment: licensedBuild)
        await manager.enterLicense(LicenseFixture.otherToolKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertTrue(manager.message?.contains("different toolstokeep app") == true)
    }

    func testTamperedKeyIsRefused() async {
        let manager = manager(environment: licensedBuild)
        await manager.enterLicense(String(LicenseFixture.todaymdKey.dropLast(4)) + "AAAA")
        XCTAssertFalse(manager.hasProAccess)
    }

    func testRevokedLicenseIsRefused() async {
        let manager = manager(environment: licensedBuild, activation: .init(ok: false, error: "revoked", tool: nil, updates_until: nil, max_devices: nil))
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertTrue(manager.message?.contains("revoked") == true)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
    }

    func testDeviceLimitIsReported() async {
        let manager = manager(environment: licensedBuild, activation: .init(ok: false, error: "device_limit", tool: nil, updates_until: nil, max_devices: 3))
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertTrue(manager.message?.contains("3 Macs") == true)
    }

    func testValidKeyWorksOffline() async {
        let manager = manager(environment: licensedBuild, activation: nil)
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertTrue(manager.hasProAccess)
    }

    func testRemovingTheLicenseLocksTheLicensedBuildAgain() async {
        let manager = manager(environment: licensedBuild)
        await manager.enterLicense(LicenseFixture.todaymdKey)
        await manager.removeLicense()
        XCTAssertEqual(manager.accessState, .free)
        XCTAssertNil(manager.license)
    }

    func testBuildWithoutPublicKeyExplainsKeysAreNotSetUp() async {
        let manager = TodayMdPurchaseManager(environment: licensedBuild, licensePublicKey: "REPLACE_WITH_LICENSE_PUBLIC_KEY", licenseStore: store)
        XCTAssertFalse(manager.canUseLicenseKeys)
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertTrue(manager.message?.contains("aren't set up") == true)
    }
}
