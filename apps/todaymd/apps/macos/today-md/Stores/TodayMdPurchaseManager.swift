import AppKit
import Foundation
import StoreKit
import ToolsToKeepKit

struct TodayMdFreeTierPolicy {
    static let maximumListCount = 1
    static let maximumTaskCount = 5

    static func allows(listCount: Int, taskCount: Int, hasProAccess: Bool) -> Bool {
        hasProAccess || (
            listCount <= maximumListCount
                && taskCount <= maximumTaskCount
        )
    }
}

@MainActor
final class TodayMdPurchaseManager: ObservableObject {
    enum AccessState: Equatable {
        case checking
        case free
        case pro
    }

    enum PurchaseStatus: Equatable {
        case idle
        case purchasing
        case restoring
    }

    /// Which build this is. Decides how Pro is unlocked.
    enum Edition: Equatable {
        /// Mac App Store install (or StoreKit testing): the in-app purchase or a toolstokeep license key.
        case appStore
        /// Direct download from toolstokeep.com, built with TODAYMD_LICENSED: a toolstokeep license key.
        case licensed
        /// Source and GitHub builds: everything included (MIT).
        case openSource
    }

    static let lifetimeProductID = "com.todaymd.app.pro.lifetime"
    static let storeKitTestingEnvironmentKey = "TODAYMD_STOREKIT_TESTING"
    static let licensedEnvironmentKey = "TODAYMD_LICENSED_TESTING"
    /// The tool's slug in the toolstokeep catalog; license keys name it.
    static let licenseTool = "todaymd"
    /// LICENSE_PUBLIC_KEY of toolstokeep.com (raw Ed25519 key, base64). Set it
    /// before shipping a build; until then license keys are reported as not set up.
    nonisolated static let licensePublicKey = "/4v0WKhVcBmftLZv9N73Hzw0DUvaDzOaJmYUo6OUR7g="
    static let storeURL = URL(string: "https://toolstokeep.com/tools/todaymd#pricing")!

#if DEBUG
    /// Debug builds only: test against a local toolstokeep site instead of
    /// toolstokeep.com, with the dev key pair from site/.dev.vars.
    ///   open today-md.app --args -TTKDevServer http://localhost:4321 \
    ///     -TTKDevLicensePublicKey <LICENSE_PUBLIC_KEY>
    nonisolated static var activeLicensePublicKey: String {
        UserDefaults.standard.string(forKey: "TTKDevLicensePublicKey") ?? licensePublicKey
    }
    nonisolated static var api: ToolsToKeepAPI {
        UserDefaults.standard.string(forKey: "TTKDevServer").flatMap(URL.init(string:)).map { ToolsToKeepAPI(baseURL: $0) } ?? ToolsToKeepAPI()
    }
#else
    nonisolated static var activeLicensePublicKey: String { licensePublicKey }
    nonisolated static var api: ToolsToKeepAPI { ToolsToKeepAPI() }
#endif

    @Published private(set) var accessState: AccessState
    @Published private(set) var purchaseStatus: PurchaseStatus = .idle
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var message: String?
    @Published private(set) var license: License?
    @Published private(set) var isActivatingLicense = false
    @Published var isPaywallPresented = false

    let edition: Edition
    var isCommerceEnabled: Bool { edition != .openSource }

