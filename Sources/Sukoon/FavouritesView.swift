import SwiftUI
import SukoonCore

struct FavouritesView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    @Bindable var navigation: AppNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SukoonSectionTitle(
                    l10n.text("Favourites", table: "Workspace"),
                    eyebrow: l10n.text("Quran"),
                    detail: l10n.text(
                        "Saved ayahs stay here for quick exact jumps back into the Quran.",
                        table: "Workspace"
                    )
                )

                if store.bookmarks.isEmpty {
                    ContentUnavailableView {
                        Label(
                            l10n.text("No favourites yet", table: "Workspace"),
                            systemImage: "heart"
                        )
                    } description: {
                        Text(
                            l10n.text(
                                "Save an ayah from the reader to keep it here.",
                                table: "Workspace"
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .sukoonCard(padding: 16)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.bookmarks, id: \.self) { reference in
                            favouriteRow(reference)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(colorScheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : palette.canvas)
    }

    @ViewBuilder
    private func favouriteRow(_ reference: VerseReference) -> some View {
        if let surah = store.library.surah(reference.surahID),
           let verse = surah.verses.first(where: { $0.id == reference.verseID }) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    open(reference)
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(l10n.surahName(surah))
                                .font(.headline)
                                .lineLimit(1)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(l10n.reference(reference))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ArabicText(verse.text, size: min(store.settings.arabicFontSize, 34))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    l10n.format(
                        "Open %@ in the Quran",
                        l10n.reference(reference),
                        table: "Workspace"
                    )
                )

                removeButton(reference)
            }
            .sukoonCard(padding: 16)
        } else {
            HStack(spacing: 10) {
                Text(l10n.reference(reference))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                removeButton(reference)
            }
            .sukoonCard(padding: 16)
        }
    }

    private func removeButton(_ reference: VerseReference) -> some View {
        Button {
            store.removeBookmark(reference)
        } label: {
            Image(systemName: "heart.fill")
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.gold)
        .accessibilityLabel(
            l10n.format(
                "Remove %@ from Favourites",
                l10n.reference(reference),
                table: "Workspace"
            )
        )
        .help(
            l10n.format(
                "Remove %@ from Favourites",
                l10n.reference(reference),
                table: "Workspace"
            )
        )
    }

    private func open(_ reference: VerseReference) {
        navigation.readerSurahID = reference.surahID
        navigation.readerReference = reference
        navigation.section = .quran
    }
}
