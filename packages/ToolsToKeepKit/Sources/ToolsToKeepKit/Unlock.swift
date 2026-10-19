import Foundation
import StoreKit

/// One place to answer "is this tool unlocked?" for every build of an app:
/// - App Store builds (iOS, Mac App Store): a StoreKit non-consumable purchase,
///   or a toolstokeep license bought on the website (allowed under App Review
///   guideline 3.1.3(b) because the same unlock is also sold in the app).
/// - Direct Mac builds (Developer ID, sold on the website): the license key.
public struct Unlock: Sendable {
    public let tool: String
    public let productID: String
    public let verifier: LicenseVerifier
    public let store: LicenseStore

    public init(tool: String, productID: String, publicKeyBase64: String, store: LicenseStore = LicenseStore()) throws {
        self.tool = tool
        self.productID = productID
        self.verifier = try LicenseVerifier(publicKeyBase64: publicKeyBase64)
        self.store = store
    }

    public enum Source: Equatable, Sendable {
        case appStore
        case license(License)
    }

    /// Checks the saved license key first (offline), then StoreKit entitlements.
    public func current() async -> Source? {
        if let key = store.load(tool: tool), let license = try? verifier.verify(key, tool: tool) {
            return .license(license)
        }
        if await appStoreTransaction() != nil { return .appStore }
        return nil
    }

    /// "I already have a license": verifies the key, then stores it.
    @discardableResult
    public func enter(key: String) throws -> License {
        let license = try verifier.verify(key, tool: tool)
        try store.save(key.trimmingCharacters(in: .whitespacesAndNewlines), tool: tool)
        return license
    }

    /// Resolves a short purchase key once, then saves its verified offline credential.
    /// Existing signed keys still work without a network call.
    @discardableResult
    public func enter(
        key: String,
        activate: @Sendable (String) async throws -> ToolsToKeepAPI.ActivationResult
    ) async throws -> License {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LicenseKey.isShort(key) else { return try enter(key: key) }
        let result = try await activate(key)
        guard result.ok else { throw LicenseError.activationFailed(result.error) }
        guard let credential = result.license else { throw LicenseError.malformed }
        return try enter(key: credential)
    }

    /// The verified StoreKit transaction for this tool's unlock, if the user owns it
    /// (purchased, restored or Family Shared; refunded purchases are excluded).
    public func appStoreTransaction() async -> Transaction? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID, transaction.revocationDate == nil {
                return transaction
            }
        }
        return nil
    }

    /// Buys the unlock through the App Store. Returns the signed transaction
    /// (`jwsRepresentation`) so it can be redeemed for a toolstokeep license.
    public func purchase() async throws -> String? {
        guard let product = try await Product.products(for: [productID]).first else { return nil }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else { return nil }
            await transaction.finish()
            return result.jwsRepresentation
        default:
            return nil
        }
    }
}
