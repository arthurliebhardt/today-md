import Foundation
import SwiftUI

struct MarkdownPreview: View {
    @Binding var markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case header(Int, String)
        case paragraph(String)
        case listItem(String)
        case checkbox(Bool, String, Int) // checked, text, line index
        case numberedItem(Int, String)
        case codeBlock(String)
        case divider
        case empty
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        let lines = markdown.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                blocks.append(.empty)
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.header(1, String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.header(2, String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                blocks.append(.header(3, String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                blocks.append(.checkbox(true, String(trimmed.dropFirst(6)), lineIndex))
            } else if trimmed.hasPrefix("- [ ] ") {
                blocks.append(.checkbox(false, String(trimmed.dropFirst(6)), lineIndex))
            } else if trimmed.hasPrefix("- ") {
                blocks.append(.listItem(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("* ") {
                blocks.append(.listItem(String(trimmed.dropFirst(2))))
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let numStr = trimmed[match].trimmingCharacters(in: .whitespaces).dropLast()
                let content = String(trimmed[match.upperBound...])
                blocks.append(.numberedItem(Int(numStr) ?? 1, content))
            } else {
                blocks.append(.paragraph(trimmed))
            }
        }

        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
        }

        return blocks
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .header(let level, let text):
            Text(inlineMarkdown(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
        case .listItem(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\u{2022}")
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(text))
                    .font(.body)
            }
        case .checkbox(let checked, let text, let lineIndex):
            Button {
                toggleCheckbox(at: lineIndex)
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? .green : .secondary)
                        .font(.system(size: 16))
                    Text(inlineMarkdown(text))
                        .font(.body)
                        .strikethrough(checked)
                        .foregroundStyle(checked ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)
        case .numberedItem(let num, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(inlineMarkdown(text))
                    .font(.body)
            }
        case .codeBlock(let code):
            Text(code)
                .font(.body.monospaced())
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
        case .divider:
            Divider()
        case .empty:
            Spacer().frame(height: 2)
        }
    }

    private func toggleCheckbox(at lineIndex: Int) {
        var lines = markdown.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        let line = lines[lineIndex]
        if line.contains("- [ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else if line.contains("- [x] ") || line.contains("- [X] ") {
            lines[lineIndex] = line
                .replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
        }
        markdown = lines.joined(separator: "\n")
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
