import Foundation

enum MarkdownInlineDisplay {
    enum LeadingToken: Equatable {
        case uncheckedChecklist
        case checkedChecklist
        case bullet
    }

    static let uncheckedChecklistToken = "☐"
    static let checkedChecklistToken = "☑"
    static let bulletToken = "•"

    static var uncheckedChecklistDisplayPrefix: String { uncheckedChecklistToken + " " }
    static var bulletDisplayPrefix: String { bulletToken + " " }

    struct NormalizedEditorState: Equatable {
        let text: String
        let selection: NSRange
        let markdown: String
    }

    static func display(from markdown: String) -> String {
        transformLines(in: markdown, using: displayLine(from:))
    }

    static func markdown(from editorText: String) -> String {
        transformLines(in: editorText, using: markdownLine(from:))
    }

    static func canonicalMarkdown(from text: String) -> String {
        transformLines(in: markdown(from: display(from: text)), using: canonicalMarkdownLine(from:))
    }

    static func isDividerMarkdownLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    static func normalizeEditorState(text: String, selection: NSRange) -> NormalizedEditorState {
        let safeSelection = clamped(range: selection, in: text)
        let markdown = markdown(from: text)
        let normalizedText = display(from: markdown)

        let markdownSelectionStart = markdownOffset(forEditorOffset: safeSelection.location, inEditorText: text)
        let markdownSelectionEnd = markdownOffset(
            forEditorOffset: safeSelection.location + safeSelection.length,
            inEditorText: text
        )

        let normalizedSelectionStart = displayOffset(
            forMarkdownOffset: markdownSelectionStart,
            inMarkdownText: markdown
        )
        let normalizedSelectionEnd = displayOffset(
            forMarkdownOffset: markdownSelectionEnd,
            inMarkdownText: markdown
        )

        return NormalizedEditorState(
            text: normalizedText,
            selection: NSRange(
                location: normalizedSelectionStart,
                length: max(normalizedSelectionEnd - normalizedSelectionStart, 0)
            ),
            markdown: markdown
        )
    }

    static func editForAutoContinuation(oldDisplay: String, newDisplay: String) -> MarkdownAutoContinuation.Edit? {
        let oldMarkdown = markdown(from: oldDisplay)
        let newMarkdown = markdown(from: newDisplay)

        guard let edit = MarkdownAutoContinuation.edit(old: oldMarkdown, new: newMarkdown) else {
            return nil
        }

        let displayText = display(from: edit.text)
        let displayCursorLocation = displayOffset(
            forMarkdownOffset: edit.cursorLocation,
            inMarkdownText: edit.text
        )

        return MarkdownAutoContinuation.Edit(
            text: displayText,
            cursorLocation: displayCursorLocation
        )
    }

    static func markdownOffset(forEditorOffset offset: Int, inEditorText text: String) -> Int {
        let clampedOffset = clamp(offset, in: text)
        let prefix = (text as NSString).substring(to: clampedOffset)
        return (markdown(from: prefix) as NSString).length
    }

    static func displayOffset(forMarkdownOffset offset: Int, inMarkdownText text: String) -> Int {
        let clampedOffset = clamp(offset, in: text)
        let prefix = (text as NSString).substring(to: clampedOffset)
        return (display(from: prefix) as NSString).length
    }

    static func leadingToken(in line: String) -> (token: LeadingToken, range: NSRange)? {
        let (indentation, content) = splitIndentation(from: line)
        let indentationLength = (indentation as NSString).length

        if let markerLength = displayMarkerLength(for: uncheckedChecklistToken, in: content) {
            return (
                .uncheckedChecklist,
                NSRange(location: indentationLength, length: markerLength)
            )
        }
        if let markerLength = displayMarkerLength(for: checkedChecklistToken, in: content) {
            return (
                .checkedChecklist,
                NSRange(location: indentationLength, length: markerLength)
            )
        }
        if let markerLength = displayMarkerLength(for: bulletToken, in: content) {
            return (
                .bullet,
                NSRange(location: indentationLength, length: markerLength)
            )
        }

        return nil
    }

