import AppKit
import SwiftUI

private final class FloatingDynamicIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class GlobalDynamicIslandController: ObservableObject {
    static let isEnabledDefaultsKey = "TodayMdGlobalDynamicIslandEnabled"

    private weak var store: TodayMdStore?
    private let userDefaults: UserDefaults
    private let viewModel = GlobalDynamicIslandViewModel()
    private var panel: FloatingDynamicIslandPanel?
    private var hostingView: NSHostingView<GlobalDynamicIslandView>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var dismissWorkItem: DispatchWorkItem?
    private var panelIsHovered = false
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            userDefaults.set(isEnabled, forKey: Self.isEnabledDefaultsKey)

            if isEnabled {
                ensurePanel()
                if store != nil {
                    startMonitorsIfNeeded()
                }
            } else {
                stopMonitors()
                hide()
            }
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.isEnabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = userDefaults.bool(forKey: Self.isEnabledDefaultsKey)
        }

        viewModel.onSubmit = { [weak self] in
            self?.submitTask()
        }
        viewModel.onCancel = { [weak self] in
            self?.hide()
        }
        viewModel.onHoverChanged = { [weak self] hovering in
            self?.handlePanelHoverChanged(hovering)
        }
    }

    func attach(store: TodayMdStore) {
        self.store = store
        ensurePanel()
        if isEnabled {
            startMonitorsIfNeeded()
        } else {
            stopMonitors()
            hide()
        }
    }

    private func ensurePanel() {
        let rootView = GlobalDynamicIslandView(viewModel: viewModel)

        if let hostingView {
            hostingView.rootView = rootView
            return
        }

        let panel = FloatingDynamicIslandPanel(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 104),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        contentView.addSubview(hostingView)
        panel.contentView = contentView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func startMonitorsIfNeeded() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved(NSEvent.mouseLocation)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(NSEvent.mouseLocation)
            }
            return event
        }

        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalClick(NSEvent.mouseLocation)
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalClick(NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func stopMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func handleMouseMoved(_ point: NSPoint) {
        guard isEnabled else { return }
        guard let screen = screen(containing: point) else { return }
        guard triggerRect(for: screen).contains(point) else { return }
        show(on: screen)
    }

    private func handleGlobalClick(_ point: NSPoint) {
        guard let panel, panel.isVisible else { return }
        if panel.frame.contains(point) { return }
        hide()
    }

    private func handlePanelHoverChanged(_ hovering: Bool) {
        panelIsHovered = hovering
        if hovering {
            cancelDismiss()
        } else {
            scheduleDismissIfNeeded()
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func triggerRect(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let width: CGFloat = 260
        let height: CGFloat = 14
        return CGRect(
            x: frame.midX - (width / 2),
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func show(on screen: NSScreen) {
        guard isEnabled else { return }
        ensurePanel()
        cancelDismiss()
        positionPanel(on: screen)

        guard let panel else { return }
        if panel.isVisible {
            viewModel.requestFocus()
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        viewModel.requestFocus()
    }

    private func positionPanel(on screen: NSScreen) {
        guard let panel else { return }
        let frame = screen.frame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - (panelSize.width / 2),
            y: frame.maxY - panelSize.height + 18
        )
        panel.setFrameOrigin(origin)
    }

    private func cancelDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func scheduleDismissIfNeeded() {
        cancelDismiss()
        guard viewModel.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !panelIsHovered else { return }
            hide()
        }

        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func hide() {
        cancelDismiss()
        panelIsHovered = false
        viewModel.reset()
        panel?.orderOut(nil)
    }

    private func submitTask() {
        let title = viewModel.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let store else {
            hide()
            return
        }

        _ = store.addUnassignedTask(title: title, block: .today)
        hide()
    }
}

@MainActor
final class GlobalDynamicIslandViewModel: ObservableObject {
    @Published var draftTitle = ""
    @Published private(set) var focusNonce = 0

    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    func requestFocus() {
        focusNonce += 1
    }

    func reset() {
        draftTitle = ""
    }
}

private struct DynamicIslandNotchShape: Shape {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct GlobalDynamicIslandView: View {
    @ObservedObject var viewModel: GlobalDynamicIslandViewModel
    @FocusState private var isTextFieldFocused: Bool

    private let notchWidth: CGFloat = 640
    private let notchHeight: CGFloat = 92
    private let accentStart = Color.orange.opacity(0.95)
    private let accentEnd = Color.orange.opacity(0.65)

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentStart, accentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            DynamicIslandNotchShape(
                topCornerRadius: 12,
                bottomCornerRadius: 28
            )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.995),
                            Color.black.opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    DynamicIslandNotchShape(
                        topCornerRadius: 12,
                        bottomCornerRadius: 28
                    )
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .frame(width: notchWidth, height: notchHeight)
                .shadow(color: Color.black.opacity(0.42), radius: 18, y: 10)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentGradient)

                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)

                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                .shadow(color: accentStart.opacity(0.28), radius: 10, y: 4)

                ZStack(alignment: .leading) {
                    if viewModel.draftTitle.isEmpty {
                        Text("+ Task")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentGradient)
                    }

                    TextField("", text: $viewModel.draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .tint(accentStart)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            viewModel.onSubmit?()
                        }
                        .onExitCommand {
                            viewModel.onCancel?()
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Today")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentGradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(accentStart.opacity(0.16))
                    )
                    .overlay(
                        Capsule()
                            .stroke(accentEnd.opacity(0.30), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .frame(width: 520, height: notchHeight, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { hovering in
            viewModel.onHoverChanged?(hovering)
        }
        .onAppear {
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
        .onChange(of: viewModel.focusNonce, initial: true) { _, _ in
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }
}
