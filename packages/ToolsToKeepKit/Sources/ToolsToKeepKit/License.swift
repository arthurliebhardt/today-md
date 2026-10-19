import CryptoKit
import Foundation

/// A signed offline credential: `TTK1.<base64url JSON>.<base64url Ed25519 signature>`.
/// Checking one needs no network: the signature is verified with the public key
/// built into the app, so a bought copy keeps working if toolstokeep.com is gone.
/// Every license includes all updates. Keys issued before that also carry an
/// `updates_until` date, which is ignored.
public struct License: Codable, Equatable, Sendable {
    public let v: Int
    public let lid: String
    public let tool: String
    public let email: String
    public let issued: String
    public let maxDevices: Int

    enum CodingKeys: String, CodingKey {
        case v, lid, tool, email, issued
        case maxDevices = "max_devices"
    }
}

public enum LicenseError: Error, Equatable {
    case malformed
    case badSignature
    case wrongTool(String)
    case unsupportedVersion(Int)
    case activationFailed(String?)
}

/// Short purchase keys need one online activation to obtain an offline credential.
public enum LicenseKey {
    public static func isShort(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard bytes.count == 26, key.hasPrefix("ttk_") else { return false }
        return bytes.dropFirst(4).allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

public struct LicenseVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey

    /// `publicKeyBase64` is LICENSE_PUBLIC_KEY from the server (raw 32 bytes, base64).
    public init(publicKeyBase64: String) throws {
        guard let raw = Data(base64Encoded: publicKeyBase64) else { throw LicenseError.malformed }
        publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// Verifies the signature and that the key is for `tool` (the slug in the store's catalog).
    public func verify(_ key: String, tool: String) throws -> License {
        let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "TTK1",
              let payload = Data(base64URLEncoded: parts[1]),
              let signature = Data(base64URLEncoded: parts[2])
        else { throw LicenseError.malformed }
        guard publicKey.isValidSignature(signature, for: Data("TTK1.\(parts[1])".utf8)) else { throw LicenseError.badSignature }
        guard let license = try? JSONDecoder().decode(License.self, from: payload) else { throw LicenseError.malformed }
        guard license.v == 1 else { throw LicenseError.unsupportedVersion(license.v) }
        guard license.tool == tool else { throw LicenseError.wrongTool(license.tool) }
        return license
    }
}

extension Data {
    init?(base64URLEncoded text: String) {
        var b64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        self.init(base64Encoded: b64)
    }
}