    static func checkboxMarkerRange(in editorText: String, atEditorOffset offset: Int) -> NSRange? {
        guard let lineContext = lineContext(in: editorText, atEditorOffset: offset),
              let token = leadingToken(in: lineContext.line) else { return nil }

        switch token.token {
        case .uncheckedChecklist, .checkedChecklist:
            return NSRange(
                location: lineContext.lineRange.location + token.range.location,
                length: token.range.length
            )
        case .bullet:
            return nil
        }
    }

    static func toggledCheckbox(in editorText: String, atEditorOffset offset: Int) -> String? {
        guard let lineContext = lineContext(in: editorText, atEditorOffset: offset),
              let token = leadingToken(in: lineContext.line) else { return nil }

        let absoluteTokenRange = NSRange(
            location: lineContext.lineRange.location + token.range.location,
            length: 1
        )

        switch token.token {
        case .uncheckedChecklist:
            return (editorText as NSString).replacingCharacters(in: absoluteTokenRange, with: checkedChecklistToken)
        case .checkedChecklist:
            return (editorText as NSString).replacingCharacters(in: absoluteTokenRange, with: uncheckedChecklistToken)
        case .bullet:
            return nil
        }
    }

    private static func displayLine(from line: String) -> String {
        let (indentation, content) = splitIndentation(from: line)

        if let remainder = normalizedRemainder(afterMarkdownMarker: "- [ ]", in: content) {
            return indentation + uncheckedChecklistToken + remainder
        }
        if let remainder = normalizedRemainder(afterMarkdownMarker: "- [x]", in: content)
            ?? normalizedRemainder(afterMarkdownMarker: "- [X]", in: content) {
            return indentation + checkedChecklistToken + remainder
        }
        if let remainder = remainder(afterStrictBulletMarker: "-", in: content)
            ?? remainder(afterStrictBulletMarker: "*", in: content)
            ?? remainder(afterStrictBulletMarker: "+", in: content) {
            return indentation + bulletToken + remainder
        }
        if let remainder = normalizedRemainder(afterDisplayMarker: uncheckedChecklistToken, in: content) {
            return indentation + uncheckedChecklistToken + remainder
        }
        if let remainder = normalizedRemainder(afterDisplayMarker: checkedChecklistToken, in: content) {
            return indentation + checkedChecklistToken + remainder
        }
        if let remainder = normalizedRemainder(afterDisplayMarker: bulletToken, in: content) {
            return indentation + bulletToken + remainder
        }

        return line
    }

    private static func markdownLine(from line: String) -> String {
        let (indentation, content) = splitIndentation(from: line)

        if let remainder = normalizedRemainder(afterDisplayMarker: uncheckedChecklistToken, in: content) {
            return indentation + "- [ ]" + remainder
        }
        if let remainder = normalizedRemainder(afterDisplayMarker: checkedChecklistToken, in: content) {
            return indentation + "- [x]" + remainder
        }
        if let remainder = normalizedRemainder(afterDisplayMarker: bulletToken, in: content) {
            return indentation + "-" + remainder
        }

        return line
    }

    private static func canonicalMarkdownLine(from line: String) -> String {
        let (indentation, content) = splitIndentation(from: line)

        if let remainder = normalizedRemainder(afterMarkdownMarker: "- [ ]", in: content) {
            return indentation + "- [ ]" + normalizeMarkdownSpacing(in: remainder)
        }
        if let remainder = normalizedRemainder(afterMarkdownMarker: "- [x]", in: content) {
            return indentation + "- [x]" + normalizeMarkdownSpacing(in: remainder)
        }
        if let remainder = normalizedRemainder(afterMarkdownMarker: "- [X]", in: content) {
            return indentation + "- [x]" + normalizeMarkdownSpacing(in: remainder)
        }
        if let bullet = canonicalBulletLine(indentation: indentation, content: content) {
            return bullet
        }
        if let ordered = canonicalOrderedListLine(indentation: indentation, content: content) {
            return ordered
        }

        return line
    }

    private static func transformLines(
        in text: String,
        using transform: (String) -> String
    ) -> String {
        text
            .components(separatedBy: "\n")
            .map(transform)
            .joined(separator: "\n")
    }

