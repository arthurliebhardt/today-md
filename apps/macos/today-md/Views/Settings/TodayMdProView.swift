import SwiftUI

struct TodayMdProView: View {
    enum Presentation {
        case settings
        case sheet
    }

    @EnvironmentObject private var purchaseManager: TodayMdPurchaseManager
    @Environment(\.dismiss) private var dismiss

    let presentation: Presentation

    private let features = [
        ProFeature(
            title: "Unlimited Tasks and Lists",
            subtitle: "Move beyond the free allowance of one list and five total tasks.",
            systemImage: "infinity",
            tint: Color.purple
        ),
        ProFeature(
            title: "Calendar Planner",
            subtitle: "Plan tasks beside your real calendar and turn them into time blocks.",
            systemImage: "calendar.badge.clock",
            tint: Color.orange
        ),
        ProFeature(
            title: "Folder Sync",
            subtitle: "Sync through a folder you choose in iCloud Drive, OneDrive, or another provider.",
            systemImage: "arrow.triangle.2.circlepath.icloud",
            tint: Color.teal
        ),
        ProFeature(
            title: "Week View",
            subtitle: "Keep the week visible beside task details so upcoming work and calendar time stay connected.",
            systemImage: "calendar.day.timeline.left",
            tint: Color.blue
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(spacing: 12) {
                ForEach(features) { feature in
                    featureRow(feature)
                }
            }

            purchaseArea

            Text("Free includes one list and five total tasks. One purchase removes those limits—no subscription or account. Your data remains local and exportable whether or not you upgrade.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(presentation == .sheet ? 28 : 0)
        .frame(width: presentation == .sheet ? 540 : nil)
        .onChange(of: purchaseManager.hasProAccess) { _, hasProAccess in
            guard presentation == .sheet, hasProAccess else { return }
            dismiss()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: purchaseManager.hasProAccess ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: Color.orange.opacity(0.2), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(purchaseManager.hasProAccess ? "today-md Pro" : "Unlock today-md Pro")
                    .font(.system(size: presentation == .sheet ? 26 : 22, weight: .bold))

                Text(purchaseManager.hasProAccess ? unlockedSubtitle : "Own the complete Mac planning workflow for one lifetime price.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if presentation == .sheet {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
    }

    private var unlockedSubtitle: String {
        purchaseManager.isCommerceEnabled
            ? "The lifetime unlock is active for this Apple Account."
            : "Pro is included in this open-source build."
    }

    private func featureRow(_ feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(feature.tint.opacity(0.13))

                Image(systemName: feature.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(feature.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
    }

    @ViewBuilder
    private var purchaseArea: some View {
        if purchaseManager.hasProAccess {
            Label("Lifetime access unlocked", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.green.opacity(0.1)))
        } else {
            VStack(spacing: 12) {
                Button {
                    Task { await purchaseManager.purchaseLifetime() }
                } label: {
                    HStack {
                        if purchaseManager.purchaseStatus == .purchasing {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(purchaseButtonTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(purchaseManager.isBusy || purchaseManager.accessState == .checking)

                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    HStack(spacing: 8) {
                        if purchaseManager.purchaseStatus == .restoring {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Restore Purchase")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(purchaseManager.isBusy)

                if let message = purchaseManager.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if purchaseManager.accessState == .checking {
            return "Checking App Store…"
        }

        if let localizedPrice = purchaseManager.localizedPrice {
            return "Unlock Forever — \(localizedPrice)"
        }

        return "Unlock Forever"
    }
}

private struct ProFeature: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}
