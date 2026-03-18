import SwiftUI

struct SearchPresentationQuery {
    let terms: [String]

    init(_ rawValue: String) {
        terms = rawValue
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        terms.isEmpty
    }

    func highlightedText(for text: String, highlightColor: Color = .yellow.opacity(0.35)) -> AttributedString {
        var attributed = AttributedString(text)
        guard !terms.isEmpty else { return attributed }

        for range in mergedRanges(in: text) {
            guard
                let lowerBound = AttributedString.Index(range.lowerBound, within: attributed),
                let upperBound = AttributedString.Index(range.upperBound, within: attributed)
            else {
                continue
            }

            attributed[lowerBound..<upperBound].backgroundColor = highlightColor
        }

        return attributed
    }

    func preview(for task: TaskItem) -> String? {
        guard !containsMatch(in: task.title) else { return nil }

        for candidate in task.searchPreviewCandidates {
            if containsMatch(in: candidate) {
                return excerpt(aroundFirstMatchIn: candidate)
            }
        }

        return nil
    }

    func containsMatch(in text: String) -> Bool {
        !mergedRanges(in: text).isEmpty
    }

    func matchingExcerpts(in text: String, limit: Int = 3) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { containsMatch(in: $0) }
            .prefix(limit)
            .map { excerpt(aroundFirstMatchIn: $0) }
    }

    private func mergedRanges(in text: String) -> [Range<String.Index>] {
        guard !terms.isEmpty, !text.isEmpty else { return [] }

        let ranges = terms.flatMap { term in
            allRanges(of: term, in: text)
        }
        .sorted { $0.lowerBound < $1.lowerBound }

        guard var current = ranges.first else { return [] }

        var merged: [Range<String.Index>] = []
        for range in ranges.dropFirst() {
            if range.lowerBound <= current.upperBound {
                if range.upperBound > current.upperBound {
                    current = current.lowerBound..<range.upperBound
                }
            } else {
                merged.append(current)
                current = range
            }
        }

        merged.append(current)
        return merged
    }

    private func allRanges(of term: String, in text: String) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange,
            locale: .current
        ) {
            ranges.append(range)

            if range.upperBound == text.endIndex {
                break
            }

            searchRange = range.upperBound..<text.endIndex
        }

        return ranges
    }

    private func excerpt(aroundFirstMatchIn text: String, radius: Int = 36) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard let match = mergedRanges(in: collapsed).first else {
            return collapsed
        }

        let startOffset = max(0, collapsed.distance(from: collapsed.startIndex, to: match.lowerBound) - radius)
        let endOffset = min(
            collapsed.count,
            collapsed.distance(from: collapsed.startIndex, to: match.upperBound) + radius
        )

        let start = collapsed.index(collapsed.startIndex, offsetBy: startOffset)
        let end = collapsed.index(collapsed.startIndex, offsetBy: endOffset)

        var excerpt = String(collapsed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > collapsed.startIndex {
            excerpt = "…" + excerpt
        }
        if end < collapsed.endIndex {
            excerpt += "…"
        }

        return excerpt
    }
}

private extension TaskItem {
    var searchPreviewCandidates: [String] {
        var candidates = subtasks.map(\.title)
        candidates.append(contentsOf: checklistItems.map(\.title))

        if let note {
            candidates.append(
                contentsOf: note.content
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }

        return candidates
    }
}
