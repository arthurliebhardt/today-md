import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case interface
    case pro
    case calendar
    case data
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interface:
            return "Interface"
        case .pro:
            return "today-md Pro"
        case .calendar:
            return "Calendar"
        case .data:
            return "Data"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .interface:
            return "Appearance and quick capture"
        case .pro:
            return "One-time lifetime unlock"
        case .calendar:
            return "Availability and time blocking"
        case .data:
            return "Backups, archive, and sync source"
        case .shortcuts:
            return "App commands and cheatsheet"
        }
    }

    var systemImage: String {
        switch self {
        case .interface:
            return "paintbrush.pointed.fill"
        case .pro:
            return "sparkles"
        case .calendar:
            return "calendar.badge.clock"
        case .data:
            return "internaldrive"
        case .shortcuts:
            return "command"
        }
    }

    var tint: Color {
        switch self {
        case .interface:
            return .indigo
        case .pro:
            return .orange
        case .calendar:
            return .orange
        case .data:
            return .orange
        case .shortcuts:
            return .purple
        }
    }
}

struct SettingsView: View {
    @Environment(TodayMdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarService: TodayMdCalendarService
    @EnvironmentObject private var syncService: TodayMdSyncService
    @EnvironmentObject private var presentationState: AppPresentationState
    @EnvironmentObject private var dynamicIslandController: GlobalDynamicIslandController
    @EnvironmentObject private var purchaseManager: TodayMdPurchaseManager
    @AppStorage(TodayMdPreferenceKey.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(TodayMdPreferenceKey.calendarDefaultDurationMinutes) private var calendarDefaultDurationMinutes = 60
    @AppStorage(TodayMdPreferenceKey.calendarDefaultIdentifier) private var calendarDefaultIdentifier = ""
    @AppStorage(TodayMdPreferenceKey.calendarVisibleIdentifiers) private var calendarVisibleIdentifiersRaw = ""

    @State private var selectedSettingsSection: SettingsSection = .interface
    @State private var alert: SettingsAlert?

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    private var appearanceModeSelection: Binding<AppAppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { appearanceModeRawValue = $0.rawValue }
        )
    }

    private var calendarPreferredIdentifier: String? {
        calendarDefaultIdentifier.isEmpty ? nil : calendarDefaultIdentifier
    }

    private var writableCalendars: [TodayMdCalendarSummary] {
        calendarService.writableCalendars
    }

    private var calendarDefaultDurationSelection: Binding<Int> {
        Binding(
            get: {
                [30, 60, 90, 120].contains(calendarDefaultDurationMinutes) ? calendarDefaultDurationMinutes : 60
            },
            set: { calendarDefaultDurationMinutes = $0 }
        )
    }

    private var calendarStatusColor: Color {
        switch calendarService.authorizationStatus {
        case .notDetermined:
            return .secondary
        case .denied, .restricted:
            return .red
        case .writeOnly:
            return .orange
        case .fullAccess:
            return .green
        }
    }

    private var calendarDestinationSummary: String {
        if let selectedCalendar = calendarService.selectedDestinationCalendar(preferredIdentifier: calendarPreferredIdentifier) {
            return selectedCalendar.displayTitle
        }

        return "No writable calendar found"
    }

    private var availableCalendars: [TodayMdCalendarSummary] {
        calendarService.calendars
    }

    private var activeCalendarIdentifiers: Set<String> {
        ContentCalendarVisibilitySelection.resolvedIdentifiers(
            from: calendarVisibleIdentifiersRaw,
            availableCalendars: availableCalendars
        )
    }

    private var allCalendarsActive: Bool {
        availableCalendars.isEmpty || activeCalendarIdentifiers.count >= availableCalendars.count
    }

    private var syncStatusColor: Color {
        switch syncService.status {
        case .disabled:
            return .secondary
        case .idle:
            return .green
        case .syncing:
            return .blue
        case .conflict:
            return .orange
        case .error:
            return .red
        }
    }

    private var syncFolderActionTitle: String {
        if !purchaseManager.hasProAccess {
            return "Enable Folder Sync — Pro"
        }

        return syncService.syncEnabled ? "Choose Sync Folder" : "Enable Sync"
    }

    private var syncFolderActionSubtitle: String {
        if syncService.syncEnabled {
            return "Switch the iCloud Drive or OneDrive folder that stores the shared snapshot and active markdown archive."
        }

        return "Choose a synced cloud folder and make its markdown archive the single shared source of truth."
    }

