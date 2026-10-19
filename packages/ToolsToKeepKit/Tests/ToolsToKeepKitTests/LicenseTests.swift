import Foundation
import Testing
@testable import ToolsToKeepKit

@Suite struct LicenseTests {
    let verifier = try! LicenseVerifier(publicKeyBase64: Fixture.publicKey)

    // The fixture predates lifetime updates and still carries updates_until.
    @Test func verifiesAKeySignedByTheServer() throws {
        let license = try verifier.verify(Fixture.recorderKey, tool: "recorder")
        #expect(license.email == "buyer@example.com")
        #expect(license.maxDevices == 3)
    }

    @Test func toleratesSurroundingWhitespace() throws {
        _ = try verifier.verify("  \(Fixture.recorderKey)\n", tool: "recorder")
    }

    @Test func rejectsAKeyForAnotherTool() {
        #expect(throws: LicenseError.wrongTool("recorder")) { try verifier.verify(Fixture.recorderKey, tool: "invoicing") }
    }

    @Test func rejectsATamperedPayload() {
        let parts = Fixture.recorderKey.split(separator: ".")
        let forged = "TTK1.\(parts[1].dropLast(2))AA.\(parts[2])"
        #expect(throws: (any Error).self) { try verifier.verify(forged, tool: "recorder") }
    }

    @Test func rejectsATamperedSignature() {
        let forged = String(Fixture.recorderKey.dropLast(4)) + "AAAA"
        #expect(throws: LicenseError.badSignature) { try verifier.verify(forged, tool: "recorder") }
    }

    @Test func rejectsAnotherPublisher() throws {
        let other = try LicenseVerifier(publicKeyBase64: "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=")
        #expect(throws: LicenseError.badSignature) { try other.verify(Fixture.recorderKey, tool: "recorder") }
    }

    @Test func rejectsGarbage() {
        #expect(throws: LicenseError.malformed) { try verifier.verify("not a key", tool: "recorder") }
    }

    @Test func recognizesOnlyCompleteShortKeys() {
        #expect(LicenseKey.isShort("ttk_abcdefghijklmnopqrstuvwxyz012345"))
        #expect(LicenseKey.isShort("ttk_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123_-"))
        #expect(LicenseKey.isShort("ttk_abcdefghijklmnopqrstuv"))
        #expect(LicenseKey.isShort("ttk_Abcdef0123456789_-ABCD"))
        for length in 0...40 {
            #expect(LicenseKey.isShort("ttk_" + String(repeating: "a", count: length)) == (length == 22 || length == 32))
        }
        for length in [22, 32] {
            let payload = String(repeating: "a", count: length - 1)
            for invalid in ["!", "=", "+", "/", ".", " ", "\n", "é"] {
                #expect(!LicenseKey.isShort("ttk_" + payload + invalid))
            }
            #expect(!LicenseKey.isShort("TTK_" + payload + "a"))
        }
    }

    @Test func activationResultDecodesOptionalOfflineCredential() throws {
        let data = try JSONSerialization.data(withJSONObject: ["ok": true, "license": Fixture.recorderKey])
        let result = try JSONDecoder().decode(ToolsToKeepAPI.ActivationResult.self, from: data)
        #expect(result.license == Fixture.recorderKey)
        let legacy = try JSONDecoder().decode(ToolsToKeepAPI.ActivationResult.self, from: Data("{\"ok\":true}".utf8))
        #expect(legacy.license == nil)
    }

    @Test func shortKeySavesTheVerifiedCredentialForOfflineUse() async throws {
        let store = LicenseStore(service: "com.toolstokeep.tests.\(UUID().uuidString)")
        defer { store.remove(tool: "recorder") }
        let unlock = try Unlock(tool: "recorder", productID: "test", publicKeyBase64: Fixture.publicKey, store: store)
        let license = try await unlock.enter(key: "  ttk_abcdefghijklmnopqrstuvwxyz012345\n") { key in
            #expect(key == "ttk_abcdefghijklmnopqrstuvwxyz012345")
            return .init(ok: true, error: nil, tool: "recorder", max_devices: 3, license: Fixture.recorderKey)
        }
        #expect(license.email == "buyer@example.com")
        #expect(store.load(tool: "recorder") == Fixture.recorderKey)
        #expect(await unlock.current() == .license(license))
    }

    @Test func legacyShortKeyStillExchangesForAnOfflineCredential() async throws {
        let store = LicenseStore(service: "com.toolstokeep.tests.\(UUID().uuidString)")
        defer { store.remove(tool: "recorder") }
        let unlock = try Unlock(tool: "recorder", productID: "test", publicKeyBase64: Fixture.publicKey, store: store)
        let license = try await unlock.enter(key: "ttk_abcdefghijklmnopqrstuv") { key in
            #expect(key == "ttk_abcdefghijklmnopqrstuv")
            return .init(ok: true, error: nil, tool: "recorder", max_devices: 3, license: Fixture.recorderKey)
        }
        #expect(license.email == "buyer@example.com")
        #expect(store.load(tool: "recorder") == Fixture.recorderKey)
        #expect(await unlock.current() == .license(license))
    }

