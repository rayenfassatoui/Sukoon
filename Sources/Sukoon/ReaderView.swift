import SwiftUI
import SukoonCore

struct ReaderView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var searchText = ""
    @State private var searchResults: QuranSearchResults?
    @State private var showsSearchResults = false
    @State private var pendingScrollReference: VerseReference?
    @State private var highlightedReference: VerseReference?
    @State private var scrollRequestID = 0
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedSurah: Surah? {
        store.library.surah(navigation.readerSurahID) ?? store.library.surahs.first
    }

    var body: some View {
        GeometryReader { geometry in
            let showsIndex = geometry.size.width >= 850
            VStack(spacing: 0) {
                navigationBar(showsIndex: showsIndex)
                Divider()
                if hasQuery && showsSearchResults {
                    searchResultsPanel
                        .frame(maxHeight: min(250, geometry.size.height * 0.4))
                    Divider()
                }
                // Only the navigation chrome changes at the breakpoint, never the reader.
                HStack(spacing: 0) {
                    if showsIndex {
                        surahIndex
                            .frame(width: 190)
                        Divider()
                    }
                    readerContent
                }
            }
        }
        .background(palette.canvas)
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
            showsSearchResults = hasQuery
        }
        .onChange(of: searchFocused) { _, focused in
            if focused && hasQuery {
                showsSearchResults = true
            }
        }
        .onChange(of: navigation.readerReference) { _, reference in
            consumeExternalReference(reference)
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let selectedSurah {
            SurahReader(
                surah: selectedSurah,
                store: store,
                pendingScrollReference: $pendingScrollReference,
                highlightedReference: highlightedReference,
                requestID: scrollRequestID,
                open: open
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

    private func navigationBar(showsIndex: Bool) -> some View {
        HStack(spacing: 8) {
            if !showsIndex {
                Menu {
                    ForEach(store.library.surahs) { surah in
                        Button(l10n.surahName(surah)) {
                            selectSurah(surah.id)
                        }
                    }
                } label: {
                    Label(l10n.text("Surahs", table: "Workspace"), systemImage: "book.closed")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(l10n.text("Choose a surah", table: "Workspace"))
                .accessibilityLabel(l10n.text("Choose a surah", table: "Workspace"))
                .accessibilityValue(selectedSurah.map(l10n.surahName) ?? "")
            }

            Button {
                searchFocused = true
                showsSearchResults = hasQuery
            } label: {
                Label(l10n.text("Find in Quran", table: "Workspace"), systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: .command)
            .help(l10n.text("Find in Quran", table: "Workspace"))

            TextField(
                l10n.format(
                    "Search surahs, ayahs, or %@",
                    l10n.reference(VerseReference(surahID: 2, verseID: 255)),
                    table: "Workspace"
                ),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit { selectFirstSearchResult() }
            .onExitCommand {
                if !searchText.isEmpty {
                    clearSearch()
                } else {
                    searchFocused = false
                }
            }
            .accessibilityLabel(l10n.text("Find in Quran", table: "Workspace"))

            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Label(l10n.text("Clear search", table: "Workspace"), systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(l10n.text("Clear search", table: "Workspace"))
            }

            Button {
                navigation.section = .favourites
            } label: {
                Label(l10n.text("Open Favourites", table: "Workspace"), systemImage: "heart")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(l10n.text("Open Favourites", table: "Workspace"))
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let searchResults, !searchResults.isEmpty {
                Text(
                    l10n.format(
                        "%@ surahs · %@ ayahs",
                        l10n.number(searchResults.surahIDs.count),
                        l10n.number(searchResults.verses.count),
                        table: "Workspace"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults.surahIDs, id: \.self) { id in
                            if let surah = store.library.surah(id) {
                                SurahIndexRow(
                                    surah: surah,
                                    selected: surah.id == navigation.readerSurahID,
                                    readCount: store.readCount(in: surah.id),
                                    action: { selectSurah(surah.id) }
                                )
                            }
                        }
                        ForEach(searchResults.verses, id: \.self) { reference in
                            if let surah = store.library.surah(reference.surahID),
                               let verse = surah.verses.first(where: { $0.id == reference.verseID }) {
                                AyahSearchRow(
                                    surah: surah,
                                    verse: verse,
                                    fontSize: store.settings.arabicFontSize,
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
                    .padding(.horizontal, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.text("No matches", table: "Workspace"))
                        .font(.callout.weight(.semibold))
                    Text(
                        l10n.format(
                            "Try a surah name, Arabic words, or a reference such as %@.",
                            l10n.reference(VerseReference(surahID: 2, verseID: 255)),
                            table: "Workspace"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(palette.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.text("Search results", table: "Workspace"))
    }

    private var surahIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.text("Surahs", table: "Workspace"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.library.surahs) { surah in
                        SurahIndexRow(
                            surah: surah,
                            selected: surah.id == navigation.readerSurahID,
                            readCount: store.readCount(in: surah.id),
                            action: { selectSurah(surah.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        showsSearchResults = false
        searchFocused = true
    }

    private func selectSurah(_ id: Int) {
        pendingScrollReference = nil
        highlightedReference = nil
        navigation.readerSurahID = id
        showsSearchResults = false
        searchFocused = false
    }

    private func open(_ reference: VerseReference) {
        navigation.readerSurahID = reference.surahID
        highlightedReference = reference
        pendingScrollReference = reference
        // A new request is deliberate even when its canonical reference is unchanged.
        scrollRequestID += 1
        showsSearchResults = false
    }

    private func consumeExternalReference(_ reference: VerseReference?) {
        guard let reference else { return }
        open(reference)
        searchFocused = false
        navigation.readerReference = nil
    }

    private func selectFirstSearchResult() {
        // Read the field's current value so Return never depends on an earlier render.
        let results = store.library.search(searchText)
        searchResults = results
        if let first = results.surahIDs.first {
            selectSurah(first)
        } else if let first = results.verses.first {
            open(first)
        } else {
            showsSearchResults = hasQuery
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

    private var progressDescription: String {
        if readCount > 0 {
            l10n.format(
                "%@ of %@ marked",
                l10n.number(readCount),
                l10n.number(surah.totalVerses),
                table: "Workspace"
            )
        } else {
            l10n.format("%@ verses", l10n.number(surah.totalVerses), table: "Workspace")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(l10n.quranNumber(surah.id))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.surahName(surah))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progressDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if readCount == surah.totalVerses {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(palette.success)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? palette.accent : palette.primary)
        .background(selected ? palette.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
    let fontSize: Double
    let isBookmarked: Bool
    let action: () -> Void
    let toggleBookmark: () -> Void

    private var reference: VerseReference {
        VerseReference(surahID: surah.id, verseID: verse.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: action) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(l10n.surahName(surah))
                            .font(.callout.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(l10n.reference(reference))
                            .font(.caption.monospacedDigit())
                            .fixedSize()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(l10n.format("Open %@ in the Quran", l10n.reference(reference), table: "Workspace"))
                .help(l10n.text("Open matching ayah", table: "Workspace"))

                ReaderFavouriteButton(reference: reference, isBookmarked: isBookmarked, action: toggleBookmark)
            }
            ArabicText(verse.text, size: fontSize)
                .padding(.vertical, fontSize * 0.12)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }
}

private struct SurahReader: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let surah: Surah
    let store: AppStore
    @Binding var pendingScrollReference: VerseReference?
    let highlightedReference: VerseReference?
    let requestID: Int
    let open: (VerseReference) -> Void
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                    .id(0)

                if surah.id != 1 && surah.id != 9,
                   let basmala = store.library.surah(1)?.verses.first {
                    ArabicText(basmala.text, size: store.settings.arabicFontSize)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                }

                ForEach(surah.verses) { verse in
                    VerseRow(
                        surah: surah,
                        verse: verse,
                        fontSize: store.settings.arabicFontSize,
                        isRead: store.isRead(surahID: surah.id, verseID: verse.id),
                        isBookmarked: store.isBookmarked(surahID: surah.id, verseID: verse.id),
                        isTarget: highlightedReference == VerseReference(surahID: surah.id, verseID: verse.id),
                        onMarkRead: { store.markRead(surahID: surah.id, verseID: verse.id) },
                        onBookmark: { store.toggleBookmark(surahID: surah.id, verseID: verse.id) }
                    )
                    .id(verse.id)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
        }
        .scrollPosition($scrollPosition, anchor: .top)
        .background(palette.surface)
        .task(id: requestID) {
            guard let reference = pendingScrollReference,
                  reference.surahID == surah.id,
                  surah.verses.contains(where: { $0.id == reference.verseID }) else { return }
            // Allow a newly selected chapter to install its exact verse targets.
            await Task.yield()
            guard !Task.isCancelled, pendingScrollReference == reference else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                scrollPosition.scrollTo(id: reference.verseID, anchor: .top)
            }
            pendingScrollReference = nil
        }
    }

    private var header: some View {
        let readCount = store.readCount(in: surah.id)
        let nextUnreadID = store.nextUnreadVerse(in: surah.id)?.id
        let bookmarks = store.bookmarks.filter { $0.surahID == surah.id }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.surahName(surah))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(l10n.isArabic ? surah.transliteration : surah.name)
                        .font(.callout)
                        .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        l10n.format(
                            "%@ · %@ verses",
                            l10n.revelationType(surah.type),
                            l10n.number(surah.totalVerses),
                            table: "Workspace"
                        )
                    )
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    readingControls(nextUnreadID: nextUnreadID, bookmarks: bookmarks)
                }
                VStack(alignment: .leading, spacing: 8) {
                    readingControls(nextUnreadID: nextUnreadID, bookmarks: bookmarks)
                }
            }
            .controlSize(.small)

            HStack(spacing: 10) {
                Text(
                    l10n.format(
                        "%@ of %@ marked",
                        l10n.number(readCount),
                        l10n.number(surah.totalVerses),
                        table: "Workspace"
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                ProgressView(value: Double(readCount), total: Double(max(1, surah.totalVerses)))
                    .progressViewStyle(.linear)
                    .frame(width: 64)
                    .accessibilityLabel(l10n.text("Quran progress", table: "Workspace"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func readingControls(nextUnreadID: Int?, bookmarks: [VerseReference]) -> some View {
        if let nextUnreadID {
            Button {
                open(VerseReference(surahID: surah.id, verseID: nextUnreadID))
            } label: {
                Label(l10n.text("Next unread", table: "Workspace"), systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
        } else {
            Label(l10n.text("Surah complete", table: "Workspace"), systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(palette.success)
        }

        Menu {
            if let reference = store.automaticNextReference,
               let automaticSurah = store.library.surah(reference.surahID) {
                Button {
                    store.startAutomaticReading()
                    open(reference)
                } label: {
                    Label(
                        l10n.format(
                            "Automatic: %@ · %@",
                            l10n.surahName(automaticSurah),
                            l10n.reference(reference),
                            table: "Workspace"
                        ),
                        systemImage: "books.vertical"
                    )
                }
                .help(l10n.text("Resume the saved automatic Quran position", table: "Workspace"))
            } else if store.isAutomaticComplete {
                Label(l10n.text("Full Quran sequence complete", table: "Workspace"), systemImage: "checkmark.seal")
            }
            Divider()
            if store.selectedSurahID == surah.id && store.settings.mode == .surah && store.settings.remindersEnabled {
                Label(l10n.text("Chosen-surah reminder plan", table: "Workspace"), systemImage: "checkmark")
            } else if nextUnreadID != nil {
                Button {
                    store.startSurah(surah.id)
                } label: {
                    Label(l10n.text("Use for chosen-surah reminders", table: "Workspace"), systemImage: "bell.badge")
                }
            }
        } label: {
            Label(l10n.text("Reminder plan", table: "Workspace"), systemImage: "bell")
        }
        .menuStyle(.borderedButton)

        if !bookmarks.isEmpty {
            Menu {
                ForEach(bookmarks, id: \.self) { bookmark in
                    Button(l10n.reference(bookmark)) {
                        open(bookmark)
                    }
                }
            } label: {
                Label(l10n.text("Favourites", table: "Workspace"), systemImage: "heart.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
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
    let isTarget: Bool
    let onMarkRead: () -> Void
    let onBookmark: () -> Void

    private var reference: VerseReference {
        VerseReference(surahID: surah.id, verseID: verse.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(l10n.reference(reference))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isTarget ? palette.accent : palette.primary.opacity(0.65))
                    .accessibilityAddTraits(isTarget ? .isSelected : [])
                Spacer(minLength: 8)
                ReaderFavouriteButton(reference: reference, isBookmarked: isBookmarked, action: onBookmark)
                if isRead {
                    Label(l10n.text("Marked", table: "Workspace"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(palette.success)
                        .accessibilityLabel(l10n.text("Verse marked as read", table: "Workspace"))
                } else {
                    Button(action: onMarkRead) {
                        Label(l10n.text("Mark read", table: "Workspace"), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(l10n.format("Mark %@ as read", l10n.reference(reference), table: "Workspace"))
                    .help(l10n.text("Confirm this verse in your Quran progress", table: "Workspace"))
                }
            }
            .controlSize(.small)
            ArabicText(verse.text, size: fontSize)
                .padding(.vertical, fontSize * 0.16)
                .textSelection(.enabled)

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(isTarget ? palette.accent.opacity(0.065) : .clear)
        .overlay(alignment: .leading) {
            if isTarget {
                Rectangle().fill(palette.accent).frame(width: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 20)
        }
    }
}

private struct ReaderFavouriteButton: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let reference: VerseReference
    let isBookmarked: Bool
    let action: () -> Void

    private var title: String {
        l10n.format(
            isBookmarked ? "Remove %@ from Favourites" : "Add %@ to Favourites",
            l10n.reference(reference),
            table: "Workspace"
        )
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isBookmarked ? "heart.fill" : "heart")
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isBookmarked ? palette.accent : palette.primary.opacity(0.65))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isBookmarked ? .isSelected : [])
        .help(title)
    }
}
