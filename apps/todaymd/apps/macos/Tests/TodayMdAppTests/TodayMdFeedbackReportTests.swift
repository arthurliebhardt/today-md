import Foundation
import XCTest
@testable import TodayMdApp

final class TodayMdFeedbackReportTests: XCTestCase {
    func testMailtoPreservesSpecialCharactersAndUsesFixedRecipient() throws {
        let report = makeReport(
            summary: "  C++ & café? #1  ",
            message: "  Steps: A+B & C? #issue\nNext line: 日本語\r\nLast line\rDone  "
        )
        let url = try XCTUnwrap(report.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "feedback@todaymd.app")
        XCTAssertEqual(queryItems.count, 2)
        XCTAssertEqual(queryItems.first { $0.name == "subject" }?.value, "today-md Feedback: C++ & café? #1")
        XCTAssertEqual(
            queryItems.first { $0.name == "body" }?.value,
            "Steps: A+B & C? #issue\r\nNext line: 日本語\r\nLast line\r\nDone\r\n\r\n---\r\ntoday-md: 1.2.3 (45)\r\nmacOS: Version 15.0"
        )
        XCTAssertTrue(url.absoluteString.contains("C%2B%2B"))
        XCTAssertFalse(url.absoluteString.contains("+"))
        XCTAssertNil(components.fragment)
    }

    func testValidationRequiresSummaryAndMessage() {
        XCTAssertFalse(makeReport(summary: " \n\t ").isValid)
        XCTAssertFalse(makeReport(message: " \r\n\t ").isValid)
        XCTAssertNil(makeReport(summary: "").mailtoURL)
        XCTAssertNil(makeReport(message: "").mailtoURL)
        XCTAssertTrue(makeReport(summary: " Summary ", message: " Details ").isValid)
    }

    func testSummaryLineBreaksCannotInsertHeaders() throws {
        let report = makeReport(summary: "  Summary\r\nCc: unexpected@example.com\nSubject: another\rheader  ")
        let url = try XCTUnwrap(report.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let subject = "today-md Feedback: Summary Cc: unexpected@example.com Subject: another header"

        XCTAssertEqual(report.subject, subject)
        XCTAssertEqual(components.queryItems?.first { $0.name == "subject" }?.value, subject)
        XCTAssertTrue(report.copyableReport.hasPrefix("To: feedback@todaymd.app\nSubject: \(subject)\n\n"))
        XCTAssertFalse(report.copyableReport.contains("\nCc:"))
        let encodedSubject = url.absoluteString.components(separatedBy: "&body=")[0]
        XCTAssertFalse(encodedSubject.contains("%0A"))
        XCTAssertFalse(encodedSubject.contains("%0D"))
    }

    func testKindChangesTitleAndSubject() {
        let feedback = makeReport()
        let bugReport = makeReport(kind: .bugReport)

        XCTAssertEqual(TodayMdFeedbackReport.Kind.allCases.map(\.title), ["Feedback", "Bug Report"])
        XCTAssertEqual(feedback.subject, "today-md Feedback: Summary")
        XCTAssertEqual(bugReport.subject, "today-md Bug Report: Summary")
        XCTAssertNotEqual(feedback.kind.id, bugReport.kind.id)
    }

    func testCopyableReportIncludesRecipientSubjectMessageAndVersions() {
        let report = makeReport(kind: .bugReport, summary: "  Missing task  ", message: "  My task disappeared.\nPlease help.  ")

        XCTAssertEqual(
            report.copyableReport,
            "To: feedback@todaymd.app\nSubject: today-md Bug Report: Missing task\n\nMy task disappeared.\nPlease help.\n\n---\ntoday-md: 1.2.3 (45)\nmacOS: Version 15.0"
        )
    }

    func testDefaultsProvideAppAndOperatingSystemVersions() {
        let report = TodayMdFeedbackReport(kind: .feedback, summary: "Summary", message: "Details")

        XCTAssertFalse(report.appVersion.isEmpty)
        XCTAssertEqual(report.operatingSystem, ProcessInfo.processInfo.operatingSystemVersionString)
    }

    private func makeReport(
        kind: TodayMdFeedbackReport.Kind = .feedback,
        summary: String = "Summary",
        message: String = "Details"
    ) -> TodayMdFeedbackReport {
        TodayMdFeedbackReport(
            kind: kind,
            summary: summary,
            message: message,
            appVersion: "1.2.3 (45)",
            operatingSystem: "Version 15.0"
        )
    }
}