    private static func splitIndentation(from line: String) -> (String, String) {
        let indentEnd = line.firstIndex { character in
            character != " " && character != "\t"
        } ?? line.endIndex

        return (
            String(line[..<indentEnd]),
            String(line[indentEnd...])
        )
    }

    private static func remainder(afterMarkdownMarker marker: String, in content: String) -> String? {
        guard content == marker || content.hasPrefix(marker + " ") else { return nil }
        return String(content.dropFirst(marker.count))
    }

    private static func remainder(afterBulletMarker marker: String, in content: String) -> String? {
        guard content == marker || content.hasPrefix(marker + " ") else { return nil }
        return String(content.dropFirst(marker.count))
    }

    private static func remainder(afterStrictBulletMarker marker: String, in content: String) -> String? {
        guard content.hasPrefix(marker + " ") else { return nil }
        return String(content.dropFirst(marker.count))
    }

    private static func remainder(afterDisplayMarker marker: String, in content: String) -> String? {
        guard content == marker || content.hasPrefix(marker + " ") else { return nil }
        return String(content.dropFirst(marker.count))
    }

    private static func normalizedRemainder(afterMarkdownMarker marker: String, in content: String) -> String? {
        guard content.hasPrefix(marker) else { return nil }
        let remainder = String(content.dropFirst(marker.count))
        if remainder.isEmpty || remainder.hasPrefix(" ") {
            return remainder
        }
        return " " + remainder
    }

    private static func normalizedRemainder(afterDisplayMarker marker: String, in content: String) -> String? {
        guard content.hasPrefix(marker) else { return nil }
        let remainder = String(content.dropFirst(marker.count))
        if remainder.isEmpty || remainder.hasPrefix(" ") {
            return remainder
        }
        return " " + remainder
    }

    private static func canonicalBulletLine(indentation: String, content: String) -> String? {
        guard let first = content.first, first == "-" || first == "*" || first == "+" else { return nil }
        let remainder = String(content.dropFirst())
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }
        return indentation + "-" + normalizeMarkdownSpacing(in: remainder)
    }

    private static func canonicalOrderedListLine(indentation: String, content: String) -> String? {
        guard let dotIndex = content.firstIndex(of: "."),
              content[..<dotIndex].allSatisfy(\.isNumber) else { return nil }

        let number = String(content[..<dotIndex])
        let remainderStart = content.index(after: dotIndex)
        let remainder = String(content[remainderStart...])
        guard remainder.isEmpty || remainder.first?.isWhitespace == true || remainder.first?.isNumber == false else {
            return nil
        }
        return indentation + number + "." + normalizeMarkdownSpacing(in: remainder)
    }

    private static func normalizeMarkdownSpacing(in remainder: String) -> String {
        guard !remainder.isEmpty else { return "" }

        let trimmedLeading = remainder.drop(while: { $0 == " " || $0 == "\t" })
        guard !trimmedLeading.isEmpty else { return " " }
        return " " + trimmedLeading
    }

    private static func displayMarkerLength(for marker: String, in content: String) -> Int? {
        if content == marker || content.hasPrefix(marker + " ") {
            return min(2, (content as NSString).length)
        }
        if normalizedRemainder(afterDisplayMarker: marker, in: content) != nil {
            return 1
        }
        return nil
    }

    private static func clamp(_ offset: Int, in text: String) -> Int {
        min(max(offset, 0), (text as NSString).length)
    }

    private static func lineContext(in text: String, atEditorOffset offset: Int) -> (line: String, lineRange: NSRange)? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let safeOffset = min(max(offset, 0), max(ns.length - 1, 0))
        let lineRange = ns.lineRange(for: NSRange(location: safeOffset, length: 0))
        return (ns.substring(with: lineRange), lineRange)
    }

    private static func clamped(range: NSRange, in text: String) -> NSRange {
        let location = clamp(range.location, in: text)
        let end = clamp(range.location + range.length, in: text)
        return NSRange(location: location, length: max(end - location, 0))
    }
}
