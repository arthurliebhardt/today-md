import AppKit
import SwiftUI

struct MarkdownEditorView: View {
    @Environment(TodayMdStore.self) private var store
    let task: TaskItem

    @State private var showPreview = false
    @State private var hoveredToolbarButtonID: String?
    @State private var markdownText = ""
    @State private var saveTask: DispatchWorkItem?
    @State private var suppressAutoContinue = false
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
            markdownText = task.note?.content ?? ""
        }
        .onChange(of: task.id, initial: true) { _, _ in
            markdownText = task.note?.content ?? ""
            showPreview = false
            cachedTextView = nil
        }
        .onChange(of: task.note?.content) { _, newValue in
            let current = newValue ?? ""
            if current != markdownText {
                suppressAutoContinue = true
                markdownText = current
            }
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
            mdBtn(title: "Strikethrough", icon: "strikethrough") { wrapSelection("~~") }
            mdBtn(title: "Inline Code", icon: "chevron.left.forwardslash.chevron.right", shortcut: "⌘`") { wrapSelection("`") }

            mdDivider

            mdBtn(title: "Bullet List", icon: "list.bullet", shortcut: "⌘⇧L") { insertPrefix("- ") }
            mdBtn(title: "Numbered List", icon: "list.number") { insertPrefix("1. ") }
            mdBtn(title: "Checklist Item", icon: "checkmark.square", shortcut: "⌘⇧T") { insertPrefix("- [ ] ") }

            mdDivider

            mdBtn(title: "Quote", icon: "text.quote") { insertPrefix("> ") }
            mdBtn(title: "Divider", icon: "minus") { appendAtCursor("\n---\n") }
            mdBtn(title: "Code Block", icon: "curlybraces") { appendAtCursor("\n```\n\n```\n") }

            Spacer()
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
                if let tv = activeTextView {
                    tv.window?.makeFirstResponder(tv)
                }
                action()
                DispatchQueue.main.async {
                    if let tv = cachedTextView {
                        tv.window?.makeFirstResponder(tv)
                    }
                }
            } label: {
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

    private func toolbarHelpText(title: String, shortcut: String?) -> String {
        guard let shortcut else { return title }
        return "\(title)\nShortcut: \(shortcut)"
    }

    private func captureActiveEditorTextView() {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              tv.isEditable,
              let textStorage = tv.textStorage,
              textStorage.string == markdownText else { return }
        cachedTextView = tv
    }

    private var activeTextView: NSTextView? {
        if let tv = cachedTextView,
           tv.window != nil,
           tv.isEditable,
           let textStorage = tv.textStorage,
           textStorage.string == markdownText {
            return tv
        }
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
           tv.isEditable,
           let textStorage = tv.textStorage,
           textStorage.string == markdownText {
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
        let original = markdownText
        guard let selection = selectedRange(in: original) else {
            markdownText += wrapper + wrapper
            return
        }
        let ns = original as NSString
        let range = selection.range
        if range.length > 0 {
            let selected = ns.substring(with: range)
            let replacement = wrapper + selected + wrapper
            let newSelection = NSRange(location: range.location + wrapper.count, length: range.length)
            markdownText = ns.replacingCharacters(in: range, with: replacement)
            restoreSelection(newSelection, in: selection.tv)
        } else {
            let replacement = wrapper + wrapper
            let caret = NSRange(location: range.location + wrapper.count, length: 0)
            markdownText = ns.replacingCharacters(in: range, with: replacement)
            restoreSelection(caret, in: selection.tv)
        }
    }

    private func insertPrefix(_ prefix: String) {
        suppressAutoContinue = true
        let original = markdownText
        guard let selection = selectedRange(in: original) else {
            if markdownText.isEmpty || markdownText.hasSuffix("\n") {
                markdownText += prefix
            } else {
                markdownText += "\n" + prefix
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
            markdownText = ns.replacingCharacters(in: range, with: prefixed)
            restoreSelection(newSelection, in: selection.tv)
        } else {
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let insertRange = NSRange(location: lineStart, length: 0)
            let caret = NSRange(location: range.location + (prefix as NSString).length, length: 0)
            markdownText = ns.replacingCharacters(in: insertRange, with: prefix)
            restoreSelection(caret, in: selection.tv)
        }
    }

    private func appendAtCursor(_ text: String) {
        suppressAutoContinue = true
        let original = markdownText
        guard let selection = selectedRange(in: original) else {
            markdownText += text
            return
        }
        let ns = original as NSString
        let range = selection.range
        let caret = NSRange(location: range.location + (text as NSString).length, length: 0)
        markdownText = ns.replacingCharacters(in: range, with: text)
        restoreSelection(caret, in: selection.tv)
    }

    private var editorView: some View {
        TextEditor(text: $markdownText)
            .font(.body.monospaced())
            .frame(minHeight: 150)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .onChange(of: markdownText) { oldValue, newValue in
                captureActiveEditorTextView()
                debouncedSave()
                autoContinueList(old: oldValue, new: newValue)
            }
            .background(KeyboardShortcutMonitor(handler: handleMarkdownShortcut))
    }

    private var previewView: some View {
        ScrollView {
            MarkdownPreview(markdown: $markdownText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .onChange(of: markdownText) { _, _ in
            debouncedSave()
        }
    }

    private func autoContinueList(old: String, new: String) {
        guard !suppressAutoContinue else {
            suppressAutoContinue = false
            return
        }

        guard new.count == old.count + 1,
              new.last == "\n" || new.hasSuffix("\n") else { return }

        guard let newlineIndex = findInsertedNewline(old: old, new: new) else { return }

        let beforeNewline = new[new.startIndex..<newlineIndex]
        let prevLine = String(beforeNewline.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")

        let trimmed = prevLine.trimmingCharacters(in: .init(charactersIn: " \t"))
        let leadingWhitespace = String(prevLine.prefix(while: { $0 == " " || $0 == "\t" }))

        var prefix: String?
        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            if trimmed == "- [ ] " || trimmed == "- [x] " {
                suppressAutoContinue = true
                let lineStart = beforeNewline.lastIndex(of: "\n").map { new.index(after: $0) } ?? new.startIndex
                markdownText = String(new[new.startIndex..<lineStart]) + String(new[new.index(after: newlineIndex)...])
                return
            }
            prefix = leadingWhitespace + "- [ ] "
        } else if trimmed.hasPrefix("- ") {
            if trimmed == "-" || trimmed == "- " {
                suppressAutoContinue = true
                let lineStart = beforeNewline.lastIndex(of: "\n").map { new.index(after: $0) } ?? new.startIndex
                markdownText = String(new[new.startIndex..<lineStart]) + String(new[new.index(after: newlineIndex)...])
                return
            }
            prefix = leadingWhitespace + "- "
        } else if trimmed.hasPrefix("* ") {
            if trimmed == "*" || trimmed == "* " {
                suppressAutoContinue = true
                let lineStart = beforeNewline.lastIndex(of: "\n").map { new.index(after: $0) } ?? new.startIndex
                markdownText = String(new[new.startIndex..<lineStart]) + String(new[new.index(after: newlineIndex)...])
                return
            }
            prefix = leadingWhitespace + "* "
        } else if trimmed.hasPrefix("> ") {
            if trimmed == ">" || trimmed == "> " {
                suppressAutoContinue = true
                let lineStart = beforeNewline.lastIndex(of: "\n").map { new.index(after: $0) } ?? new.startIndex
                markdownText = String(new[new.startIndex..<lineStart]) + String(new[new.index(after: newlineIndex)...])
                return
            }
            prefix = leadingWhitespace + "> "
        } else if let match = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) {
            let numStr = trimmed[match].dropLast(2)
            if let num = Int(numStr) {
                if trimmed == "\(num). " || trimmed == "\(num)." {
                    suppressAutoContinue = true
                    let lineStart = beforeNewline.lastIndex(of: "\n").map { new.index(after: $0) } ?? new.startIndex
                    markdownText = String(new[new.startIndex..<lineStart]) + String(new[new.index(after: newlineIndex)...])
                    return
                }
                prefix = leadingWhitespace + "\(num + 1). "
            }
        }

        if let prefix {
            suppressAutoContinue = true
            let afterNewline = new.index(after: newlineIndex)
            markdownText = String(new[new.startIndex...newlineIndex]) + prefix + String(new[afterNewline...])
        }
    }

    private func findInsertedNewline(old: String, new: String) -> String.Index? {
        let oldChars = Array(old)
        let newChars = Array(new)
        guard newChars.count == oldChars.count + 1 else { return nil }

        for i in 0..<newChars.count {
            if i >= oldChars.count || newChars[i] != oldChars[i] {
                if newChars[i] == "\n" {
                    return new.index(new.startIndex, offsetBy: i)
                }
                return nil
            }
        }
        return nil
    }

    private func handleMarkdownShortcut(_ event: NSEvent) -> Bool {
        guard !showPreview, activeTextView != nil else { return false }
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

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
        case ([.command], "`"):
            wrapSelection("`")
            return true
        case ([.command, .shift], "l"):
            insertPrefix("- ")
            return true
        case ([.command, .shift], "t"):
            insertPrefix("- [ ] ")
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
}
