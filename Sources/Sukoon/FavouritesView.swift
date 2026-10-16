import SwiftUI
import SukoonCore

struct FavouritesView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    @Bindable var navigation: AppNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    SukoonSectionTitle(
                        l10n.text("Favourites", table: "Workspace"),
                        detail: l10n.text(
                            "Saved ayahs stay here for quick exact jumps back into the Quran.",
                            table: "Workspace"
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !store.bookmarks.isEmpty {
                        openQuranButton
                    }
                }

                if store.bookmarks.isEmpty {
                    ContentUnavailableView {
                        Label(l10n.text("No favourites yet", table: "Workspace"), systemImage: "heart")
                    } description: {
                        Text(l10n.text("Save an ayah from the reader to keep it here.", table: "Workspace"))
                    } actions: {
                        openQuranButton
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .sukoonCard(padding: 16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.bookmarks, id: \.self) { reference in
                            VStack(spacing: 0) {
                                favouriteRow(reference)
                                if reference != store.bookmarks.last {
                                    Rectangle()
                                        .fill(palette.hairline)
                                        .frame(height: 1)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .sukoonCard(padding: 0)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvas)
    }

    private var openQuranButton: some View {
        Button {
            navigation.section = .quran
        } label: {
            Label(l10n.text("Open Quran", table: "Workspace"), systemImage: "book.closed")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func favouriteRow(_ reference: VerseReference) -> some View {
        if let surah = store.library.surah(reference.surahID),
           let verse = surah.verses.first(where: { $0.id == reference.verseID }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        open(reference)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l10n.surahName(surah))
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                Text(l10n.reference(reference))
                                    .font(.caption.monospacedDigit())
                                Image(systemName: "arrow.up.forward")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(l10n.format("Open %@ in the Quran", l10n.reference(reference), table: "Workspace"))
                    .help(l10n.format("Open %@ in the Quran", l10n.reference(reference), table: "Workspace"))

                    removeButton(reference)
                }

                ArabicText(verse.text, size: store.settings.arabicFontSize)
                    .padding(.vertical, store.settings.arabicFontSize * 0.16)
                    .textSelection(.enabled)
            }
            .padding(20)
        } else {
            HStack(spacing: 12) {
                Text(l10n.reference(reference))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                removeButton(reference)
            }
            .padding(20)
        }
    }

    private func removeButton(_ reference: VerseReference) -> some View {
        let title = l10n.format("Remove %@ from Favourites", l10n.reference(reference), table: "Workspace")
        return Button {
            store.removeBookmark(reference)
        } label: {
            Label(title, systemImage: "heart.fill")
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.accent)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isSelected)
        .help(title)
    }

    private func open(_ reference: VerseReference) {
        navigation.readerSurahID = reference.surahID
        navigation.readerReference = reference
        navigation.section = .quran
    }
}