    private var syncLastSyncText: String {
        guard let lastSyncAt = syncService.lastSyncAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    private var markdownArchivePath: String? {
        if syncService.syncEnabled {
            return syncService.markdownArchivePath
        }
        return try? TodayMdMarkdownArchiveService.archivePath()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.09),
                    Color.blue.opacity(0.06),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange.opacity(0.95), Color.orange.opacity(0.65)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 54, height: 54)
                        .shadow(color: Color.orange.opacity(0.18), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Settings")
                                .font(.system(size: 28, weight: .bold))

                            Text("Keep the utility actions grouped instead of stacking the whole workspace into one long sheet.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Workspace")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(SettingsSection.allCases) { section in
                            settingsSectionButton(section)
                        }
                    }

                    Spacer()

                    Text("The actions stay the same, but only one group is visible at a time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 230, alignment: .topLeading)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsSectionHeader(
                            selectedSettingsSection.title,
                            subtitle: selectedSettingsSection.subtitle,
                            tint: selectedSettingsSection.tint
                        )

                        settingsSectionContent
                    }
                    .padding(.trailing, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(28)
            .frame(width: 760, height: 680)
        }
        .preferredColorScheme(appearanceMode.preferredColorScheme)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message)
            )
        }
        .onAppear {
            calendarService.refreshIfNeeded()
        }
        .task {
            await purchaseManager.prepare()
        }
        .sheet(isPresented: $purchaseManager.isPaywallPresented) {
            TodayMdProView(presentation: .sheet)
                .environmentObject(purchaseManager)
        }
    }

    var settingsSectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedSettingsSection {
            case .interface:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Appearance and quick capture")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.indigo.opacity(0.14))

                                Image(systemName: appearanceMode.systemImage)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.indigo)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("App appearance")
                                    .font(.headline)

                                Text("Choose whether today-md follows macOS or stays in a fixed light or dark theme.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)
                        }

                        Picker("Appearance", selection: appearanceModeSelection) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(appearanceMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.indigo.opacity(0.14), lineWidth: 1)
                    )

                    settingsToggleCard(
                        title: "Top Screen Notch",
                        subtitle: "Show the floating notch when the pointer reaches the top-center edge of the screen. You can always open it directly with \(QuickAddShortcut.display).",
                        systemImage: "rectangle.topthird.inset.filled",
                        tint: .indigo,
                        isOn: $dynamicIslandController.isEnabled
                    )

                    HStack(spacing: 8) {
                        Circle()
                            .fill(dynamicIslandController.isEnabled ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 10, height: 10)

                        Text(dynamicIslandController.isEnabled ? "The notch is active and can appear from the screen edge." : "The edge trigger is off, but you can still open quick add with \(QuickAddShortcut.display).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.indigo.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.indigo.opacity(0.12), lineWidth: 1)
                    )
                }

            case .pro:
                TodayMdProView(presentation: .settings)

            case .calendar:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Calendar blocking")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(calendarStatusColor)
                                .frame(width: 10, height: 10)

                            Text("Status: \(calendarService.authorizationStatus.label)")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(calendarService.authorizationStatus.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Calendars shown here come from macOS Calendar. Outlook / Exchange calendars appear here when the account is added to Calendar on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let lastError = calendarService.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.orange.opacity(0.14), lineWidth: 1)
                    )

                    VStack(spacing: 12) {
                        settingsActionCard(
                            title: calendarService.authorizationStatus.resolutionActionTitle,
                            subtitle: calendarService.authorizationStatus.resolutionActionSubtitle,
                            systemImage: calendarService.authorizationStatus.resolutionActionSystemImage,
                            tint: .orange,
                            action: requestCalendarAccessFromSettings
                        )
                    }

                    if calendarService.authorizationStatus.canReadEvents {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Calendar for entries")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text("Choose which calendar receives blockers created from tasks.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Picker("Destination calendar", selection: $calendarDefaultIdentifier) {
                                    ForEach(writableCalendars) { calendar in
                                        Text(calendar.displayTitle)
                                            .tag(calendar.id)
                                    }
                                }
                                .pickerStyle(.menu)

                                Text("Current target: \(calendarDestinationSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Default block length")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Picker("Default block length", selection: calendarDefaultDurationSelection) {
                                    Text("30m").tag(30)
                                    Text("60m").tag(60)
                                    Text("90m").tag(90)
                                    Text("120m").tag(120)
                                }
                                .pickerStyle(.segmented)

                                Text("Next open \(calendarDefaultDurationSelection.wrappedValue)m slot: \(calendarSuggestedSlotText(durationMinutes: calendarDefaultDurationSelection.wrappedValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.86))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Active calendars")
                                    .font(.headline)

                                Spacer(minLength: 12)

                                if !allCalendarsActive, !availableCalendars.isEmpty {
                                    Button("Show All") {
                                        calendarVisibleIdentifiersRaw = ""
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                }
                            }

                            Text(
                                availableCalendars.isEmpty
                                    ? "No calendars are available yet."
                                    : allCalendarsActive
                                        ? "All calendars are active across the planner views."
                                        : "\(activeCalendarIdentifiers.count) of \(availableCalendars.count) calendars are active across the planner views."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            if availableCalendars.isEmpty {
                                Text("Add an account in the macOS Calendar app, then refresh here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .leading)],
                                    alignment: .leading,
                                    spacing: 10
                                ) {
                                    ForEach(availableCalendars) { calendar in
                                        let isActive = activeCalendarIdentifiers.contains(calendar.id)

                                        Button {
                                            toggleActiveCalendar(calendar)
                                        } label: {
                                            HStack(alignment: .center, spacing: 10) {
                                                Circle()
                                                    .fill(Color(nsColor: calendar.nsColor))
                                                    .frame(width: 10, height: 10)

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(calendar.title)
                                                        .font(.subheadline.weight(.semibold))
                                                        .lineLimit(1)

                                                    Text(calendar.subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }

                                                Spacer(minLength: 8)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(
                                                        isActive
                                                            ? Color(nsColor: calendar.nsColor).opacity(0.16)
                                                            : Color.secondary.opacity(0.08)
                                                    )
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(
                                                        isActive
                                                            ? Color(nsColor: calendar.nsColor).opacity(0.32)
                                                            : Color.secondary.opacity(0.14),
                                                        lineWidth: 1
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .help("\(calendar.displayTitle)\n\(calendar.subtitle)")
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.86))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                        )
                    }
                }

            case .data:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Data source and backups")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(syncStatusColor)
                                .frame(width: 10, height: 10)

                            Text(syncService.syncEnabled ? "Source: Sync Folder" : "Source: Local Archive")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(
                            syncService.syncEnabled
                                ? "The sync folder is the active markdown archive and single source of truth while sync is enabled."
                                : "The local Application Support archive is the active markdown archive until sync is enabled."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Last successful sync: \(syncLastSyncText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let folderPath = syncService.folderPath {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sync folder")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(folderPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let lastError = syncService.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.teal.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.teal.opacity(0.14), lineWidth: 1)
                    )

                    VStack(spacing: 12) {
                        settingsActionCard(
                            title: "Import Backup",
                            subtitle: "Select a JSON backup file and merge it or replace the current data.",
                            systemImage: "square.and.arrow.down",
                            tint: .blue,
                            action: startImport
                        )

                        settingsActionCard(
                            title: "Export Backup",
                            subtitle: "Choose a folder and create a timestamped JSON backup plus separate markdown note files.",
                            systemImage: "square.and.arrow.up",
                            tint: .orange,
                            action: startExport
                        )

                        settingsActionCard(
                            title: "Open Markdown Archive",
                            subtitle: syncService.syncEnabled
                                ? "Open the markdown archive inside the selected sync folder."
                                : "Open the local folder where tasks are mirrored as reusable .md files.",
                            systemImage: "doc.text",
                            tint: .green,
                            action: openMarkdownArchive
                        )

                        settingsActionCard(
                            title: syncFolderActionTitle,
                            subtitle: syncFolderActionSubtitle,
                            systemImage: "icloud",
                            tint: .teal,
                            action: startSyncFolderSelection
                        )

                        settingsActionCard(
                            title: "Sync Now",
                            subtitle: "Re-read the cloud snapshot, pull if needed, or push this Mac's pending changes.",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .blue,
                            isEnabled: syncService.syncEnabled,
                            action: syncNowFromSettings
                        )

                        settingsActionCard(
                            title: "Open Sync Folder",
                            subtitle: "Reveal the chosen sync folder so you can inspect the JSON snapshot and markdown archive.",
                            systemImage: "folder",
                            tint: .green,
                            isEnabled: syncService.hasFolderSelection,
                            action: openSyncFolder
                        )

                        settingsActionCard(
                            title: "Disable Sync",
                            subtitle: "Keep local data on this Mac, but stop reading from and writing to the shared sync folder.",
                            systemImage: "xmark.icloud",
                            tint: .red,
                            isEnabled: syncService.syncEnabled,
                            action: disableSyncFromSettings
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                    )

                    if let markdownArchivePath {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(syncService.syncEnabled ? "Active archive location" : "Local archive location")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(markdownArchivePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

            case .shortcuts:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Keyboard shortcuts")
                        .font(.headline)

                    settingsActionCard(
                        title: "Open Shortcut Cheatsheet",
                        subtitle: "See the current selection, editor, board, and app shortcuts in one place.",
                        systemImage: "command",
                        tint: .purple,
                        action: openShortcutCheatsheetFromSettings
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick access")
                            .font(.subheadline.weight(.semibold))

                        shortcutPreviewRow(title: "Open shortcuts", shortcut: "Cmd-/")
                        shortcutPreviewRow(title: "Open settings", shortcut: "Cmd-,")
                        shortcutPreviewRow(title: "Quick add task", shortcut: QuickAddShortcut.display)
                        shortcutPreviewRow(title: "New task", shortcut: "Cmd-N")
                        shortcutPreviewRow(title: "Mark done", shortcut: "Cmd-Shift-D")
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.purple.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.purple.opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.bottom, 56)
    }

    func settingsSectionButton(_ section: SettingsSection) -> some View {
        let isSelected = selectedSettingsSection == section

        return Button {
            if section == .calendar, !purchaseManager.hasProAccess {
                selectedSettingsSection = .pro
            } else {
                selectedSettingsSection = section
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(section.tint.opacity(isSelected ? 0.16 : 0.08))

                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? section.tint : .secondary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if section == .calendar, !purchaseManager.hasProAccess {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.92) : Color.white.opacity(0.001))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? section.tint.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func settingsSectionHeader(_ title: String, subtitle: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))

                Image(systemName: selectedSettingsSection.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    func settingsActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(isEnabled ? 0.14 : 0.08))

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isEnabled ? tint : .secondary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isEnabled ? .primary : .secondary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
    }

    func settingsToggleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(isOn.wrappedValue ? 0.14 : 0.08))

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : .secondary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(isOn.wrappedValue ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isOn.wrappedValue ? tint.opacity(0.14) : Color.secondary.opacity(0.12))
                    )

                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(tint)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }

    private func startImport() {
        TodayMdTransferService.importData(into: store) { archive, mode in
            purchaseManager.authorizeImport(
                archive,
                mode: mode,
                currentListCount: store.lists.count,
                currentTaskCount: store.allTasks.count
            )
        }
    }

    private func startExport() {
        TodayMdTransferService.exportData(from: store)
    }

    private func openShortcutCheatsheetFromSettings() {
        dismiss()
        presentationState.presentKeyboardShortcuts()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startSyncFolderSelection() {
        guard purchaseManager.hasProAccess else {
            purchaseManager.presentPaywall(message: "Folder Sync is included with the lifetime Pro unlock.")
            return
        }

        syncService.promptForFolderSelection()
    }

    private func syncNowFromSettings() {
        guard purchaseManager.hasProAccess else {
            purchaseManager.presentPaywall(message: "Folder Sync is included with the lifetime Pro unlock.")
            return
        }

        syncService.syncNow()
    }

    private func disableSyncFromSettings() {
        syncService.disableSync()
    }

    private func requestCalendarAccessFromSettings() {
        calendarService.resolveAuthorization()
    }

    private func openMarkdownArchive() {
        if syncService.syncEnabled {
            syncService.openMarkdownArchiveFolder()
            return
        }

        do {
            try TodayMdMarkdownArchiveService.revealArchiveFolder()
        } catch {
            presentError(title: "Open Markdown Archive Failed", error: error)
        }
    }

    private func openSyncFolder() {
        syncService.openSyncFolder()
    }

    private func calendarSuggestedSlotText(durationMinutes: Int) -> String {
        guard let interval = calendarService.suggestedBlockInterval(durationMinutes: durationMinutes) else {
            return "No open slot found in the next two weeks."
        }

        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: interval.start, to: interval.end)
    }

    private func toggleActiveCalendar(_ calendar: TodayMdCalendarSummary) {
        let availableIdentifiers = Set(availableCalendars.map(\.id))
        guard availableIdentifiers.contains(calendar.id) else { return }

        var updatedSelection = activeCalendarIdentifiers

        if allCalendarsActive {
            updatedSelection = availableIdentifiers.subtracting([calendar.id])
        } else if updatedSelection.contains(calendar.id) {
            guard updatedSelection.count > 1 else { return }
            updatedSelection.remove(calendar.id)
        } else {
            updatedSelection.insert(calendar.id)
        }

        calendarVisibleIdentifiersRaw = ContentCalendarVisibilitySelection.storedValue(
            for: updatedSelection,
            availableCalendars: availableCalendars
        )
    }

    private func shortcutPreviewRow(title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            ShortcutSequenceView(shortcut: shortcut, tone: .secondary)
        }
    }

    private func presentError(title: String, error: Error) {
        alert = SettingsAlert(
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }
}

private struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
