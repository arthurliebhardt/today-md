import AppKit
import SwiftUI

struct MarkdownEditorView: View {
    @Environment(TodayMdStore.self) private var store
    let task: TaskItem

    @State private var showPreview = false
    @State private var hoveredToolbarButtonID: String?
    @State private var markdownText = ""
    @State private var editorText = ""
    @State private var saveTask: DispatchWorkItem?
    @State private var suppressAutoContinue = false
    @State private var suppressInlineNormalization = false
    @State private var cachedTextView: NSTextView?

    private var searchQuery: SearchPresentationQuery { SearchPresentationQuery(store.searchText) }
    private var matchingNoteExcerpts: [String] { searchQuery.matchingExcerpts(in: markdownText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.subheadline.bold())
                Spacer()
                if task.note != nil || !markdownText.isEmpty {
                    Toggle(isOn: $showPreview) {
                        Image(systemName: showPreview ? "eye.fill" : "pencil")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }

            if !showPreview {
                mdToolbar
            }

            if !matchingNoteExcerpts.isEmpty {
                searchMatchesView
            }

            if showPreview {
                previewView
            } else {
                editorView
            }
        }
        .onAppear {
            suppressInlineNormalization = true
            loadNoteContent(task.note?.content ?? "")
        }
        .onChange(of: task.id, initial: true) { _, _ in
            suppressInlineNormalization = true
            loadNoteContent(task.note?.content ?? "")
            showPreview = false
            cachedTextView = nil
        }
        .onChange(of: task.note?.content) { _, newValue in
            let current = newValue ?? ""
            if current != markdownText {
                suppressInlineNormalization = true
                loadNoteContent(current)
            }
        }
        .onChange(of: editorText) { oldValue, newValue in
            handleEditorChange(oldValue: oldValue, newValue: newValue)
        }
        .onDisappear {
            hoveredToolbarButtonID = nil
        }
    }

    private var mdToolbar: some View {
        HStack(alignment: .top, spacing: 1) {
            mdBtn(title: "Heading 1", label: "H1", shortcut: "⌘1") { insertPrefix("# ") }
            mdBtn(title: "Heading 2", label: "H2", shortcut: "⌘2") { insertPrefix("## ") }
            mdBtn(title: "Heading 3", label: "H3", shortcut: "⌘3") { insertPrefix("### ") }

            mdDivider

            mdBtn(title: "Bold", icon: "bold", shortcut: "⌘B") { wrapSelection("**") }
            mdBtn(title: "Italic", icon: "italic", shortcut: "⌘I") { wrapSelection("_") }
            mdBtn(title: "Strikethrough", icon: "strikethrough", shortcut: "⌘⇧X") { wrapSelection("~~") }
            mdBtn(title: "Code Block", icon: "curlybraces", shortcut: "⌘`") {
                insertSnippetAtCursor("\n```\n\n```\n", caretOffset: 5)
            }

            mdDivider

            mdBtn(title: "Bullet List", icon: "list.bullet", shortcut: "⌘⇧L") {
                insertPrefix(MarkdownInlineDisplay.bulletDisplayPrefix)
            }
            mdBtn(title: "Numbered List", icon: "list.number", shortcut: "⌘⇧O") { insertNumberedList() }
            mdBtn(title: "Checklist Item", icon: "checkmark.square", shortcut: "⌘⇧T") {
                insertPrefix(MarkdownInlineDisplay.uncheckedChecklistDisplayPrefix)
            }
            mdBtn(title: "Divider", icon: "minus", shortcut: "⌘⇧D") { appendAtCursor("\n---\n") }
        }
    }

