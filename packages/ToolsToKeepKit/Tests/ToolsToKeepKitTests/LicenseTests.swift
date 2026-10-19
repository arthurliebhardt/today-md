import Testing
@testable import ToolsToKeepKit

@Suite struct LicenseTests {
    let verifier = try! LicenseVerifier(publicKeyBase64: Fixture.publicKey)

    @Test func verifiesAKeySignedByTheServer() throws {
        let license = try verifier.verify(Fixture.recorderKey, tool: "recorder")
        #expect(license.email == "buyer@example.com")
        #expect(license.updatesUntil == "2027-10-18")
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

    @Test func updatesFollowTheUpdateWindow() throws {
        let license = try verifier.verify(Fixture.recorderKey, tool: "recorder")
        #expect(license.includesUpdate(releasedOn: "2027-01-01"))
        #expect(!license.includesUpdate(releasedOn: "2028-01-01"))
    }

    @Test func deviceHashIsStableHex() {
        #expect(DeviceID.hash() == DeviceID.hash())
        #expect(DeviceID.hash().count == 64)
    }
}
