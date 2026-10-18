import Combine
import Foundation

#if TODAYMD_GITHUB && !TODAYMD_APP_STORE && canImport(Sparkle)
import Sparkle
#endif

struct TodayMdUpdateConfiguration {
    enum Distribution {
        case github
        case appStore
        case development
    }

    static var currentDistribution: Distribution {
#if TODAYMD_APP_STORE
        .appStore
#elseif TODAYMD_GITHUB
        .github
#else
        .development
#endif
    }

    static var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    let distribution: Distribution
    let bundleURL: URL
    let infoDictionary: [String: Any]
    let isDebugBuild: Bool

    init(
        distribution: Distribution = Self.currentDistribution,
        bundleURL: URL = Bundle.main.bundleURL,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        isDebugBuild: Bool = Self.isDebugBuild
    ) {
        self.distribution = distribution
        self.bundleURL = bundleURL
        self.infoDictionary = infoDictionary
        self.isDebugBuild = isDebugBuild
    }

    var unavailableReason: String? {
        guard distribution == .github else {
            return "Updates are provided by the distribution where you installed today-md."
        }
        guard !isDebugBuild else {
            return "Updates are available in release builds downloaded from GitHub."
        }
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return "Install the today-md app from GitHub to enable updates."
        }
        guard let feed = infoDictionary["SUFeedURL"] as? String,
              let components = URLComponents(string: feed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              !feed.contains("$("), components.url != nil else {
            return "The update feed is missing or invalid. Download a new copy from GitHub."
        }
        guard let publicKey = infoDictionary["SUPublicEDKey"] as? String,
              let keyData = Data(base64Encoded: publicKey), keyData.count == 32 else {
            return "The update signing key is missing or invalid. Download a new copy from GitHub."
        }
        guard versionString(for: "CFBundleShortVersionString") != nil,
              versionString(for: "CFBundleVersion") != nil else {
            return "This build is missing its version information. Download a new copy from GitHub."
        }
        return nil
    }

    var versionDescription: String {
        guard let version = versionString(for: "CFBundleShortVersionString") else {
            return "Development build"
        }
        guard let build = versionString(for: "CFBundleVersion") else {
            return "Version \(version)"
        }
        return "Version \(version) (\(build))"
    }

    private func versionString(for key: String) -> String? {
        guard let value = infoDictionary[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains("$(") else { return nil }
        return value
    }
}

@MainActor
final class TodayMdUpdateManager: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var isUpdaterReady = false
    @Published private(set) var unavailableReason: String?

    let versionDescription: String

    private let configuration: TodayMdUpdateConfiguration
    private let beforeInstallingUpdate: () -> Void
    private var hasAttemptedStartup = false

#if TODAYMD_GITHUB && !TODAYMD_APP_STORE && canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif

    init(
        configuration: TodayMdUpdateConfiguration = TodayMdUpdateConfiguration(),
        beforeInstallingUpdate: @escaping () -> Void = {}
    ) {
        self.configuration = configuration
        self.beforeInstallingUpdate = beforeInstallingUpdate
        versionDescription = configuration.versionDescription
        unavailableReason = configuration.unavailableReason
        super.init()
    }

    // Called by the app delegate after application launch, before any update checks.
    func start() {
        guard !hasAttemptedStartup else { return }
        hasAttemptedStartup = true
        guard configuration.unavailableReason == nil else { return }

#if TODAYMD_GITHUB && !TODAYMD_APP_STORE && canImport(Sparkle)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        do {
            try controller.updater.start()
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .assign(to: &$automaticallyChecksForUpdates)
            isUpdaterReady = true
        } catch {
            unavailableReason = "Updates could not start: \(error.localizedDescription)"
            updaterController = nil
        }
#else
        unavailableReason = "Updates are available in the app downloaded from GitHub."
#endif
    }

    func checkForUpdates() {
#if TODAYMD_GITHUB && !TODAYMD_APP_STORE && canImport(Sparkle)
        guard canCheckForUpdates else { return }
        // Sparkle's standard UI presents progress, update results, and download errors.
        updaterController?.checkForUpdates(nil)
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if TODAYMD_GITHUB && !TODAYMD_APP_STORE && canImport(Sparkle)
        guard isUpdaterReady else { return }
        // Sparkle owns this preference and persists it in the app's user defaults.
        updaterController?.updater.automaticallyChecksForUpdates = enabled
#endif
    }
}

#if TODAYMD_GITHUB && !TODAYMD_APP_STORE && canImport(Sparkle)
extension TodayMdUpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        beforeInstallingUpdate()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        beforeInstallingUpdate()
    }
}
#endif
