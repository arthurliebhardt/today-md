import AppKit
import Carbon
import SwiftUI

enum QuickAddShortcut {
    static let display = "Cmd-_"
    static let keyEquivalent: Character = "-"
    static let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static let keyCode: UInt32 = UInt32(kVK_ANSI_Minus)
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf16.reduce(0) { partialResult, scalar in
        (partialResult << 8) + OSType(scalar)
    }
}

private extension Notification.Name {
    static let globalQuickAddHotKeyTriggered = Notification.Name("TodayMdGlobalQuickAddHotKeyTriggered")
}

private final class GlobalQuickAddHotKeyMonitor {
    private let hotKeyID = EventHotKeyID(signature: fourCharCode("TMDQ"), id: 1)
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init() {
        register()
    }

    deinit {
        unregister()
    }

    private func register() {
        guard eventHandler == nil, hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                let monitor = Unmanaged<GlobalQuickAddHotKeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var pressedHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard status == noErr,
                      pressedHotKeyID.signature == monitor.hotKeyID.signature,
                      pressedHotKeyID.id == monitor.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .globalQuickAddHotKeyTriggered, object: nil)
                }

                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            eventHandler = nil
            return
        }

        let hotKeyStatus = RegisterEventHotKey(
            QuickAddShortcut.keyCode,
            QuickAddShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if hotKeyStatus != noErr {
            unregister()
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

private final class FloatingDynamicIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class GlobalDynamicIslandController: NSObject, ObservableObject {
    static let isEnabledDefaultsKey = "TodayMdGlobalDynamicIslandEnabled"

    private weak var store: TodayMdStore?
    private let userDefaults: UserDefaults
    private let viewModel = GlobalDynamicIslandViewModel()
    private let hotKeyMonitor = GlobalQuickAddHotKeyMonitor()
    private var panel: FloatingDynamicIslandPanel?
    private var hostingView: NSHostingView<GlobalDynamicIslandView>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var dismissWorkItem: DispatchWorkItem?
    private var panelIsHovered = false
    private var lastPresentedScreen: NSScreen?
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
        super.init()

        viewModel.onSubmit = { [weak self] in
            self?.submitTask()
        }
        viewModel.onCancel = { [weak self] in
            self?.hide()
        }
        viewModel.onActivate = { [weak self] in
            self?.activatePanelForTextEntry()
        }
        viewModel.onHoverChanged = { [weak self] hovering in
            self?.handlePanelHoverChanged(hovering)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGlobalQuickAddHotKeyNotification(_:)),
            name: .globalQuickAddHotKeyTriggered,
            object: nil
        )
    }

    @objc private func handleGlobalQuickAddHotKeyNotification(_ notification: Notification) {
        presentQuickAdd()
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
            styleMask: [.borderless],
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
        ensurePanel()
        cancelDismiss()
        positionPanel(on: screen)
        lastPresentedScreen = screen

        guard let panel else { return }
        if panel.isVisible {
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
    }

    func presentQuickAdd() {
        guard let screen = preferredScreen() else { return }
        show(on: screen)
        activatePanelForTextEntry()
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

    private func preferredScreen() -> NSScreen? {
        if let screen = screen(containing: NSEvent.mouseLocation) {
            return screen
        }

        if let keyWindowScreen = NSApp.keyWindow?.screen {
            return keyWindowScreen
        }

        if let lastPresentedScreen {
            return lastPresentedScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func activatePanelForTextEntry() {
        ensurePanel()

        if let screen = preferredScreen() {
            positionPanel(on: screen)
            lastPresentedScreen = screen
        }

        guard let panel else { return }
        cancelDismiss()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        viewModel.requestFocus()
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
        guard let store else {
            hide()
            return
        }

        _ = store.quickAddTask(title: viewModel.draftTitle, to: .today, listID: nil)
        hide()
    }
}

@MainActor
final class GlobalDynamicIslandViewModel: ObservableObject {
    @Published var draftTitle = ""
    @Published private(set) var focusNonce = 0

    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onActivate: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    func requestFocus() {
        focusNonce += 1
    }

    func reset() {
        draftTitle = ""
    }
}

private final class GlobalDynamicIslandTextField: NSTextField {
    var onActivate: (() -> Void)?
    var onCancel: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct GlobalDynamicIslandTextFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let focusNonce: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> GlobalDynamicIslandTextField {
        let textField = GlobalDynamicIslandTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14, weight: .semibold)
        textField.textColor = .white
        textField.placeholderAttributedString = NSAttributedString(
            string: "+ Task",
            attributes: [
                .foregroundColor: NSColor.systemOrange.withAlphaComponent(0.92),
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ]
        )
        textField.onActivate = onActivate
        textField.onCancel = onCancel
        textField.stringValue = text
        if let cell = textField.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.usesSingleLineMode = true
            cell.isScrollable = true
            cell.lineBreakMode = .byTruncatingTail
        }
        return textField
    }

    func updateNSView(_ textField: GlobalDynamicIslandTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        textField.onActivate = onActivate
        textField.onCancel = onCancel

        if textField.stringValue != text {
            textField.stringValue = text
        }

        if context.coordinator.lastFocusedNonce != focusNonce {
            context.coordinator.lastFocusedNonce = focusNonce
            DispatchQueue.main.async {
                guard let window = textField.window else { return }
                window.makeFirstResponder(textField)
                if let editor = window.fieldEditor(false, for: textField) as? NSTextView {
                    editor.insertionPointColor = .systemOrange
                    editor.selectedRange = NSRange(location: textField.stringValue.utf16.count, length: 0)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onCancel: () -> Void
        var lastFocusedNonce = -1

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            if text.wrappedValue != textField.stringValue {
                text.wrappedValue = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }

            return false
        }
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

                GlobalDynamicIslandTextFieldRepresentable(
                    text: $viewModel.draftTitle,
                    focusNonce: viewModel.focusNonce,
                    onSubmit: { viewModel.onSubmit?() },
                    onCancel: { viewModel.onCancel?() },
                    onActivate: { viewModel.onActivate?() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 24)
                .layoutPriority(1)

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
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .frame(width: 520, height: notchHeight, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering in
            viewModel.onHoverChanged?(hovering)
        }
        .onTapGesture {
            viewModel.onActivate?()
        }
    }
}
