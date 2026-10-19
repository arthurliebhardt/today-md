import Foundation

/// The weekly online check for a saved license key. Keys verify offline, so a
/// refund, dispute or manual revocation only reaches an app through this
/// check. Only an explicit "revoked" from the server counts: being offline,
/// rate limited or getting any other answer leaves the license in place.
public enum LicenseCheck {
    public static let interval: TimeInterval = 7 * 24 * 60 * 60

    public enum Status: Equatable, Sendable {
        case valid
        case revoked
        /// No answer that settles it (offline, server error, rate limit). Try again later.
        case unknown
    }

    public static func isDue(lastChecked: Date?, now: Date = Date()) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= interval || lastChecked > now
    }

    /// Asks the server through `activate` (`ToolsToKeepAPI.activate(key:)` in apps).
    public static func status(
        of key: String,
        activate: @Sendable (String) async throws -> ToolsToKeepAPI.ActivationResult
    ) async -> Status {
        guard let result = try? await activate(key) else { return .unknown }
        if result.ok { return .valid }
        return result.error == "revoked" ? .revoked : .unknown
    }
}
