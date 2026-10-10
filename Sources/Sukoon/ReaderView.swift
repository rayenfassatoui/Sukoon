import SwiftUI
import SukoonCore

struct ReaderView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var searchText = ""
    @State private var pendingScrollVerse: Int?
    @FocusState private var searchFocused: Bool

    private var matchingSurahs: [Surah] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return store.library.surahs }
        var normalizedNumber = ""
        for character in term {
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else {
                normalizedNumber = ""
                break
            }
            normalizedNumber.unicodeScalars.append(UnicodeScalar(48 + digit)!)
        }
        let searchedNumber = Int(normalizedNumber)
        return store.library.surahs.filter { surah in
            surah.id == searchedNumber
                || surah.transliteration.localizedCaseInsensitiveContains(term)
                || surah.name.localizedCaseInsensitiveContains(term)
        }
    }

    private var selectedSurah: Surah? {
        store.library.surah(navigation.readerSurahID) ?? store.library.surahs.first
    }

    var body: some View {
        HStack(spacing: 0) {
            surahIndex
                .frame(width: 286)
                .background(.thinMaterial)

            Divider().opacity(0.5)

            if let selectedSurah {
                SurahReader(
                    surah: selectedSurah,
                    store: store,
                    pendingScrollVerse: $pendingScrollVerse
                )
                .id(selectedSurah.id)
            } else {
                ContentUnavailableView(
                    l10n.text("Quran unavailable", table: "Workspace"),
                    systemImage: "book.closed"
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colorScheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : palette.canvas)
        .onAppear {
            if store.library.surah(navigation.readerSurahID) == nil,
               let first = store.library.surahs.first {
                navigation.readerSurahID = first.id
            }
        }
    }

    private var surahIndex: some View {
        let matches = matchingSurahs
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(l10n.text("The Quran", table: "Workspace"))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        l10n.format(
                            "Search %@ surahs",
                            l10n.number(store.library.surahs.count),
                            table: "Workspace"
                        ),
                        text: $searchText
                    )
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit {
                            if let first = matches.first {
                                navigation.readerSurahID = first.id
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l10n.text("Clear search", table: "Workspace"))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                if let automatic = store.automaticNextReference,
                   let automaticSurah = store.library.surah(automatic.surahID) {
                    Button {
                        store.startAutomaticReading()
                        navigation.readerSurahID = automatic.surahID
                        pendingScrollVerse = automatic.verseID
                    } label: {
                        Label(
                            l10n.format(
                                "Automatic: %@ · %@",
                                l10n.surahName(automaticSurah),
                                l10n.reference(automatic),
                                table: "Workspace"
                            ),
                            systemImage: "books.vertical.fill"
                        )
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.accent)
                    .help(l10n.text("Resume the saved automatic Quran position", table: "Workspace"))
                } else if store.isAutomaticComplete {
                    Label(
                        l10n.text("Automatic Quran complete"),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.success)
                }

                if let bookmark = store.bookmark,
                   let bookmarkedSurah = store.library.surah(bookmark.surahID) {
                    Button {
                        navigation.readerSurahID = bookmark.surahID
                        pendingScrollVerse = bookmark.verseID
                    } label: {
                        Label(
                            l10n.format(
                                "Resume %@ · %@",
                                l10n.surahName(bookmarkedSurah),
                                l10n.number(bookmark.verseID),
                                table: "Workspace"
                            ),
                            systemImage: "bookmark.fill"
                        )
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.accent)
                    .help(l10n.text("Open your bookmarked verse", table: "Workspace"))
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 38)
            .padding(.bottom, 14)

            Divider().opacity(0.55)

            if matches.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matches) { surah in
                            SurahIndexRow(
                                surah: surah,
                                selected: surah.id == navigation.readerSurahID,
                                readCount: store.readCount(in: surah.id),
                                action: { navigation.readerSurahID = surah.id }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}

private struct SurahIndexRow: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let selected: Bool
    let readCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? palette.accent.opacity(0.16) : palette.raisedSurface)
                    Text(l10n.number(surah.id))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.surahName(surah))
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Text(
                        l10n.format(
                            "%@ verses",
                            l10n.number(surah.totalVerses),
                            table: "Workspace"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 5)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(l10n.isArabic ? surah.transliteration : surah.name)
                        .font(l10n.isArabic ? .caption : .custom("Geeza Pro", size: 16))
                        .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
                    if readCount == surah.totalVerses {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(palette.success)
                    } else if readCount > 0 {
                        Text("\u{2066}\(l10n.number(readCount))/\(l10n.number(surah.totalVerses))\u{2069}")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.accentSoft.opacity(0.25))
            }
        }
        .accessibilityLabel(
            l10n.format(
                "Surah %@, %@ verses",
                l10n.surahName(surah),
                l10n.number(surah.totalVerses),
                table: "Workspace"
            )
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SurahReader: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let store: AppStore
    @Binding var pendingScrollVerse: Int?


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    header(proxy: proxy)
                        .padding(.bottom, 20)

                    if surah.id != 1 && surah.id != 9, let basmala = store.library.surah(1)?.verses.first {
                        ArabicText(basmala.text, size: min(store.settings.arabicFontSize, 34))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 38)
                            .padding(.vertical, 26)
                    }

                    ForEach(surah.verses) { verse in
                        VerseRow(
                            surah: surah,
                            verse: verse,
                            fontSize: store.settings.arabicFontSize,
                            isRead: store.isRead(surahID: surah.id, verseID: verse.id),
                            isBookmarked: store.bookmark == VerseReference(surahID: surah.id, verseID: verse.id),
                            onMarkRead: { store.markRead(surahID: surah.id, verseID: verse.id) },
                            onBookmark: { store.setBookmark(surahID: surah.id, verseID: verse.id) }
                        )
                        .id(verse.id)
                    }
                }
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 48)
            }
            .onChange(of: pendingScrollVerse, initial: true) { _, verseID in
                guard let verseID, surah.verses.contains(where: { $0.id == verseID }) else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(verseID, anchor: .top)
                }
                pendingScrollVerse = nil
            }
        }
    }

    @ViewBuilder
    private func header(proxy: ScrollViewProxy) -> some View {
        let readCount = store.readCount(in: surah.id)
        let isChosenSurahPlan = store.selectedSurahID == surah.id
            && store.settings.mode == .surah
            && store.settings.remindersEnabled
        let automaticReference = store.automaticNextReference
        let isAutomaticPosition = automaticReference?.surahID == surah.id
        let nextUnreadID = store.nextUnreadVerse(in: surah.id)?.id
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        l10n.format(
                            "SURAH %@",
                            l10n.number(surah.id),
                            table: "Workspace"
                        )
                    )
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(l10n.surahName(surah))
                        .font(.system(size: 33, weight: .semibold, design: .rounded))
                    Text(
                        l10n.format(
                            "%@ · %@ verses",
                            l10n.revelationType(surah.type),
                            l10n.number(surah.totalVerses),
                            table: "Workspace"
                        )
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(l10n.isArabic ? surah.transliteration : surah.name)
                    .font(l10n.isArabic ? .title3 : .custom("Geeza Pro", size: 38).weight(.bold))
                    .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
                    .foregroundStyle(palette.accent)
            }

            if isAutomaticPosition, let automaticReference {
                Button {
                    store.startAutomaticReading()
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(automaticReference.verseID, anchor: .top)
                    }
                } label: {
                    Label(
                        l10n.format(
                            "Automatic next: %@",
                            l10n.reference(automaticReference),
                            table: "Workspace"
                        ),
                        systemImage: "books.vertical.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 12) {
                if nextUnreadID == nil {
                    Label(l10n.text("Surah complete", table: "Workspace"), systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.success)
                } else if isChosenSurahPlan {
                    Label(l10n.text("Chosen-surah reminder plan", table: "Workspace"), systemImage: "bell.badge.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.accent)
                } else {
                    Button {
                        store.startSurah(surah.id)
                    } label: {
                        Label(l10n.text("Use for chosen-surah reminders", table: "Workspace"), systemImage: "bell.badge")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let nextUnreadID {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(nextUnreadID, anchor: .top)
                        }
                    } label: {
                        Label(l10n.text("Next unread", table: "Workspace"), systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                }
            }


            HStack(spacing: 12) {
                if let bookmark = store.bookmark, bookmark.surahID == surah.id {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(bookmark.verseID, anchor: .top)
                        }
                    } label: {
                        Label(
                            l10n.format(
                                "Bookmark %@",
                                l10n.number(bookmark.verseID),
                                table: "Workspace"
                            ),
                            systemImage: "bookmark.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Text(
                    l10n.format(
                        "%@ of %@ marked",
                        l10n.number(readCount),
                        l10n.number(surah.totalVerses),
                        table: "Workspace"
                    )
                )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            SukoonProgress(value: surah.totalVerses == 0 ? 0 : Double(readCount) / Double(surah.totalVerses))
        }
        .padding(.horizontal, 38)
        .padding(.top, 38)
    }
}

private struct VerseRow: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let verse: Verse
    let fontSize: Double
    let isRead: Bool
    let isBookmarked: Bool
    let onMarkRead: () -> Void
    let onBookmark: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 9) {
                    Text(l10n.number(verse.id))
                        .font(.custom("Geeza Pro", size: 16).weight(.bold))
                        .foregroundStyle(isRead ? .white : palette.accent)
                        .frame(width: 38, height: 38)
                        .background(isRead ? palette.success : palette.accentSoft.opacity(0.28), in: Circle())

                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(palette.gold)
                            .accessibilityLabel(l10n.text("Bookmarked", table: "Workspace"))
                    }
                }

                ArabicText(verse.text, size: fontSize)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Text(l10n.reference(VerseReference(surahID: surah.id, verseID: verse.id)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if isBookmarked {
                    Label(l10n.text("Bookmark", table: "Workspace"), systemImage: "bookmark.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.gold)
                } else {
                    Button(action: onBookmark) {
                        Label(l10n.text("Bookmark", table: "Workspace"), systemImage: "bookmark")
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.text("Save this verse as your reading position", table: "Workspace"))
                }

                if isRead {
                    Label(l10n.text("Marked", table: "Workspace"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.success)
                        .accessibilityLabel(l10n.text("Verse marked as read", table: "Workspace"))
                } else {
                    Button(action: onMarkRead) {
                        Label(l10n.text("Mark read", table: "Workspace"), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .help(l10n.text("Confirm this verse in your Quran progress", table: "Workspace"))
                }
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 28)
        .background(isRead ? palette.success.opacity(0.035) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, 38)
        }
    }
}