    @Test func shortKeyRejectsUnverifiedCertificates() async throws {
        let store = LicenseStore(service: "com.toolstokeep.tests.\(UUID().uuidString)")
        defer { store.remove(tool: "recorder") }
        let unlock = try Unlock(tool: "recorder", productID: "test", publicKeyBase64: Fixture.publicKey, store: store)
        let tampered = String(Fixture.recorderKey.dropLast(4)) + "AAAA"
        for credential in [nil, "not a certificate", tampered] {
            await #expect(throws: (any Error).self) {
                try await unlock.enter(key: "ttk_abcdefghijklmnopqrstuvwxyz012345") { _ in
                    .init(ok: true, error: nil, tool: "recorder", max_devices: 3, license: credential)
                }
            }
            #expect(store.load(tool: "recorder") == nil)
        }
        let otherTool = try Unlock(tool: "other", productID: "test", publicKeyBase64: Fixture.publicKey, store: store)
        await #expect(throws: LicenseError.wrongTool("recorder")) {
            try await otherTool.enter(key: "ttk_abcdefghijklmnopqrstuvwxyz012345") { _ in
                .init(ok: true, error: nil, tool: "other", max_devices: 3, license: Fixture.recorderKey)
            }
        }
        #expect(store.load(tool: "other") == nil)
    }

    @Test func shortKeyCannotUnlockOfflineOrWhenActivationIsRefused() async throws {
        let store = LicenseStore(service: "com.toolstokeep.tests.\(UUID().uuidString)")
        defer { store.remove(tool: "recorder") }
        let unlock = try Unlock(tool: "recorder", productID: "test", publicKeyBase64: Fixture.publicKey, store: store)
        await #expect(throws: (any Error).self) {
            try await unlock.enter(key: "ttk_abcdefghijklmnopqrstuvwxyz012345") { _ in throw URLError(.notConnectedToInternet) }
        }
        await #expect(throws: LicenseError.activationFailed("revoked")) {
            try await unlock.enter(key: "ttk_abcdefghijklmnopqrstuvwxyz012345") { _ in
                .init(ok: false, error: "revoked", tool: nil, max_devices: nil, license: Fixture.recorderKey)
            }
        }
        #expect(store.load(tool: "recorder") == nil)
    }

    @Test func asyncEntryKeepsLegacyKeysOffline() async throws {
        let store = LicenseStore(service: "com.toolstokeep.tests.\(UUID().uuidString)")
        defer { store.remove(tool: "recorder") }
        let unlock = try Unlock(tool: "recorder", productID: "test", publicKeyBase64: Fixture.publicKey, store: store)
        let license = try await unlock.enter(key: Fixture.recorderKey) { _ in
            Issue.record("Legacy key entry must not contact the activation server")
            throw URLError(.notConnectedToInternet)
        }
        #expect(license.email == "buyer@example.com")
    }

    @Test func checkIsDueWeekly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(LicenseCheck.isDue(lastChecked: nil, now: now))
        #expect(!LicenseCheck.isDue(lastChecked: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(LicenseCheck.isDue(lastChecked: now.addingTimeInterval(-7 * 86_400), now: now))
        // A clock set back must not postpone the check forever.
        #expect(LicenseCheck.isDue(lastChecked: now.addingTimeInterval(86_400), now: now))
    }

    @Test func onlyAnExplicitRevocationRevokes() async {
        func answer(_ ok: Bool, _ error: String?) -> @Sendable (String) async throws -> ToolsToKeepAPI.ActivationResult {
            { _ in ToolsToKeepAPI.ActivationResult(ok: ok, error: error, tool: "recorder", max_devices: 3) }
        }
        #expect(await LicenseCheck.status(of: Fixture.recorderKey, activate: answer(true, nil)) == .valid)
        #expect(await LicenseCheck.status(of: Fixture.recorderKey, activate: answer(false, "revoked")) == .revoked)
        #expect(await LicenseCheck.status(of: Fixture.recorderKey, activate: answer(false, "rate_limited")) == .unknown)
        #expect(await LicenseCheck.status(of: Fixture.recorderKey, activate: answer(false, "device_limit")) == .unknown)
        #expect(await LicenseCheck.status(of: Fixture.recorderKey) { _ in throw URLError(.notConnectedToInternet) } == .unknown)
    }

    @Test func deviceHashIsStableHex() {
        #expect(DeviceID.hash() == DeviceID.hash())
        #expect(DeviceID.hash().count == 64)
    }
}
