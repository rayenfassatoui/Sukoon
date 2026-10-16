import SwiftUI
import SukoonCore

struct CelebrationView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    let navigation: AppNavigation
    let onDismiss: () -> Void

    init(store: AppStore, navigation: AppNavigation, onDismiss: @escaping () -> Void) {
        self.store = store
        self.navigation = navigation
        self.onDismiss = onDismiss
    }

    private var acceptanceVerse: Verse? {
        store.library.surah(2)?.verses.first(where: { $0.id == 127 })
    }

    private var acceptanceReference: String {
        let reference = l10n.reference(VerseReference(surahID: 2, verseID: 127))
        let surahName = store.library.surah(2).map(l10n.surahName) ?? ""
        return l10n.format(
            "Quran %@ · %@",
            reference,
            surahName,
            table: "Preferences"
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(palette.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("خَتْمُ الْقُرْآن")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                    Text(l10n.text("You completed the Quran", table: "Preferences"))
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Label(l10n.text("Close"), systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()
            ScrollView {
                khatmCelebration
                    .padding(16)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
            }
            Divider()
            celebrationActions
                .padding(16)
        }
        .frame(minWidth: 440, idealWidth: 480, maxWidth: 640, minHeight: 260, idealHeight: 320, maxHeight: 560)
        .background(palette.canvas)
        .presentationSizing(.fitted)
    }

    private var khatmCelebration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                l10n.text(
                    "Every verse in your journey is marked. Take a quiet moment for gratitude, and ask Allah to accept what you have offered.",
                    table: "Preferences"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let acceptanceVerse {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        l10n.text("A Quranic prayer of acceptance", table: "Preferences"),
                        systemImage: "hands.sparkles"
                    )
                    .font(.headline)
                    ArabicText(
                        acceptanceVerse.text,
                        size: store.settings.arabicFontSize
                    )
                    .textSelection(.enabled)
                    if !l10n.isArabic {
                        Text(
                            l10n.text(
                                "“Our Lord, accept this from us. You are indeed the All-Hearing, All-Knowing.”",
                                table: "Preferences"
                            )
                        )
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(acceptanceReference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .sukoonCard(padding: 14)
            }
        }
    }

    private var celebrationActions: some View {
        HStack(spacing: 12) {
            Button {
                navigation.readerSurahID = 1
                navigation.readerReference = nil
                navigation.section = .quran
                onDismiss()
            } label: {
                Label(
                    l10n.text("Open Quran", table: "Preferences"),
                    systemImage: "book.closed"
                )
            }
            .buttonStyle(.bordered)
            .help(l10n.text("Open the Quran reader", table: "Preferences"))

            Spacer(minLength: 0)

            Button {
                navigation.section = .journey
                onDismiss()
            } label: {
                Label(
                    l10n.text("View completed journey", table: "Preferences"),
                    systemImage: "checkmark.seal"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.controlAccent)
            .keyboardShortcut(.defaultAction)
            .help(l10n.text("Open your completed reading journey", table: "Preferences"))
        }
    }
}