    private let verifier: LicenseVerifier?
    private let licenseStore: LicenseStore
    private let activate: @Sendable (String) async throws -> ToolsToKeepAPI.ActivationResult
    private let licenseCheckDefaults: UserDefaults
    private var transactionUpdatesTask: Task<Void, Never>?
    private var licenseCheckTask: Task<Void, Never>?
    private var isCheckingLicense = false
    static let lastLicenseCheckKey = "TodayMdLastLicenseCheck"

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        licensePublicKey: String = TodayMdPurchaseManager.activeLicensePublicKey,
        licenseStore: LicenseStore = LicenseStore(service: "com.today-md.app.license"),
        activate: @escaping @Sendable (String) async throws -> ToolsToKeepAPI.ActivationResult = { key in
            try await TodayMdPurchaseManager.api.activate(key: key, tool: TodayMdPurchaseManager.licenseTool)
        },
        licenseCheckDefaults: UserDefaults = .standard
    ) {
        edition = Self.edition(environment: environment)
        verifier = try? LicenseVerifier(publicKeyBase64: licensePublicKey)
        self.licenseStore = licenseStore
        self.activate = activate
        self.licenseCheckDefaults = licenseCheckDefaults
        accessState = edition == .openSource ? .pro : .checking

        if edition != .openSource {
            license = storedLicense()
            if license != nil { accessState = .pro }
        }
        guard edition == .appStore else {
            if edition == .licensed {
                if license == nil { accessState = .free }
                licenseCheckTask = checkLicenseWhenActivated()
            }
            return
        }
        transactionUpdatesTask = observeTransactionUpdates()
    }

    deinit {
        transactionUpdatesTask?.cancel()
        licenseCheckTask?.cancel()
    }

    var hasProAccess: Bool {
        accessState == .pro
    }

    var isBusy: Bool {
        purchaseStatus != .idle
    }

    var localizedPrice: String? {
        lifetimeProduct?.displayPrice
    }

    static func edition(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appStoreReceiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> Edition {
        if commerceIsEnabled(environment: environment, appStoreReceiptURL: appStoreReceiptURL, fileExists: fileExists) {
            return .appStore
        }
#if TODAYMD_LICENSED
        return .licensed
#else
        return environment[licensedEnvironmentKey] == "1" ? .licensed : .openSource
#endif
    }

    static func commerceIsEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appStoreReceiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> Bool {
        let hasAppStoreReceipt = appStoreReceiptURL.map { fileExists($0.path) } ?? false
        return hasAppStoreReceipt || environment[storeKitTestingEnvironmentKey] == "1"
    }

    func authorizeTaskCreation(currentListCount: Int, currentTaskCount: Int) -> Bool {
        let message = currentListCount > TodayMdFreeTierPolicy.maximumListCount
            ? "Your library is above the free limit of 1 list. Delete down to 1 list or unlock today-md Pro to add more tasks."
            : "The free version supports up to 5 total tasks. Delete a task or unlock today-md Pro for unlimited tasks."

        return authorizeFreeTierUsage(
            listCount: currentListCount,
            taskCount: currentTaskCount + 1,
            message: message
        )
    }

    func authorizeListCreation(currentListCount: Int, currentTaskCount: Int) -> Bool {
        let message = currentTaskCount > TodayMdFreeTierPolicy.maximumTaskCount
            ? "Your library is above the free limit of 5 total tasks. Delete down to 5 tasks or unlock today-md Pro to add another list."
            : "The free version supports 1 list. Delete the existing list or unlock today-md Pro for unlimited lists."

        return authorizeFreeTierUsage(
            listCount: currentListCount + 1,
            taskCount: currentTaskCount,
            message: message
        )
    }

    func authorizeImport(resultingListCount: Int, resultingTaskCount: Int) -> Bool {
        if resultingListCount > TodayMdFreeTierPolicy.maximumListCount {
            return authorizeFreeTierUsage(
                listCount: resultingListCount,
                taskCount: resultingTaskCount,
                message: "This backup would exceed the free limit of 1 list. Unlock today-md Pro to import it without limits."
            )
        }

        return authorizeFreeTierUsage(
            listCount: resultingListCount,
            taskCount: resultingTaskCount,
            message: "This backup would exceed the free limit of 5 total tasks. Unlock today-md Pro to import it without limits."
        )
    }

    func authorizeImport(
        _ archive: TodayMdArchive,
        mode: ImportMode,
        currentListCount: Int,
        currentTaskCount: Int
    ) -> Bool {
        let resultingListCount: Int
        let resultingTaskCount: Int

        switch mode {
        case .merge:
            resultingListCount = currentListCount + archive.lists.count
            resultingTaskCount = currentTaskCount + archive.totalTaskCount
        case .replaceExisting:
            resultingListCount = archive.lists.count
            resultingTaskCount = archive.totalTaskCount
        }

        return authorizeImport(
            resultingListCount: resultingListCount,
            resultingTaskCount: resultingTaskCount
        )
    }

    func prepare() async {
        guard edition == .appStore else {
            await checkLicenseIfDue()
            return
        }

        async let productLoad: Void = loadProduct()
        async let entitlementRefresh: Void = refreshEntitlements()
        _ = await (productLoad, entitlementRefresh)
    }

    func presentPaywall(message: String? = nil) {
        guard !hasProAccess else { return }
        self.message = message
        isPaywallPresented = true
    }

    private func authorizeFreeTierUsage(listCount: Int, taskCount: Int, message: String) -> Bool {
        guard !TodayMdFreeTierPolicy.allows(
            listCount: listCount,
            taskCount: taskCount,
            hasProAccess: hasProAccess
        ) else {
            return true
        }

        presentPaywall(message: message)
        return false
    }

    // MARK: License keys (toolstokeep.com)

    /// Whether this build can check license keys at all.
    var canUseLicenseKeys: Bool { verifier != nil && edition != .openSource }

    /// Short purchase keys need one online activation in either edition. The
    /// signed credential returned by the server is verified and kept for offline
    /// use. Existing signed keys still work offline; only the direct download
    /// checks their activation and device limit with toolstokeep.com.
    func enterLicense(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let verifier else {
            message = "License keys aren't set up in this build yet."
            return
        }
        guard !isActivatingLicense else { return }
        message = nil
        isActivatingLicense = true
        defer { isActivatingLicense = false }

        var credential = key
        let verified: License
        if LicenseKey.isShort(key) {
            let result: ToolsToKeepAPI.ActivationResult
            do {
                result = try await activate(key)
            } catch {
                message = "Connect to the internet to activate this short license key. Once activated, it works offline."
                return
            }
            guard result.ok else {
                message = licenseActivationError(result)
                return
            }
            guard let certificate = result.license else {
                message = "toolstokeep.com didn't return a valid license. Try activating again."
                return
            }
            do {
                verified = try verifier.verify(certificate, tool: Self.licenseTool)
                credential = certificate.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch LicenseError.wrongTool {
                message = "That key is for a different toolstokeep app."
                return
            } catch {
                message = "toolstokeep.com returned a license that couldn't be verified. Try activating again."
                return
            }
        } else {
            do {
                verified = try verifier.verify(key, tool: Self.licenseTool)
            } catch LicenseError.wrongTool {
                message = "That key is for a different toolstokeep app."
                return
            } catch {
                message = "That doesn't look like a valid today-md license key. Paste the whole key from your email."
                return
            }
            if edition == .licensed {
                do {
                    let result = try await activate(key)
                    guard result.ok else {
                        message = licenseActivationError(result, maxDevices: verified.maxDevices)
                        return
                    }
                } catch {
                    // Offline or toolstokeep.com unreachable: the signature is valid, so unlock.
                }
            }
        }

        do {
            try licenseStore.save(credential, tool: Self.licenseTool)
        } catch {
            message = "The license is valid but couldn't be saved to the Keychain."
            return
        }
        license = verified
        accessState = .pro
        licenseCheckDefaults.set(Date(), forKey: Self.lastLicenseCheckKey)
        message = "today-md Pro is unlocked with your license for \(verified.email)."
    }

    private func licenseActivationError(_ result: ToolsToKeepAPI.ActivationResult, maxDevices: Int? = nil) -> String {
        switch result.error {
        case "revoked":
            return "This license was refunded or revoked."
        case "device_limit":
            if let limit = result.max_devices ?? maxDevices {
                return "This license is already active on \(limit) Macs. Email support@todaymd.app to move it."
            }
            return "This license has reached its device limit. Email support@todaymd.app to move it."
        case "wrong_tool":
            return "That key is for a different toolstokeep app."
        default:
            return "toolstokeep.com didn't accept this key. Check that you pasted all of it."
        }
    }

    func removeLicense() async {
        licenseStore.remove(tool: Self.licenseTool)
        licenseCheckDefaults.removeObject(forKey: Self.lastLicenseCheckKey)
        license = nil
        await refreshEntitlements()
    }

    /// Licensed edition: about once a week, asks toolstokeep.com whether the
    /// saved key was refunded, disputed or revoked, and turns Pro off if so.
    /// Offline, or any answer other than "revoked", changes nothing. The App
    /// Store edition never makes this automatic call.
    func checkLicenseIfDue(now: Date = Date()) async {
        guard edition == .licensed, license != nil, !isCheckingLicense,
              let key = licenseStore.load(tool: Self.licenseTool),
              LicenseCheck.isDue(lastChecked: licenseCheckDefaults.object(forKey: Self.lastLicenseCheckKey) as? Date, now: now)
        else { return }
        isCheckingLicense = true
        defer { isCheckingLicense = false }

        let status = await LicenseCheck.status(of: key, activate: activate)
        // The key may have been replaced or removed while the check ran.
        guard licenseStore.load(tool: Self.licenseTool) == key else { return }
        switch status {
        case .valid:
            licenseCheckDefaults.set(now, forKey: Self.lastLicenseCheckKey)
        case .revoked:
            licenseStore.remove(tool: Self.licenseTool)
            licenseCheckDefaults.removeObject(forKey: Self.lastLicenseCheckKey)
            license = nil
            accessState = .free
            message = "Your today-md license was refunded or revoked, so Pro is turned off on this Mac."
        case .unknown:
            break
        }
    }

    func openStore() {
        NSWorkspace.shared.open(Self.storeURL)
    }

    private func storedLicense() -> License? {
        guard let verifier, let key = licenseStore.load(tool: Self.licenseTool) else { return nil }
        return try? verifier.verify(key, tool: Self.licenseTool)
    }

    // MARK: App Store

    func purchaseLifetime() async {
        guard edition == .appStore, !hasProAccess, purchaseStatus == .idle else { return }

        purchaseStatus = .purchasing
        message = nil
        defer { purchaseStatus = .idle }

        if lifetimeProduct == nil {
            await loadProduct()
        }

        guard let lifetimeProduct else {
            message = "The lifetime purchase is temporarily unavailable. Check your internet connection and try again."
            return
        }

        do {
            switch try await lifetimeProduct.purchase() {
            case .success(let verificationResult):
                let transaction = try Self.verified(verificationResult)
                await transaction.finish()
                await refreshEntitlements()

                if hasProAccess {
                    message = "today-md Pro is unlocked for this Apple Account."
                }
            case .pending:
                message = "The purchase is pending approval. Pro will unlock automatically when it completes."
            case .userCancelled:
                break
            @unknown default:
                message = "The App Store returned an unknown purchase result. Please try again."
            }
        } catch {
            message = Self.purchaseErrorMessage(for: error)
        }
    }

    func restorePurchases() async {
        guard edition == .appStore, purchaseStatus == .idle else { return }

        purchaseStatus = .restoring
        message = nil
        defer { purchaseStatus = .idle }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = hasProAccess
                ? "today-md Pro was restored successfully."
                : "No lifetime purchase was found for this Apple Account."
        } catch {
            message = Self.purchaseErrorMessage(for: error)
        }
    }

    func refreshEntitlements() async {
        guard edition != .openSource else {
            accessState = .pro
            return
        }

        license = storedLicense()
        if license != nil {
            accessState = .pro
            return
        }
        guard edition == .appStore else {
            accessState = .free
            return
        }

        var ownsLifetimeProduct = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.lifetimeProductID else { continue }
            guard transaction.revocationDate == nil else { continue }
            ownsLifetimeProduct = true
            break
        }

        accessState = ownsLifetimeProduct ? .pro : .free
    }

    private func loadProduct() async {
        do {
            lifetimeProduct = try await Product.products(for: [Self.lifetimeProductID]).first
            if lifetimeProduct == nil, accessState != .pro {
                message = "The App Store product is not available yet. Confirm its product ID in App Store Connect."
            }
        } catch {
            if accessState != .pro {
                message = Self.purchaseErrorMessage(for: error)
            }
        }
    }

    /// Runs the weekly license check whenever the app comes to the front, so a
    /// Mac that keeps today-md open for weeks is checked too.
    private func checkLicenseWhenActivated() -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard !Task.isCancelled else { return }
                await self?.checkLicenseIfDue()
            }
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    private static func purchaseErrorMessage(for error: Error) -> String {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return "The App Store could not be reached. Check your connection and try again."
            case .notAvailableInStorefront:
                return "The lifetime purchase is not available in this App Store region."
            case .userCancelled:
                return "The purchase was cancelled."
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
