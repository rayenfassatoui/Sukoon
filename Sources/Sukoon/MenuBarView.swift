import SwiftUI
import SukoonCore

struct MenuBarView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable var store: AppStore
    let reminderClock: ReminderClock
    let services: AppServices
    let onOpen: (AppSection) -> Void
    let onPreview: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let content = store.lastReminder ?? store.previewReminder()
        let automaticComplete = store.settings.mode == .automatic && store.isAutomaticComplete
        let suspension = ReminderSuspensionStatus(store: store, now: reminderClock.now)
        VStack(spacing: 12) {
            HStack {
                Text(l10n.text("Sukoon"))
                    .font(.headline)
                Spacer()
                Button { onOpen(.settings) } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(l10n.text("Settings"))
                .accessibilityLabel(l10n.text("Settings"))
            }
            if let content {
                ScrollView {
                    ArabicText(content.arabic, size: store.settings.arabicFontSize)
                        .textSelection(.enabled)
                        .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.center, for: .alignment)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
                .id(content.id)
            } else {
                Button { onOpen(automaticComplete ? .journey : .quran) } label: {
                    Text(l10n.text(automaticComplete ? "Automatic Quran complete" : "Choose a surah"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 18)
                .accessibilityLabel(l10n.text(automaticComplete ? "Automatic Quran complete" : "Choose a surah"))
            }

            if let suspension {
                VStack(alignment: .leading, spacing: 3) {
                    Label(suspension.title(l10n: l10n), systemImage: suspension.isSnoozed ? "moon.zzz" : "moon")
                        .font(.caption.weight(.medium))
                    Text(suspension.detail(l10n: l10n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reminders.suspension")
            } else if !store.settings.remindersEnabled {
                Label(l10n.text("Reminders are paused", table: "Workspace"), systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if services.showsUpdateNotice {
                Button { onOpen(.settings) } label: {
                    Label(l10n.text("App update", table: "Preferences"), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .help(l10n.text("Open update details", table: "Preferences"))
                .accessibilityIdentifier("updates.openDetails")
            }

            Divider().overlay(palette.hairline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    if let content {
                        PassageReference(library: store.library, content: content)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer(minLength: 4)
                    actionButtons(content: content)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let content {
                        PassageReference(library: store.library, content: content)
                    }
                    actionButtons(content: content)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(width: 336)
        .padding(16)
        .background(palette.canvas)
    }

    @ViewBuilder
    private func actionButtons(content: ReminderContent?) -> some View {
        HStack(spacing: 10) {
            if let reference = content?.reference {
                Button {
                    store.toggleBookmark(surahID: reference.surahID, verseID: reference.verseID)
                } label: {
                    Image(systemName: store.isBookmarked(
                        surahID: reference.surahID,
                        verseID: reference.verseID
                    ) ? "heart.fill" : "heart")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.accent)
                .accessibilityAddTraits(
                    store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID) ? .isSelected : []
                )
                .help(
                    l10n.format(
                        store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID)
                            ? "Remove %@ from Favourites"
                            : "Add %@ to Favourites",
                        l10n.reference(reference),
                        table: "Workspace"
                    )
                )
                .accessibilityLabel(
                    l10n.format(
                        store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID)
                            ? "Remove %@ from Favourites"
                            : "Add %@ to Favourites",
                        l10n.reference(reference),
                        table: "Workspace"
                    )
                )
                .accessibilityIdentifier("reminders.favourite")
            }

            Button { onOpen(.quran) } label: {
                Label(l10n.text("Open Quran", table: "Preferences"), systemImage: "book.closed")
            }
            .buttonStyle(.borderless)
            .help(l10n.text("Open the Quran"))
            .accessibilityLabel(l10n.text("Open the Quran"))
            .accessibilityIdentifier("workspace.open")

            Menu {
                Button {
                    store.settings.remindersEnabled.toggle()
                } label: {
                    Label(
                        l10n.text(store.settings.remindersEnabled ? "Pause reminders" : "Resume reminders"),
                        systemImage: store.settings.remindersEnabled ? "pause" : "play"
                    )
                }
                Menu(l10n.text("Snooze reminders"), systemImage: "moon.zzz") {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button(l10n.format("For %@ minutes", l10n.number(minutes))) {
                            store.snooze(for: minutes * 60)
                        }
                        .accessibilityIdentifier("reminders.snooze.\(minutes)")
                    }
                }
                if let until = store.snoozedUntil, until > reminderClock.now {
                    Button(l10n.text("Cancel snooze"), systemImage: "play.circle") {
                        store.cancelSnooze()
                    }
                    .accessibilityIdentifier("reminders.cancelSnooze")
                }
                Button(l10n.text("Preview reminder"), systemImage: "bell", action: onPreview)
                    .disabled(store.previewReminder() == nil)
                Divider()
                Button(l10n.text("Settings"), systemImage: "slider.horizontal.3") { onOpen(.settings) }
                Button(l10n.text("Reading progress"), systemImage: "checkmark.circle") { onOpen(.journey) }
                Button(l10n.text("Favourites", table: "Workspace"), systemImage: "heart") { onOpen(.favourites) }
                Divider()
                Button(l10n.text("Quit Sukoon"), action: onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(l10n.text("Sukoon actions"))
            .accessibilityLabel(l10n.text("Sukoon actions"))
            .accessibilityIdentifier("sukoon.actions")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

@MainActor
struct ReminderSuspensionStatus {
    let resumeDate: Date
    let isSnoozed: Bool

    init?(store: AppStore, now: Date) {
        guard store.canScheduleReminder,
              let resumeDate = store.reminderSuspensionEnd(at: now), resumeDate > now else { return nil }
        self.resumeDate = resumeDate
        isSnoozed = store.snoozedUntil.map { $0 > now } ?? false
    }

    func title(l10n: AppLocalization) -> String {
        l10n.text(isSnoozed ? "Reminders are snoozed" : "Quiet hours are active")
    }

    func detail(l10n: AppLocalization) -> String {
        let date = resumeDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(l10n.locale))
        return l10n.format("Reminders resume %@.", date)
    }
}
