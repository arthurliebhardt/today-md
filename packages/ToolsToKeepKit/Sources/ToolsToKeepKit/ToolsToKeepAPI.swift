import CryptoKit
import Foundation
#if canImport(IOKit)
import IOKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The few server calls an app makes. Short keys need one activation to obtain
/// a signed offline credential. `LicenseCheck` repeats activation about once a
/// week in direct-download apps to catch refunded keys.
public struct ToolsToKeepAPI: Sendable {
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "https://toolstokeep.com")!) {
        self.baseURL = baseURL
    }

    public struct ActivationResult: Decodable, Sendable {
        public let ok: Bool
        public let error: String?
        public let tool: String?
        public let max_devices: Int?
        /// Signed offline credential returned after a license key is activated.
        public let license: String?

        /// For apps that stub activation in tests or previews.
        public init(ok: Bool, error: String?, tool: String?, max_devices: Int?, license: String? = nil) {
            self.ok = ok
            self.error = error
            self.tool = tool
            self.max_devices = max_devices
            self.license = license
        }
    }

    /// Device activation (enforces the license's device limit). Call it when the
    /// user enters a key; `LicenseCheck` calls it again about once a week, which
    /// is a no-op for an already activated device.
    public func activate(key: String, deviceHash: String = DeviceID.hash(), tool: String? = nil) async throws -> ActivationResult {
        var body = ["key": key, "device": deviceHash]
        body["tool"] = tool
        return try await post("api/activate", body)
    }

    public struct RedeemResult: Decodable, Sendable {
        public let ok: Bool
        /// "emailed" or "already_redeemed" on success.
        public let status: String?
        public let error: String?
    }

    /// Turns an App Store purchase into a toolstokeep license, emailed to `email`
    /// (for the Mac version from the website, and the My tools page).
    /// Pass `Transaction.jwsRepresentation` from StoreKit 2.
    public func redeem(transactionJWS: String, email: String) async throws -> RedeemResult {
        try await post("api/apple/redeem", ["transaction": transactionJWS, "email": email])
    }

    public struct Release: Decodable, Sendable {
        public let version: String
        public let platform: String
        public let released_at: String
        public let sha256: String?
        public let notes: String?
    }

    /// Latest release for update prompts. Every license includes it.
    public func latestRelease(tool: String, platform: String = "any") async throws -> Release {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/releases/\(tool)/latest"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "platform", value: platform)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// A stable, anonymous device identifier: SHA-256 of the hardware UUID on macOS,
/// or of identifierForVendor on iOS. Only the hash ever leaves the device.
public enum DeviceID {
    public static func hash() -> String {
        let id = rawID() ?? UUID().uuidString
        return SHA256.hash(data: Data("toolstokeep:\(id)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func rawID() -> String? {
        #if os(macOS)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        #elseif canImport(UIKit)
        return MainActor.assumeIsolated { UIDevice.current.identifierForVendor?.uuidString }
        #else
        return nil
        #endif
    }
}
