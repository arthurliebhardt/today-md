import XCTest
import ToolsToKeepKit
@testable import TodayMdApp

private struct OfflineError: Error {}

@MainActor
final class TodayMdLicenseTests: XCTestCase {
    private var store: LicenseStore!
    private var defaultsSuite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        // A Keychain service and defaults suite of its own per test, removed afterwards.
        store = LicenseStore(service: "com.today-md.app.license.tests.\(UUID().uuidString)")
        defaultsSuite = "com.today-md.app.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
    }

    override func tearDown() async throws {
        store.remove(tool: TodayMdPurchaseManager.licenseTool)
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    private func manager(
        environment: [String: String],
        activation: ToolsToKeepAPI.ActivationResult? = .init(ok: true, error: nil, tool: "todaymd", max_devices: 3)
    ) -> TodayMdPurchaseManager {
        TodayMdPurchaseManager(
            environment: environment,
            licensePublicKey: LicenseFixture.publicKey,
            licenseStore: store,
            activate: { _ in
                guard let activation else { throw OfflineError() }
                return activation
            },
            licenseCheckDefaults: defaults
        )
    }

    private let licensedBuild = [TodayMdPurchaseManager.licensedEnvironmentKey: "1"]
    private let appStoreBuild = [TodayMdPurchaseManager.storeKitTestingEnvironmentKey: "1"]
    private let shortKey = "ttk_abcdefghijklmnopqrstuvwxyz012345"
    private var shortActivation: ToolsToKeepAPI.ActivationResult {
        .init(ok: true, error: nil, tool: "todaymd", max_devices: 3, license: LicenseFixture.todaymdKey)
    }

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

    func testAppStoreEditionNeverContactsToolstokeepForSignedKeys() async {
        let manager = TodayMdPurchaseManager(
            environment: appStoreBuild,
            licensePublicKey: LicenseFixture.publicKey,
            licenseStore: store,
            activate: { _ in
                XCTFail("The App Store edition must verify legacy signed keys offline")
                return .init(ok: false, error: "revoked", tool: nil, max_devices: nil)
            },
            licenseCheckDefaults: defaults
        )
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertTrue(manager.hasProAccess)
    }

    func testShortKeyUnlocksBothEditionsAndStoresAnOfflineCredential() async {
        for environment in [licensedBuild, appStoreBuild] {
            store.remove(tool: TodayMdPurchaseManager.licenseTool)
            let manager = manager(environment: environment, activation: shortActivation)
            await manager.enterLicense("  \(shortKey)\n")
            XCTAssertTrue(manager.hasProAccess)
            XCTAssertEqual(manager.license?.email, "buyer@example.com")
            XCTAssertEqual(store.load(tool: TodayMdPurchaseManager.licenseTool), LicenseFixture.todaymdKey)

            let relaunched = self.manager(environment: environment, activation: nil)
            XCTAssertTrue(relaunched.hasProAccess)
        }
    }

    func testLegacyShortKeyStillUnlocksBothEditions() async {
        for environment in [licensedBuild, appStoreBuild] {
            store.remove(tool: TodayMdPurchaseManager.licenseTool)
            let manager = manager(environment: environment, activation: shortActivation)
            await manager.enterLicense("ttk_abcdefghijklmnopqrstuv")
            XCTAssertTrue(manager.hasProAccess)
            XCTAssertEqual(store.load(tool: TodayMdPurchaseManager.licenseTool), LicenseFixture.todaymdKey)

            let relaunched = self.manager(environment: environment, activation: nil)
            XCTAssertTrue(relaunched.hasProAccess)
        }
    }

    func testShortKeyNeedsInternetBeforeItCanUnlock() async {
        for environment in [licensedBuild, appStoreBuild] {
            let manager = manager(environment: environment, activation: nil)
            await manager.enterLicense(shortKey)
            XCTAssertFalse(manager.hasProAccess)
            XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
            XCTAssertTrue(manager.message?.contains("Connect to the internet") == true)
        }
    }

    func testShortKeyRejectsMissingMalformedAndForgedCredentials() async {
        let forged = String(LicenseFixture.todaymdKey.dropLast(4)) + "AAAA"
        for credential in [nil, "not a certificate", forged] {
            let activation = ToolsToKeepAPI.ActivationResult(ok: true, error: nil, tool: "todaymd", max_devices: 3, license: credential)
            let manager = manager(environment: licensedBuild, activation: activation)
            await manager.enterLicense(shortKey)
            XCTAssertFalse(manager.hasProAccess)
            XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
            XCTAssertNotNil(manager.message)
        }
    }

    func testShortKeyRejectsACredentialForAnotherTool() async {
        let activation = ToolsToKeepAPI.ActivationResult(ok: true, error: nil, tool: "todaymd", max_devices: 3, license: LicenseFixture.otherToolKey)
        let manager = manager(environment: licensedBuild, activation: activation)
        await manager.enterLicense(shortKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
        XCTAssertTrue(manager.message?.contains("different toolstokeep app") == true)
    }

    func testShortKeyReportsRevocationAndDeviceLimit() async {
        let revoked = manager(environment: licensedBuild, activation: .init(ok: false, error: "revoked", tool: nil, max_devices: nil))
        await revoked.enterLicense(shortKey)
        XCTAssertFalse(revoked.hasProAccess)
        XCTAssertTrue(revoked.message?.contains("revoked") == true)

        let limited = manager(environment: licensedBuild, activation: .init(ok: false, error: "device_limit", tool: nil, max_devices: 3))
        await limited.enterLicense(shortKey)
        XCTAssertFalse(limited.hasProAccess)
        XCTAssertTrue(limited.message?.contains("3 Macs") == true)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
    }

    func testMalformedShortKeyDoesNotCallActivation() async {
        let manager = TodayMdPurchaseManager(
            environment: licensedBuild,
            licensePublicKey: LicenseFixture.publicKey,
            licenseStore: store,
            activate: { _ in
                XCTFail("Malformed short keys must be rejected before activation")
                return .init(ok: true, error: nil, tool: "todaymd", max_devices: 3, license: LicenseFixture.todaymdKey)
            },
            licenseCheckDefaults: defaults
        )
        await manager.enterLicense("ttk_too_short")
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
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
        let manager = manager(environment: licensedBuild, activation: .init(ok: false, error: "revoked", tool: nil, max_devices: nil))
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertTrue(manager.message?.contains("revoked") == true)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
    }

    func testDeviceLimitIsReported() async {
        let manager = manager(environment: licensedBuild, activation: .init(ok: false, error: "device_limit", tool: nil, max_devices: 3))
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

    // MARK: Weekly license check

    private let revoked = ToolsToKeepAPI.ActivationResult(ok: false, error: "revoked", tool: nil, max_devices: nil)
    private let nextWeek = Date().addingTimeInterval(8 * 86_400)

    func testRefundedLicenseIsTurnedOffAtTheWeeklyCheck() async {
        await manager(environment: licensedBuild).enterLicense(LicenseFixture.todaymdKey)
        let relaunched = manager(environment: licensedBuild, activation: revoked)

        // Checked when the key was entered, so not due yet.
        await relaunched.checkLicenseIfDue()
        XCTAssertTrue(relaunched.hasProAccess)

        await relaunched.checkLicenseIfDue(now: nextWeek)
        XCTAssertEqual(relaunched.accessState, .free)
        XCTAssertNil(relaunched.license)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
        XCTAssertTrue(relaunched.message?.contains("refunded or revoked") == true)
    }

    func testWeeklyCheckOfflineKeepsPro() async {
        await manager(environment: licensedBuild).enterLicense(LicenseFixture.todaymdKey)
        let relaunched = manager(environment: licensedBuild, activation: nil)
        await relaunched.checkLicenseIfDue(now: nextWeek)
        XCTAssertTrue(relaunched.hasProAccess)
    }

    func testOtherServerAnswersKeepPro() async {
        await manager(environment: licensedBuild).enterLicense(LicenseFixture.todaymdKey)
        let relaunched = manager(environment: licensedBuild, activation: .init(ok: false, error: "rate_limited", tool: nil, max_devices: nil))
        await relaunched.checkLicenseIfDue(now: nextWeek)
        XCTAssertTrue(relaunched.hasProAccess)
    }

    func testAppStoreEditionSkipsTheWeeklyCheck() async {
        await manager(environment: appStoreBuild).enterLicense(LicenseFixture.todaymdKey)
        let relaunched = manager(environment: appStoreBuild, activation: revoked)
        await relaunched.checkLicenseIfDue(now: nextWeek)
        XCTAssertNotNil(relaunched.license)
        XCTAssertNotNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
    }

    func testShortKeyWeeklyCheckUsesTheSavedSignedCredential() async {
        await manager(environment: licensedBuild, activation: shortActivation).enterLicense(shortKey)
        let relaunched = TodayMdPurchaseManager(
            environment: licensedBuild,
            licensePublicKey: LicenseFixture.publicKey,
            licenseStore: store,
            activate: { key in
                XCTAssertEqual(key, LicenseFixture.todaymdKey)
                return .init(ok: false, error: "revoked", tool: nil, max_devices: nil)
            },
            licenseCheckDefaults: defaults
        )
        await relaunched.checkLicenseIfDue(now: nextWeek)
        XCTAssertFalse(relaunched.hasProAccess)
        XCTAssertNil(store.load(tool: TodayMdPurchaseManager.licenseTool))
    }

    func testBuildWithoutPublicKeyExplainsKeysAreNotSetUp() async {
        let manager = TodayMdPurchaseManager(environment: licensedBuild, licensePublicKey: "REPLACE_WITH_LICENSE_PUBLIC_KEY", licenseStore: store)
        XCTAssertFalse(manager.canUseLicenseKeys)
        await manager.enterLicense(LicenseFixture.todaymdKey)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertTrue(manager.message?.contains("aren't set up") == true)
    }
}
