import AppKit
import SwiftUI

struct TodayMdFeedbackView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var kind: TodayMdFeedbackReport.Kind = .feedback
    @State private var summary = ""
    @State private var message = ""
    @State private var statusMessage: String?
    @State private var emailOpenFailed = false
    @FocusState private var summaryIsFocused: Bool

    private var report: TodayMdFeedbackReport {
        TodayMdFeedbackReport(kind: kind, summary: summary, message: message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Help improve today-md")
                    .font(.title2.weight(.semibold))
                Text("Share an idea, tell us what you think, or report something that isn't working.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Type", selection: $kind) {
                ForEach(TodayMdFeedbackReport.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.headline)
                TextField("A brief description", text: $summary)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Summary")
                    .focused($summaryIsFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(kind == .bugReport ? "What happened?" : "Your feedback")
                    .font(.headline)
                Text(kind == .bugReport
                     ? "Include the steps to reproduce the bug, what you expected, and what happened instead."
                     : "What could we make better for you?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $message)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 160)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary)
                    }
                    .accessibilityLabel(kind == .bugReport ? "Bug details" : "Feedback details")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("To: \(TodayMdFeedbackReport.recipient)")
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
                Text("Opens a draft in your email app for you to review and send. Includes your app and macOS versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(emailOpenFailed ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedbackStatus")
            }

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy Report", action: copyReport)
                    .disabled(!report.isValid)
                Button("Open Email App", action: composeEmail)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!report.isValid)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { summaryIsFocused = true }
        .onChange(of: kind) { _, _ in clearStatus() }
        .onChange(of: summary) { _, _ in clearStatus() }
        .onChange(of: message) { _, _ in clearStatus() }
    }

    private func composeEmail() {
        guard report.isValid, let url = report.mailtoURL else { return }
        openURL(url) { accepted in
            emailOpenFailed = !accepted
            statusMessage = accepted
                ? "Finish sending in your email app. Your report is still available here."
                : "Couldn't open an email app. Use Copy Report and paste it into an email to \(TodayMdFeedbackReport.recipient)."
        }
    }

    private func copyReport() {
        guard report.isValid else { return }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(report.copyableReport, forType: .string)
        emailOpenFailed = !copied
        statusMessage = copied
            ? "Report copied. Paste it into an email to \(TodayMdFeedbackReport.recipient)."
            : "Couldn't copy your report. You can select and copy your message manually."
    }

    private func clearStatus() {
        statusMessage = nil
        emailOpenFailed = false
    }
}
