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
        transformLines(in: normalizedLineEndings(in: markdown), using: displayLine(from:))
    }

    static func markdown(from editorText: String) -> String {
        transformLines(in: normalizedLineEndings(in: editorText), using: markdownLine(from:))
    }

    static func canonicalMarkdown(from text: String) -> String {
        transformLines(in: markdown(from: display(from: text)), using: canonicalMarkdownLine(from:))
    }

    static func isDividerMarkdownLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    static func normalizeEditorState(text: String, selection: NSRange) -> NormalizedEditorState {
        let normalizedSource = normalizedLineEndings(in: text)
        let safeSelection = clamped(range: selection, in: normalizedSource)
        let markdown = markdown(from: normalizedSource)
        let normalizedText = display(from: markdown)

        let markdownSelectionStart = markdownOffset(forEditorOffset: safeSelection.location, inEditorText: normalizedSource)
        let markdownSelectionEnd = markdownOffset(
            forEditorOffset: safeSelection.location + safeSelection.length,
            inEditorText: normalizedSource
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
        let oldDisplay = normalizedLineEndings(in: oldDisplay)
        let newDisplay = normalizedLineEndings(in: newDisplay)

        guard newDisplay.count == oldDisplay.count + 1,
              let newlineIndex = findInsertedNewline(old: oldDisplay, new: newDisplay) else {
            return nil
        }

        let lineStart = newDisplay[..<newlineIndex].lastIndex(of: "\n").map { newDisplay.index(after: $0) } ?? newDisplay.startIndex
        let currentLine = String(newDisplay[lineStart..<newlineIndex])
        let priorLine = previousLine(before: lineStart, in: newDisplay)
        guard let decision = displayContinuationDecision(for: currentLine, priorLine: priorLine) else {
            return nil
        }

        switch decision {
        case .continueWith(let prefix):
            let beforePart = String(newDisplay[...newlineIndex])
            let afterNewline = newDisplay.index(after: newlineIndex)
            let afterPart = String(newDisplay[afterNewline...])

            return MarkdownAutoContinuation.Edit(
                text: beforePart + prefix + afterPart,
                cursorLocation: (beforePart as NSString).length + (prefix as NSString).length
            )
        case .exitList:
            let beforePart = String(newDisplay[..<lineStart])
            let afterPart = String(newDisplay[newlineIndex...])

            return MarkdownAutoContinuation.Edit(
                text: beforePart + afterPart,
                cursorLocation: (beforePart as NSString).length + 1
            )
        }
    }

    static func editForInsertedNewline(in display: String, atEditorOffset offset: Int) -> MarkdownAutoContinuation.Edit? {
        let safeOffset = clamp(offset, in: display)
        let cursorIndex = String.Index(utf16Offset: safeOffset, in: display)
        let lineStart = display[..<cursorIndex].lastIndex(of: "\n").map { display.index(after: $0) } ?? display.startIndex
        let lineEnd = display[cursorIndex...].firstIndex(of: "\n") ?? display.endIndex
        let currentLine = String(display[lineStart..<lineEnd])
        let priorLine = previousLine(before: lineStart, in: display)

        guard let decision = displayContinuationDecision(for: currentLine, priorLine: priorLine) else {
            return nil
        }

        switch decision {
        case .continueWith(let prefix):
            let beforeCursor = String(display[..<cursorIndex])
            let afterCursor = String(display[cursorIndex...])
            let inserted = "\n" + prefix

            return MarkdownAutoContinuation.Edit(
                text: beforeCursor + inserted + afterCursor,
                cursorLocation: (beforeCursor as NSString).length + (inserted as NSString).length
            )
        case .exitList:
            let beforeLine = String(display[..<lineStart])
            let afterLine = String(display[lineEnd...])

            return MarkdownAutoContinuation.Edit(
                text: beforeLine + afterLine,
                cursorLocation: (beforeLine as NSString).length
            )
        }
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

    private static func normalizedLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private enum DisplayContinuationDecision: Equatable {
        case continueWith(String)
        case exitList
    }

    private static func displayContinuationDecision(for line: String, priorLine: String?) -> DisplayContinuationDecision? {
        let leadingWhitespace = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPriorLine = priorLine?.trimmingCharacters(in: .whitespacesAndNewlines)

        if isEmptyDisplayChecklistMarker(trimmed) {
            if trimmedPriorLine.map(isDisplayChecklistAnyLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + uncheckedChecklistDisplayPrefix)
        }
        if isDisplayChecklistLine(trimmed) {
            return .continueWith(leadingWhitespace + uncheckedChecklistDisplayPrefix)
        }
        if trimmed == bulletToken {
            if trimmedPriorLine.map(isDisplayBulletLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + bulletDisplayPrefix)
        }
        if trimmed.hasPrefix(bulletDisplayPrefix) {
            return .continueWith(leadingWhitespace + bulletDisplayPrefix)
        }
        if isEmptyDisplayNumberedListMarker(trimmed), let number = numberedListValue(for: trimmed) {
            if trimmedPriorLine.map(isDisplayNumberedListLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "\(number + 1). ")
        }
        if isDisplayNumberedListLine(trimmed), let number = numberedListValue(for: trimmed) {
            return .continueWith(leadingWhitespace + "\(number + 1). ")
        }

        return nil
    }

    private static func isEmptyDisplayChecklistMarker(_ line: String) -> Bool {
        line == uncheckedChecklistToken || line == checkedChecklistToken
    }

    private static func isDisplayChecklistAnyLine(_ line: String) -> Bool {
        isEmptyDisplayChecklistMarker(line) || isDisplayChecklistLine(line)
    }

    private static func isDisplayChecklistLine(_ line: String) -> Bool {
        line.hasPrefix(uncheckedChecklistDisplayPrefix)
            || line.hasPrefix(checkedChecklistToken + " ")
    }

    private static func isDisplayBulletLine(_ line: String) -> Bool {
        line == bulletToken || line.hasPrefix(bulletDisplayPrefix)
    }

    private static func isEmptyDisplayNumberedListMarker(_ line: String) -> Bool {
        guard let number = numberedListValue(for: line) else { return false }
        return line == "\(number)."
    }

    private static func isDisplayNumberedListLine(_ line: String) -> Bool {
        guard let number = numberedListValue(for: line) else { return false }
        return line == "\(number)." || line.hasPrefix("\(number). ")
    }

    private static func numberedListValue(for line: String) -> Int? {
        guard let token = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first,
              token.last == "." else { return nil }
        return Int(token.dropLast())
    }

    private static func previousLine(before lineStart: String.Index, in text: String) -> String? {
        guard lineStart > text.startIndex else { return nil }

        let endOfPreviousLine = text.index(before: lineStart)
        let prefix = text[..<endOfPreviousLine]
        let previousLineStart = prefix.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        return String(text[previousLineStart..<endOfPreviousLine])
    }

    private static func findInsertedNewline(old: String, new: String) -> String.Index? {
        let oldChars = Array(old)
        let newChars = Array(new)
        guard newChars.count == oldChars.count + 1 else { return nil }

        for i in 0..<newChars.count {
            if i >= oldChars.count || newChars[i] != oldChars[i] {
                guard newChars[i] == "\n" else { return nil }
                return new.index(new.startIndex, offsetBy: i)
            }
        }

        return nil
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
