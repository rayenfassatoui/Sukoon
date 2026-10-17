import SwiftUI
import SukoonCore

struct UpdateNoticeView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let services: AppServices

    private var title: String {
        switch services.updateState {
        case let .updateAvailable(version, _):
            l10n.format("Sukoon %@ is available.", version, table: "Preferences")
        case .checking:
            l10n.text("Preparing the update…", table: "Preferences")
        case .downloading:
            l10n.text("Downloading the update…", table: "Preferences")
        case .extracting:
            l10n.text("Preparing installation…", table: "Preferences")
        case .installing:
            l10n.text("Installing and restarting…", table: "Preferences")
        case .waitingForRelaunch:
            l10n.text("Restart Sukoon to finish the update", table: "Preferences")
        case let .installed(version):
            l10n.format("Sukoon %@ was installed.", version, table: "Preferences")
        case .failed:
            l10n.text("Update needs attention", table: "Preferences")
        case .idle, .upToDate:
            l10n.text("Updates", table: "Preferences")
        }
    }

    private var detail: String {
        if case let .failed(failure) = services.updateState {
            return failure.localizedMessage(l10n)
        }
        return l10n.text(
            "Sukoon will restart after installation. Your reading progress and preferences are kept.",
            table: "Preferences"
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                message
                actions.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                message
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if case .waitingForRelaunch = services.updateState {
                Button(l10n.text("Restart Sukoon", table: "Preferences")) { services.retryUpdateRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.controlAccent)
                    .accessibilityIdentifier("updates.restart")
            } else if services.isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(title)
                if services.canCancelUpdate {
                    Button(l10n.text("Cancel", table: "Preferences")) { services.cancelUpdate() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("updates.cancel")
                }
            } else {
                if case .updateAvailable = services.updateState {
                    Button(l10n.text("Download & Install", table: "Preferences")) {
                        services.downloadAndInstallUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.controlAccent)
                    .help(l10n.text("Download the update and restart Sukoon", table: "Preferences"))
                    .accessibilityIdentifier("updates.install")
                }
                if case .installed = services.updateState {
                    EmptyView()
                } else {
                    Button(l10n.text("Open GitHub release", table: "Preferences")) { services.openRelease() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("updates.release")
                }
                Button {
                    services.dismissUpdateNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help(l10n.text("Dismiss update notice", table: "Preferences"))
                .accessibilityLabel(l10n.text("Dismiss update notice", table: "Preferences"))
                .accessibilityIdentifier("updates.dismiss")
            }
        }
    }
}
