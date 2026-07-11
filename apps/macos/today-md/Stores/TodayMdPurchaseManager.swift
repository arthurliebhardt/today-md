import Foundation
import StoreKit

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

    static let lifetimeProductID = "com.today-md.app.pro.lifetime"
    static let storeKitTestingEnvironmentKey = "TODAYMD_STOREKIT_TESTING"

    @Published private(set) var accessState: AccessState
    @Published private(set) var purchaseStatus: PurchaseStatus = .idle
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var message: String?
    @Published var isPaywallPresented = false

    let isCommerceEnabled: Bool

    private var transactionUpdatesTask: Task<Void, Never>?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
#if TODAYMD_APP_STORE
        isCommerceEnabled = true
#else
        isCommerceEnabled = Self.commerceIsEnabled(environment: environment)
#endif
        accessState = isCommerceEnabled ? .checking : .pro

        guard isCommerceEnabled else { return }
        transactionUpdatesTask = observeTransactionUpdates()
    }

    deinit {
        transactionUpdatesTask?.cancel()
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
        guard isCommerceEnabled else { return }

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

    func purchaseLifetime() async {
        guard isCommerceEnabled, !hasProAccess, purchaseStatus == .idle else { return }

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
        guard isCommerceEnabled, purchaseStatus == .idle else { return }

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
        guard isCommerceEnabled else {
            accessState = .pro
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
