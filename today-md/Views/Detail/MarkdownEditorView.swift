import SwiftUI

struct MarkdownEditorView: View {
    @Environment(TodayMdStore.self) private var store
    let task: TaskItem

    @State private var showPreview = false
    @State private var markdownText = ""
    @State private var saveTask: DispatchWorkItem?
    @State private var suppressAutoContinue = false
    @State private var cachedTextView: NSTextView?

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
    }

    private var mdToolbar: some View {
        HStack(spacing: 1) {
            mdBtn("H1", icon: nil, tip: "Heading 1 (⌘1)") { insertPrefix("# ") }
            mdBtn("H2", icon: nil, tip: "Heading 2 (⌘2)") { insertPrefix("## ") }
            mdBtn("H3", icon: nil, tip: "Heading 3 (⌘3)") { insertPrefix("### ") }

            mdDivider

            mdBtn(nil, icon: "bold", tip: "Bold (⌘B)") { wrapSelection("**") }
            mdBtn(nil, icon: "italic", tip: "Italic (⌘I)") { wrapSelection("_") }
            mdBtn(nil, icon: "strikethrough", tip: "Strikethrough") { wrapSelection("~~") }
            mdBtn(nil, icon: "chevron.left.forwardslash.chevron.right", tip: "Code (⌘`)") { wrapSelection("`") }

            mdDivider

            mdBtn(nil, icon: "list.bullet", tip: "Bullet List (⌘⇧L)") { insertPrefix("- ") }
            mdBtn(nil, icon: "list.number", tip: "Numbered List") { insertPrefix("1. ") }
            mdBtn(nil, icon: "checkmark.square", tip: "Task (⌘⇧T)") { insertPrefix("- [ ] ") }

            mdDivider

            mdBtn(nil, icon: "text.quote", tip: "Quote") { insertPrefix("> ") }
            mdBtn(nil, icon: "minus", tip: "Divider") { appendAtCursor("\n---\n") }
            mdBtn(nil, icon: "curlybraces", tip: "Code Block") { appendAtCursor("\n```\n\n```\n") }

            Spacer()
        }
    }

    private var mdDivider: some View {
        Divider().frame(height: 20).padding(.horizontal, 6)
    }

    private func mdBtn(_ label: String?, icon: String?, tip: String, action: @escaping () -> Void) -> some View {
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
            .font(.system(size: 13))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .foregroundStyle(.secondary)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
        }
        .buttonStyle(.borderless)
        .help(tip)
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
