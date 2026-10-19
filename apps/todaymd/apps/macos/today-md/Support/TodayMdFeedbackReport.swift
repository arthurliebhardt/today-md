import Foundation

struct TodayMdFeedbackReport {
    enum Kind: String, CaseIterable, Identifiable {
        case feedback
        case bugReport

        var id: String { rawValue }

        var title: String {
            switch self {
            case .feedback:
                return "Feedback"
            case .bugReport:
                return "Bug Report"
            }
        }
    }

    static let recipient = "feedback@todaymd.app"

    let kind: Kind
    let summary: String
    let message: String
    let appVersion: String
    let operatingSystem: String

    init(
        kind: Kind,
        summary: String,
        message: String,
        appVersion: String = TodayMdFeedbackReport.currentAppVersion,
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.kind = kind
        self.summary = summary
        self.message = message
        self.appVersion = appVersion
        self.operatingSystem = operatingSystem
    }

    var isValid: Bool {
        !trimmedSummary.isEmpty && !trimmedMessage.isEmpty
    }

    var subject: String {
        "today-md \(kind.title): \(trimmedSummary)"
    }

    var body: String {
        "\(trimmedMessage)\n\n---\ntoday-md: \(appVersion)\nmacOS: \(operatingSystem)"
    }

    var mailtoURL: URL? {
        guard isValid else { return nil }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let mailBody = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")

        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              let encodedBody = mailBody.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return nil
        }

        return URL(string: "mailto:\(Self.recipient)?subject=\(encodedSubject)&body=\(encodedBody)")
    }

    var copyableReport: String {
        "To: \(Self.recipient)\nSubject: \(subject)\n\n\(body)"
    }

    static var currentAppVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "Development build"

        guard let build, !build.isEmpty else { return displayVersion }
        return "\(displayVersion) (\(build))"
    }

    private var trimmedSummary: String {
        summary
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