    private var mdDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 6)
            .padding(.top, 5)
    }

    private var searchMatchesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search matches")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(matchingNoteExcerpts.enumerated()), id: \.offset) { _, excerpt in
                Text(searchQuery.highlightedText(for: excerpt))
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
        }
    }

    private func mdBtn(
        title: String,
        label: String? = nil,
        icon: String? = nil,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let buttonID = [title, label, icon].compactMap { $0 }.joined(separator: "-")
        let isHovered = hoveredToolbarButtonID == buttonID

        return VStack(spacing: 4) {
            Button {
                performToolbarAction(action)
            } label: {
                toolbarButtonFace(label: label, icon: icon, isHovered: isHovered)
            }
            .buttonStyle(.plain)
            .help(toolbarHelpText(title: title, shortcut: shortcut))
            .accessibilityLabel(title)
            .accessibilityHint(shortcut.map { "Shortcut \($0)" } ?? "")
            .onHover { hovering in
                if hovering {
                    hoveredToolbarButtonID = buttonID
                } else if hoveredToolbarButtonID == buttonID {
                    hoveredToolbarButtonID = nil
                }
            }

            Text(shortcut ?? " ")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(shortcut == nil ? 0 : 1)
        }
        .frame(width: 36)
    }

    private func toolbarButtonFace(label: String? = nil, icon: String? = nil, isHovered: Bool) -> some View {
        Group {
            if let icon {
                Image(systemName: icon)
            } else if let label {
                Text(label).fontWeight(.bold)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
        .foregroundStyle(isHovered ? Color.accentColor : Color(nsColor: .labelColor).opacity(0.84))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isHovered
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .textBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isHovered
                    ? Color.accentColor.opacity(0.35)
                    : Color(nsColor: .separatorColor).opacity(0.28),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 6 : 2, y: 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func toolbarHelpText(title: String, shortcut: String?) -> String {
        guard let shortcut else { return title }
        return "\(title)\nShortcut: \(shortcut)"
    }

    private func performToolbarAction(_ action: @escaping () -> Void) {
        let textView = cachedTextView ?? activeTextView
        textView?.window?.makeFirstResponder(textView)
        action()
        DispatchQueue.main.async {
            textView?.window?.makeFirstResponder(textView)
        }
    }

    private func captureActiveEditorTextView() {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              tv.isEditable,
              !tv.isFieldEditor else { return }
        cachedTextView = tv
    }

    private var activeTextView: NSTextView? {
        if let tv = cachedTextView,
           tv.window != nil,
           tv.isEditable,
           !tv.isFieldEditor {
            return tv
        }
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
           tv.isEditable,
           !tv.isFieldEditor {
            cachedTextView = tv
            return tv
        }
        return nil
    }

    private func selectedRange(in text: String) -> (tv: NSTextView, range: NSRange)? {
        guard let tv = activeTextView else { return nil }
        let range = tv.selectedRange()
        let length = (text as NSString).length
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              range.location <= length,
              range.location + range.length <= length else { return nil }
        return (tv, range)
    }

    private func restoreSelection(_ range: NSRange, in tv: NSTextView?) {
        guard let tv else { return }
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(range)
        }
    }

    private func wrapSelection(_ wrapper: String) {
        suppressAutoContinue = true
        let original = activeTextView?.string ?? editorText
        guard let selection = selectedRange(in: original) else {
            editorText += wrapper + wrapper
            return
        }
        let ns = original as NSString
        let range = selection.range
        if range.length > 0 {
            let selected = ns.substring(with: range)
            let replacement = wrapper + selected + wrapper
            let newSelection = NSRange(location: range.location + wrapper.count, length: range.length)
            editorText = ns.replacingCharacters(in: range, with: replacement)
            restoreSelection(newSelection, in: selection.tv)
        } else {
            let replacement = wrapper + wrapper
            let caret = NSRange(location: range.location + wrapper.count, length: 0)
            editorText = ns.replacingCharacters(in: range, with: replacement)
            restoreSelection(caret, in: selection.tv)
        }
    }

    private func insertPrefix(_ prefix: String) {
        suppressAutoContinue = true
        let original = activeTextView?.string ?? editorText
        guard let selection = selectedRange(in: original) else {
            if editorText.isEmpty || editorText.hasSuffix("\n") {
                editorText += prefix
            } else {
                editorText += "\n" + prefix
            }
            return
        }
        let ns = original as NSString
        let range = selection.range

        if range.length > 0 {
            let selectedText = ns.substring(with: range)
            let prefixed = selectedText
                .components(separatedBy: "\n")
                .map { prefix + $0 }
                .joined(separator: "\n")
            let newSelection = NSRange(location: range.location, length: (prefixed as NSString).length)
            editorText = ns.replacingCharacters(in: range, with: prefixed)
            restoreSelection(newSelection, in: selection.tv)
        } else {
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let insertRange = NSRange(location: lineStart, length: 0)
            let caret = NSRange(location: range.location + (prefix as NSString).length, length: 0)
            editorText = ns.replacingCharacters(in: insertRange, with: prefix)
            restoreSelection(caret, in: selection.tv)
        }
    }

    private func insertNumberedList() {
        suppressAutoContinue = true
        let original = activeTextView?.string ?? editorText
        guard let selection = selectedRange(in: original) else {
            if editorText.isEmpty || editorText.hasSuffix("\n") {
                editorText += "1. "
            } else {
                editorText += "\n1. "
            }
            return
        }

        let ns = original as NSString
        let range = selection.range

        if range.length > 0 {
            let selectedText = ns.substring(with: range)
            let numbered = MarkdownListFormatting.numberLines(in: selectedText)
            let newSelection = NSRange(location: range.location, length: (numbered as NSString).length)
            editorText = ns.replacingCharacters(in: range, with: numbered)
            restoreSelection(newSelection, in: selection.tv)
        } else {
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let insertRange = NSRange(location: lineStart, length: 0)
            let prefix = MarkdownListFormatting.nextNumberedListPrefix(in: original, at: lineStart)
            let caret = NSRange(location: range.location + (prefix as NSString).length, length: 0)
            editorText = ns.replacingCharacters(in: insertRange, with: prefix)
            restoreSelection(caret, in: selection.tv)
        }
    }

    private func appendAtCursor(_ text: String) {
        insertSnippetAtCursor(text)
    }

    private func insertSnippetAtCursor(_ text: String, caretOffset: Int? = nil) {
        suppressAutoContinue = true
        let original = activeTextView?.string ?? editorText
        let insertedLength = (text as NSString).length
        let targetOffset = min(max(caretOffset ?? insertedLength, 0), insertedLength)

        guard let selection = selectedRange(in: original) else {
            editorText += text
            return
        }
        let ns = original as NSString
        let range = selection.range
        let caret = NSRange(location: range.location + targetOffset, length: 0)
        editorText = ns.replacingCharacters(in: range, with: text)
        restoreSelection(caret, in: selection.tv)
    }

    private var editorView: some View {
        ZStack(alignment: .topLeading) {
            if editorText.isEmpty {
                Text("Write notes. Checklists and bullets render as you type.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            InlineMarkdownTextEditor(text: $editorText) { textView in
                if cachedTextView !== textView {
                    cachedTextView = textView
                }
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            .background(KeyboardShortcutMonitor(handler: handleMarkdownShortcut))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(noteSurface)
    }

    private var previewView: some View {
        ScrollView {
            MarkdownPreview(markdown: previewMarkdownBinding)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(minHeight: 220, maxHeight: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(noteSurface)
        .onChange(of: markdownText) { _, _ in
            debouncedSave()
        }
    }

    private func autoContinueList(old: String, new: String) {
        guard !suppressAutoContinue else {
            suppressAutoContinue = false
            return
        }

        guard let edit = MarkdownInlineDisplay.editForAutoContinuation(oldDisplay: old, newDisplay: new) else {
            return
        }

        let textView = cachedTextView ?? activeTextView
        suppressAutoContinue = true
        editorText = edit.text
        restoreSelection(NSRange(location: edit.cursorLocation, length: 0), in: textView)
    }

    private func handleMarkdownShortcut(_ event: NSEvent) -> Bool {
        guard !showPreview, activeTextView != nil else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

        switch (flags, characters) {
        case ([.command], "1"):
            insertPrefix("# ")
            return true
        case ([.command], "2"):
            insertPrefix("## ")
            return true
        case ([.command], "3"):
            insertPrefix("### ")
            return true
        case ([.command], "b"):
            wrapSelection("**")
            return true
        case ([.command], "i"):
            wrapSelection("_")
            return true
        case ([.command, .shift], "x"):
            wrapSelection("~~")
            return true
        case ([.command], "`"):
            insertSnippetAtCursor("\n```\n\n```\n", caretOffset: 5)
            return true
        case ([.command, .shift], "o"):
            insertNumberedList()
            return true
        case ([.command, .shift], "d"):
            appendAtCursor("\n---\n")
            return true
        case ([.command, .shift], "l"):
            insertPrefix(MarkdownInlineDisplay.bulletDisplayPrefix)
            return true
        case ([.command, .shift], "t"):
            insertPrefix(MarkdownInlineDisplay.uncheckedChecklistDisplayPrefix)
            return true
        default:
            return false
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        let work = DispatchWorkItem { saveNote() }
        saveTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNote() {
        store.updateTaskNote(id: task.id, content: markdownText)
    }

    private var noteSurface: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: .textBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 18, y: 6)
    }

    private var previewMarkdownBinding: Binding<String> {
        Binding(
            get: { markdownText },
            set: { newValue in
                markdownText = newValue

                let rendered = MarkdownInlineDisplay.display(from: newValue)
                if editorText != rendered {
                    suppressInlineNormalization = true
                    editorText = rendered
                }
            }
        )
    }

    private func loadNoteContent(_ content: String) {
        let displayText = MarkdownInlineDisplay.display(from: content)
        let normalized = MarkdownInlineDisplay.normalizeEditorState(
            text: displayText,
            selection: NSRange(location: (displayText as NSString).length, length: 0)
        )
        markdownText = normalized.markdown
        editorText = normalized.text
    }

    private func handleEditorChange(oldValue: String, newValue: String) {
        captureActiveEditorTextView()

        if suppressInlineNormalization {
            suppressInlineNormalization = false
            return
        }

        let textView = cachedTextView ?? activeTextView
        let normalized = MarkdownInlineDisplay.normalizeEditorState(
            text: newValue,
            selection: textView?.selectedRange() ?? NSRange(location: (newValue as NSString).length, length: 0)
        )

        if normalized.text != newValue {
            suppressInlineNormalization = true
            markdownText = normalized.markdown
            debouncedSave()
            editorText = normalized.text
            restoreSelection(normalized.selection, in: textView)
            return
        }

        markdownText = normalized.markdown
        debouncedSave()
        autoContinueList(old: oldValue, new: newValue)
    }
}

enum MarkdownListFormatting {
    static func numberLines(in text: String) -> String {
        text
            .components(separatedBy: "\n")
            .enumerated()
            .map { index, line in "\(index + 1). \(line)" }
            .joined(separator: "\n")
    }

    static func nextNumberedListPrefix(in text: String, at lineStart: Int) -> String {
        let ns = text as NSString
        guard lineStart > 0 else { return "1. " }

        let previousLineEnd = lineStart - 1
        guard previousLineEnd >= 0 else { return "1. " }

        let previousLineRange = ns.lineRange(for: NSRange(location: previousLineEnd, length: 0))
        let previousLine = ns.substring(with: previousLineRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let previousNumber = MarkdownAutoContinuation.numberedListValue(for: previousLine) else {
            return "1. "
        }
        return "\(previousNumber + 1). "
    }
}

enum MarkdownAutoContinuation {
    struct Edit: Equatable {
        let text: String
        let cursorLocation: Int
    }

    private enum Decision: Equatable {
        case continueWith(String)
        case exitList
    }

    static func edit(old: String, new: String) -> Edit? {
        guard new.count == old.count + 1,
              let newlineIndex = findInsertedNewline(old: old, new: new) else { return nil }

        let lineStart = new[..<newlineIndex].lastIndex(of: "\n").map { new.index(after: $0) } ?? new.startIndex
        let currentLine = String(new[lineStart..<newlineIndex])
        let priorLine = previousLine(before: lineStart, in: new)
        guard let decision = continuationDecision(for: currentLine, priorLine: priorLine) else { return nil }

        switch decision {
        case .continueWith(let prefix):
            let beforePart = String(new[...newlineIndex])
            let afterNewline = new.index(after: newlineIndex)
            let afterPart = String(new[afterNewline...])

            return Edit(
                text: beforePart + prefix + afterPart,
                cursorLocation: (beforePart as NSString).length + (prefix as NSString).length
            )
        case .exitList:
            let beforePart = String(new[..<lineStart])
            let afterPart = String(new[newlineIndex...])

            return Edit(
                text: beforePart + afterPart,
                cursorLocation: (beforePart as NSString).length + 1
            )
        }
    }

    private static func continuationDecision(for line: String, priorLine: String?) -> Decision? {
        let leadingWhitespace = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPriorLine = priorLine?.trimmingCharacters(in: .whitespacesAndNewlines)

        if isEmptyChecklistMarker(trimmed) {
            if trimmedPriorLine.map(isChecklistAnyLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "- [ ] ")
        }
        if isChecklistLine(trimmed) {
            return .continueWith(leadingWhitespace + "- [ ] ")
        }
        if trimmed == "-" {
            if trimmedPriorLine.map(isDashBulletLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "- ")
        }
        if trimmed.hasPrefix("- ") {
            return .continueWith(leadingWhitespace + "- ")
        }
        if trimmed == "*" {
            if trimmedPriorLine.map(isStarBulletLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "* ")
        }
        if trimmed.hasPrefix("* ") {
            return .continueWith(leadingWhitespace + "* ")
        }
        if trimmed == "+" {
            if trimmedPriorLine.map(isPlusBulletLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "+ ")
        }
        if trimmed.hasPrefix("+ ") {
            return .continueWith(leadingWhitespace + "+ ")
        }
        if isEmptyNumberedListMarker(trimmed), let number = numberedListValue(for: trimmed) {
            if trimmedPriorLine.map(isNumberedListLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "\(number + 1). ")
        }
        if isNumberedListLine(trimmed), let number = numberedListValue(for: trimmed) {
            return .continueWith(leadingWhitespace + "\(number + 1). ")
        }
        if trimmed == ">" {
            if trimmedPriorLine.map(isQuoteLine) == true {
                return .exitList
            }
            return .continueWith(leadingWhitespace + "> ")
        }
        if trimmed.hasPrefix("> ") {
            return .continueWith(leadingWhitespace + "> ")
        }

        return nil
    }

    private static func isEmptyChecklistMarker(_ line: String) -> Bool {
        line == "- [ ]" || line == "- [x]" || line == "- [X]"
    }

    private static func isChecklistAnyLine(_ line: String) -> Bool {
        isEmptyChecklistMarker(line) || isChecklistLine(line)
    }

    private static func isChecklistLine(_ line: String) -> Bool {
        line.hasPrefix("- [ ] ")
            || line.hasPrefix("- [x] ")
            || line.hasPrefix("- [X] ")
    }

    private static func isDashBulletLine(_ line: String) -> Bool {
        line == "-" || line.hasPrefix("- ")
    }

    private static func isStarBulletLine(_ line: String) -> Bool {
        line == "*" || line.hasPrefix("* ")
    }

    private static func isPlusBulletLine(_ line: String) -> Bool {
        line == "+" || line.hasPrefix("+ ")
    }

    private static func isQuoteLine(_ line: String) -> Bool {
        line == ">" || line.hasPrefix("> ")
    }

    private static func isEmptyNumberedListMarker(_ line: String) -> Bool {
        guard let number = numberedListValue(for: line) else { return false }
        return line == "\(number)."
    }

    private static func isNumberedListLine(_ line: String) -> Bool {
        guard let number = numberedListValue(for: line) else { return false }
        return line == "\(number)." || line.hasPrefix("\(number). ")
    }

    static func numberedListValue(for line: String) -> Int? {
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
}
