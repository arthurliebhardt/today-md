import CryptoKit
import Foundation
import Testing
@testable import ToolsToKeepKit

@Suite struct LifetimeLicenseTests {
    @Test func verifiesSignedLifetimeKeyWithoutAnUpdateWindow() throws {
        let fixture = SignedLicenseFixture()
        let license = try fixture.verifier().verify(fixture.key(), tool: "todaymd")

        #expect(license.lid == "lic_lifetime_fixture")
        #expect(license.email == "buyer@example.com")
        #expect(license.maxDevices == 3)
        #expect(license.updatesUntil == nil)
        #expect(license.includesUpdate(releasedOn: "9999-12-31"))
    }

    @Test func verifiesSignedLifetimeKeyWithANullUpdateWindow() throws {
        var fixture = SignedLicenseFixture()
        fixture.payload["updates_until"] = NSNull()
        let license = try fixture.verifier().verify(fixture.key(), tool: "todaymd")

        #expect(license.updatesUntil == nil)
        #expect(license.includesUpdate(releasedOn: "9999-12-31"))
    }

    @Test func lifetimeKeyStillRequiresTheExpectedTool() throws {
        let fixture = SignedLicenseFixture()
        let verifier = try fixture.verifier()
        let key = try fixture.key()

        #expect(throws: LicenseError.wrongTool("todaymd")) {
            try verifier.verify(key, tool: "recorder")
        }
    }

    @Test func lifetimeKeyStillRequiresTheTrustedIssuer() throws {
        let fixture = SignedLicenseFixture()
        let otherIssuer = SignedLicenseFixture()
        let verifier = try otherIssuer.verifier()
        let key = try fixture.key()

        #expect(throws: LicenseError.badSignature) {
            try verifier.verify(key, tool: "todaymd")
        }
    }

    @Test func lifetimeKeyRejectsTamperedIdentity() throws {
        let fixture = SignedLicenseFixture()
        let verifier = try fixture.verifier()
        let parts = try fixture.key().split(separator: ".")
        var forgedPayload = fixture.payload
        forgedPayload["email"] = "other@example.com"
        let forged = "TTK1.\(try SignedLicenseFixture.encodedPayload(forgedPayload)).\(parts[2])"

        #expect(throws: LicenseError.badSignature) {
            try verifier.verify(forged, tool: "todaymd")
        }
    }

    @Test func lifetimeKeyStillRequiresASupportedVersion() throws {
        var fixture = SignedLicenseFixture()
        fixture.payload["v"] = 2
        let verifier = try fixture.verifier()
        let key = try fixture.key()

        #expect(throws: LicenseError.unsupportedVersion(2)) {
            try verifier.verify(key, tool: "todaymd")
        }
    }

    @Test(arguments: ["v", "lid", "tool", "email", "issued", "max_devices"])
    func lifetimeKeyStillRequiresIdentityFields(_ field: String) throws {
        var fixture = SignedLicenseFixture()
        fixture.payload.removeValue(forKey: field)
        let verifier = try fixture.verifier()
        let key = try fixture.key()

        #expect(throws: LicenseError.malformed) {
            try verifier.verify(key, tool: "todaymd")
        }
    }

    @Test func rejectsANonStringUpdateWindow() throws {
        var fixture = SignedLicenseFixture()
        fixture.payload["updates_until"] = 20271019
        let verifier = try fixture.verifier()
        let key = try fixture.key()

        #expect(throws: LicenseError.malformed) {
            try verifier.verify(key, tool: "todaymd")
        }
    }
}

private struct SignedLicenseFixture {
    private let signingKey = Curve25519.Signing.PrivateKey()
    var payload: [String: Any] = [
        "v": 1,
        "lid": "lic_lifetime_fixture",
        "tool": "todaymd",
        "email": "buyer@example.com",
        "issued": "2026-10-19",
        "max_devices": 3,
    ]

    func verifier() throws -> LicenseVerifier {
        try LicenseVerifier(publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString())
    }

    func key() throws -> String {
        let message = "TTK1.\(try Self.encodedPayload(payload))"
        let signature = try signingKey.signature(for: Data(message.utf8))
        return "\(message).\(Self.base64URL(signature))"
    }

    static func encodedPayload(_ payload: [String: Any]) throws -> String {
        base64URL(try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
