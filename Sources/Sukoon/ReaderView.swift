import SwiftUI
import SukoonCore

struct ReaderView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var searchText = ""
    @State private var pendingScrollReference: VerseReference?
    @State private var scrollRequestID = 0
    @State private var searchResults: QuranSearchResults?
    @FocusState private var searchFocused: Bool

    private var isBrowsing: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func open(_ reference: VerseReference) {
        navigation.readerSurahID = reference.surahID
        pendingScrollReference = reference
        scrollRequestID += 1
    }

    private func consumeExternalReference(_ reference: VerseReference?) {
        guard let reference else { return }
        open(reference)
        navigation.readerReference = nil
    }

    private func selectFirstSearchResult() {
        // Direct references and text matches select the exact ayah; names select a chapter.
        if let first = searchResults?.surahIDs.first {
            pendingScrollReference = nil
            navigation.readerSurahID = first
        } else if let first = searchResults?.verses.first {
            open(first)
        }
    }

    private var selectedSurah: Surah? {
        store.library.surah(navigation.readerSurahID) ?? store.library.surahs.first
    }

    @ViewBuilder
    private var readerContent: some View {
        if let selectedSurah {
            SurahReader(
                surah: selectedSurah,
                store: store,
                pendingScrollReference: $pendingScrollReference,
                requestID: scrollRequestID
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

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 720
            HStack(spacing: 0) {
                if !compact {
                    surahIndex
                        .frame(width: 286)
                        .background(.thinMaterial)
                    Divider().opacity(0.5)
                }
                VStack(spacing: 0) {
                    if compact {
                        compactReaderNavigation
                        Divider().opacity(0.5)
                    }
                    readerContent
                }
            }
        }
        .background(colorScheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : palette.canvas)
        .onAppear {
            if store.library.surah(navigation.readerSurahID) == nil,
               let first = store.library.surahs.first {
                navigation.readerSurahID = first.id
            }
            searchResults = store.library.search(searchText)
            consumeExternalReference(navigation.readerReference)
        }
        .onChange(of: searchText) { _, query in
            searchResults = store.library.search(query)
        }
        .onChange(of: navigation.readerReference) { _, reference in
            consumeExternalReference(reference)
        }
    }
    private var compactReaderNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        l10n.format(
                            "Search surahs, ayahs, or %@",
                            l10n.reference(VerseReference(surahID: 2, verseID: 255)),
                            table: "Workspace"
                        ),
                        text: $searchText
                    )
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { selectFirstSearchResult() }
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
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Button {
                    navigation.section = .favourites
                } label: {
                    Image(systemName: "heart")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .help(l10n.text("Open Favourites", table: "Workspace"))
                .accessibilityLabel(l10n.text("Open Favourites", table: "Workspace"))
            }

            Menu {
                compactSurahMenuContent
            } label: {
                Label(
                    selectedSurah.map(l10n.surahName) ?? l10n.text("Choose a surah", table: "Workspace"),
                    systemImage: "book.closed"
                )
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(l10n.text("Choose a surah", table: "Workspace"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var compactSurahMenuContent: some View {
        if isBrowsing {
            ForEach(store.library.surahs) { surah in
                Button {
                    pendingScrollReference = nil
                    navigation.readerSurahID = surah.id
                } label: {
                    Text(l10n.surahName(surah))
                }
            }
        } else if let searchResults {
            ForEach(searchResults.surahIDs, id: \.self) { id in
                if let surah = store.library.surah(id) {
                    Button {
                        pendingScrollReference = nil
                        navigation.readerSurahID = surah.id
                    } label: {
                        Text(l10n.surahName(surah))
                    }
                }
            }
            ForEach(searchResults.verses, id: \.self) { reference in
                if let surah = store.library.surah(reference.surahID),
                   surah.verses.contains(where: { $0.id == reference.verseID }) {
                    Button {
                        open(reference)
                    } label: {
                        Text("\(l10n.surahName(surah)) · \(l10n.reference(reference))")
                    }
                }
            }
            if searchResults.isEmpty {
                Text(l10n.text("No matches", table: "Workspace"))
            }
        }
    }

    private var surahIndex: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(l10n.text("The Quran", table: "Workspace"))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        l10n.format(
                            "Search surahs, ayahs, or %@",
                            l10n.reference(VerseReference(surahID: 2, verseID: 255)),
                            table: "Workspace"
                        ),
                        text: $searchText
                    )
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit { selectFirstSearchResult() }
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
                        open(automatic)
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

                Button {
                    navigation.section = .favourites
                } label: {
                    Label(
                        l10n.format(
                            "Favourites %@",
                            l10n.number(store.bookmarks.count),
                            table: "Workspace"
                        ),
                        systemImage: "heart"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.accent)
                .disabled(store.bookmarks.isEmpty)
            }
            .padding(.horizontal, 17)
            .padding(.top, 38)
            .padding(.bottom, 14)

            Divider().opacity(0.55)

            if !isBrowsing, searchResults?.isEmpty != false {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if isBrowsing {
                            ForEach(store.library.surahs) { surah in
                                chapterRow(surah)
                            }
                        } else if let searchResults {
                            ForEach(searchResults.surahIDs, id: \.self) { id in
                                if let surah = store.library.surah(id) {
                                    chapterRow(surah)
                                }
                            }
                            ForEach(searchResults.verses, id: \.self) { reference in
                                if let surah = store.library.surah(reference.surahID),
                                   let verse = surah.verses.first(where: { $0.id == reference.verseID }) {
                                    AyahSearchRow(
                                        surah: surah,
                                        verse: verse,
                                        isBookmarked: store.isBookmarked(
                                            surahID: reference.surahID,
                                            verseID: reference.verseID
                                        ),
                                        action: { open(reference) },
                                        toggleBookmark: {
                                            store.toggleBookmark(
                                                surahID: reference.surahID,
                                                verseID: reference.verseID
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func chapterRow(_ surah: Surah) -> some View {
        SurahIndexRow(
            surah: surah,
            selected: surah.id == navigation.readerSurahID,
            readCount: store.readCount(in: surah.id),
            action: {
                pendingScrollReference = nil
                navigation.readerSurahID = surah.id
            }
        )
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
                    Text(l10n.quranNumber(surah.id))
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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

private struct AyahSearchRow: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let verse: Verse
    let isBookmarked: Bool
    let action: () -> Void
    let toggleBookmark: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(l10n.surahName(surah))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(l10n.reference(VerseReference(surahID: surah.id, verseID: verse.id)))
                            .font(.caption.monospacedDigit())
                    }
                    ArabicText(verse.text, size: 21)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(l10n.text("Open matching ayah", table: "Workspace"))

            Button(action: toggleBookmark) {
                Image(systemName: isBookmarked ? "heart.fill" : "heart")
                    .foregroundStyle(isBookmarked ? palette.gold : palette.accent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                l10n.format(
                    isBookmarked ? "Remove %@ from Favourites" : "Add %@ to Favourites",
                    l10n.reference(VerseReference(surahID: surah.id, verseID: verse.id)),
                    table: "Workspace"
                )
            )
        }
        .padding(10)
        .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SurahReader: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let store: AppStore
    @Binding var pendingScrollReference: VerseReference?
    let requestID: Int
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    header(proxy: proxy)
                        .padding(.bottom, 20)

                    if surah.id != 1 && surah.id != 9, let basmala = store.library.surah(1)?.verses.first {
                        ArabicText(basmala.text, size: min(store.settings.arabicFontSize, 34))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                    }

                    ForEach(surah.verses) { verse in
                        VerseRow(
                            surah: surah,
                            verse: verse,
                            fontSize: store.settings.arabicFontSize,
                            isRead: store.isRead(surahID: surah.id, verseID: verse.id),
                            isBookmarked: store.isBookmarked(surahID: surah.id, verseID: verse.id),
                            onMarkRead: { store.markRead(surahID: surah.id, verseID: verse.id) },
                            onBookmark: { store.toggleBookmark(surahID: surah.id, verseID: verse.id) }
                        )
                        .id(verse.id)
                    }
                }
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 48)
            }
            .task(id: requestID) {
                guard let reference = pendingScrollReference,
                      reference.surahID == surah.id,
                      surah.verses.contains(where: { $0.id == reference.verseID }) else { return }
                // Wait for the newly selected chapter's scroll content to enter the hierarchy.
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(reference.verseID, anchor: .top)
                }
                pendingScrollReference = nil
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                l10n.format(
                    "SURAH %@",
                    l10n.quranNumber(surah.id),
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
    }

    private var alternateSurahName: some View {
        Text(l10n.isArabic ? surah.transliteration : surah.name)
            .font(l10n.isArabic ? .title3 : .custom("Geeza Pro", size: 38).weight(.bold))
            .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
            .foregroundStyle(palette.accent)
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    titleBlock
                    Spacer(minLength: 12)
                    alternateSurahName
                }
                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    alternateSurahName
                }
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

            VStack(alignment: .leading, spacing: 10) {
                if nextUnreadID != nil {
                    if isChosenSurahPlan {
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


            VStack(alignment: .leading, spacing: 10) {
                let bookmarks = store.bookmarks.filter { $0.surahID == surah.id }
                if !bookmarks.isEmpty {
                    Menu {
                        ForEach(bookmarks, id: \.self) { bookmark in
                            Button(l10n.reference(bookmark)) {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(bookmark.verseID, anchor: .top)
                                }
                            }
                        }
                    } label: {
                        Label(l10n.text("Favourites", table: "Workspace"), systemImage: "heart.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

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
        .padding(.horizontal, 20)
        .padding(.top, 24)
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
                    Text(l10n.quranNumber(verse.id))
                        .font(.custom("Geeza Pro", size: 16).weight(.bold))
                        .foregroundStyle(isRead ? .white : palette.accent)
                        .frame(width: 38, height: 38)
                        .background(isRead ? palette.success : palette.accentSoft.opacity(0.28), in: Circle())

                    if isBookmarked {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(palette.gold)
                            .accessibilityHidden(true)
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
                Button(action: onBookmark) {
                    Image(systemName: isBookmarked ? "heart.fill" : "heart")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isBookmarked ? palette.gold : palette.accent)
                .accessibilityLabel(
                    l10n.format(
                        isBookmarked ? "Remove %@ from Favourites" : "Add %@ to Favourites",
                        l10n.reference(VerseReference(surahID: surah.id, verseID: verse.id)),
                        table: "Workspace"
                    )
                )
                .help(l10n.format(
                    isBookmarked ? "Remove %@ from Favourites" : "Add %@ to Favourites",
                    l10n.reference(VerseReference(surahID: surah.id, verseID: verse.id)),
                    table: "Workspace"
                ))

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
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(isRead ? palette.success.opacity(0.035) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, 20)
        }
    }
}
