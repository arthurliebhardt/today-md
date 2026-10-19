import AppKit
import SwiftUI

enum SidebarSelection: Hashable {
    case all
    case list(UUID)
}

enum AuxiliaryPanelMode: String, CaseIterable, Identifiable {
    case details
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details:
            return "Details"
        case .week:
            return "Week"
        }
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case board
    case planner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board:
            return "Board"
        case .planner:
            return "Planner"
        }
    }
}

@MainActor
enum TaskVisibilityScope {
    static func tasks(for selection: SidebarSelection, store: TodayMdStore) -> [TaskItem] {
        switch selection {
        case .all:
            return store.allTasks
        case .list(let listID):
            guard let list = store.list(id: listID) else { return [] }
            return list.items.sorted(by: taskSort)
        }
    }
}

enum ContentCalendarVisibilitySelection {
    static func resolvedIdentifiers(from rawValue: String, availableCalendars: [TodayMdCalendarSummary]) -> Set<String> {
        let availableIdentifiers = Set(availableCalendars.map(\.id))
        guard !availableIdentifiers.isEmpty else { return [] }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return availableIdentifiers }

        let selectedIdentifiers = Set(trimmedValue.split(separator: ",").map(String.init))
            .intersection(availableIdentifiers)

        return selectedIdentifiers.isEmpty ? availableIdentifiers : selectedIdentifiers
    }

    static func storedValue(for identifiers: Set<String>, availableCalendars: [TodayMdCalendarSummary]) -> String {
        let availableIdentifiers = Set(availableCalendars.map(\.id))
        guard !availableIdentifiers.isEmpty else { return "" }

        let sanitizedIdentifiers = identifiers.intersection(availableIdentifiers)
        guard !sanitizedIdentifiers.isEmpty, sanitizedIdentifiers.count < availableIdentifiers.count else {
            return ""
        }

        return sanitizedIdentifiers.sorted().joined(separator: ",")
    }
}

@MainActor
struct WindowTitleSyncView: NSViewRepresentable {
    let title: String

    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        weak var window: NSWindow?
        var title = ""

        func applyTitle() {
            guard let window else { return }
            window.titleVisibility = .visible
            if window.title != title {
                window.title = title
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindowChange = { [coordinator = context.coordinator] window in
            coordinator.window = window
            coordinator.applyTitle()
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.title = title
        context.coordinator.window = nsView.window
        context.coordinator.applyTitle()
        nsView.onWindowChange = { [coordinator = context.coordinator] window in
            coordinator.window = window
            coordinator.applyTitle()
        }
    }
}

struct ShortcutSequenceView: View {
    enum Tone {
        case accent
        case secondary
    }

    let shortcut: String
    var tone: Tone = .accent
    var font: Font = .system(.subheadline, design: .monospaced, weight: .semibold)

    private var tokens: [String] {
        shortcut
            .components(separatedBy: CharacterSet(charactersIn: "-+"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent:
            return .blue
        case .secondary:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent:
            return Color.blue.opacity(0.10)
        case .secondary:
            return Color.secondary.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .accent:
            return Color.blue.opacity(0.18)
        case .secondary:
            return Color.secondary.opacity(0.18)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                shortcutToken(token)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func shortcutToken(_ token: String) -> some View {
        Group {
            if token.caseInsensitiveCompare("cmd") == .orderedSame || token.caseInsensitiveCompare("command") == .orderedSame {
                Image(systemName: "command")
            } else {
                Text(token)
            }
        }
        .font(font)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .foregroundStyle(foregroundColor)
    }
}

@MainActor
struct WindowChromeInsetReader: NSViewRepresentable {
    let onTopInsetChange: (CGFloat) -> Void

    final class TrackingView: NSView {
        var onTopInsetChange: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportTopInset()
        }

        override func layout() {
            super.layout()
            reportTopInset()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            reportTopInset()
        }

        private func reportTopInset() {
            guard let window else { return }
            let topInset = max(0, window.frame.height - window.contentLayoutRect.maxY)
            onTopInsetChange?(topInset)
        }
    }

    @MainActor
    final class Coordinator {
        private var lastReportedInset: CGFloat = -1

        func update(topInset: CGFloat, onTopInsetChange: @escaping (CGFloat) -> Void) {
            guard abs(topInset - lastReportedInset) > 0.5 else { return }
            lastReportedInset = topInset

            DispatchQueue.main.async {
                onTopInsetChange(topInset)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onTopInsetChange = { topInset in
            context.coordinator.update(topInset: topInset, onTopInsetChange: onTopInsetChange)
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onTopInsetChange = { topInset in
            context.coordinator.update(topInset: topInset, onTopInsetChange: onTopInsetChange)
        }
        nsView.layoutSubtreeIfNeeded()
    }
}
