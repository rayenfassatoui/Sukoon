import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public let library: QuranLibrary

    public var settings: AppSettings {
        didSet {
            if oldValue.mode != settings.mode || oldValue.remindersEnabled != settings.remindersEnabled {
                invalidatePendingReminder()
            }
            persist()
        }
    }

    public private(set) var selectedSurahID: Int? {
        didSet {
            if oldValue != selectedSurahID {
                invalidatePendingReminder()
            }
            persist()
        }
    }

    public private(set) var lastReminder: ReminderContent?

    public private(set) var bookmark: VerseReference? {
        didSet { persist() }
    }

    public private(set) var automaticVerseOffset: Int

    public var celebration: Celebration?
    public private(set) var persistenceError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reminderSeed: UInt64
    @ObservationIgnored private var reminderSequence: UInt64
    @ObservationIgnored private var ayahReminderID: UUID
    @ObservationIgnored private var duaReminderID: UUID
    @ObservationIgnored private var surahReminderID: UUID
    @ObservationIgnored private var automaticReminderID: UUID
    @ObservationIgnored private var automaticPreviewID: UUID
    private var readVerses: Set<VerseReference> {
        didSet { persist() }
    }
    private var readCountsBySurah: [Int: Int]

    private static let persistenceKey = "Sukoon.AppStore.state.v1"
    private static let duaReferences = [
        VerseReference(surahID: 2, verseID: 127),
        VerseReference(surahID: 2, verseID: 201),
        VerseReference(surahID: 3, verseID: 8),
        VerseReference(surahID: 3, verseID: 193),
        VerseReference(surahID: 7, verseID: 23),
        VerseReference(surahID: 14, verseID: 40),
        VerseReference(surahID: 20, verseID: 25),
        VerseReference(surahID: 25, verseID: 74)
    ]

    public init(library: QuranLibrary, defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
        reminderSeed = UInt64.random(in: UInt64.min...UInt64.max)
        reminderSequence = 0
        ayahReminderID = UUID()
        duaReminderID = UUID()
        surahReminderID = UUID()
        automaticReminderID = UUID()
        automaticPreviewID = UUID()

        var decodedState: PersistedState?
        var loadError: String?
        if let data = defaults.data(forKey: Self.persistenceKey) {
            do {
                decodedState = try JSONDecoder().decode(PersistedState.self, from: data)
            } catch {
                loadError = error.localizedDescription
            }
        }

        let state = decodedState ?? PersistedState()
        settings = state.settings
        if let selected = state.selectedSurahID, library.surah(selected) != nil {
            selectedSurahID = selected
        } else {
            selectedSurahID = nil
        }
        if let savedBookmark = state.bookmark,
           Self.contains(savedBookmark, in: library) {
            bookmark = savedBookmark
        } else {
            bookmark = nil
        }
        automaticVerseOffset = min(max(state.automaticVerseOffset, 0), library.verseCount)
        let validReadVerses = Set(state.readVerses.filter { Self.contains($0, in: library) })
        readVerses = validReadVerses
        readCountsBySurah = Dictionary(grouping: validReadVerses, by: \.surahID).mapValues(\.count)
        lastReminder = nil
        celebration = nil
        persistenceError = loadError.map {
            AppLocalization(language: state.settings.language).format("Saved Sukoon progress could not be read: %@", $0)
        }
    }

    /// Read the language even when a broken Quran resource prevents constructing the store.
    public static func savedLanguage(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let data = defaults.data(forKey: persistenceKey),
              let preference = try? JSONDecoder().decode(SavedLanguage.self, from: data) else { return .english }
        return preference.settings.language
    }

    public var activeSurah: Surah? {
        guard let selectedSurahID else { return nil }
        return library.surah(selectedSurahID)
    }

    public var automaticNextReference: VerseReference? {
        guard let result = library.verse(atGlobalOffset: automaticVerseOffset) else { return nil }
        return VerseReference(surahID: result.surah.id, verseID: result.verse.id)
    }

    public var automaticSurah: Surah? {
        library.verse(atGlobalOffset: automaticVerseOffset)?.surah
    }

    public var isAutomaticComplete: Bool {
        automaticVerseOffset >= library.verseCount
    }

    public var completedSurahIDs: Set<Int> {
        Set(library.surahs.lazy.filter { surah in
            !surah.verses.isEmpty && self.readCount(in: surah.id) == surah.verses.count
        }.map(\.id))
    }

    public var readVerseCount: Int {
        readVerses.count
    }

    public var completionFraction: Double {
        guard library.verseCount > 0 else { return 0 }
        return Double(readVerseCount) / Double(library.verseCount)
    }

    public var canScheduleReminder: Bool {
        guard settings.remindersEnabled else { return false }
        switch settings.mode {
        case .surah:
            guard let selectedSurahID else { return false }
            return nextUnreadVerse(in: selectedSurahID) != nil
        case .automatic:
            return !isAutomaticComplete
        case .mixed, .ayah, .dua:
            return library.verseCount > 0
        }
    }

    public func readCount(in surahID: Int) -> Int {
        readCountsBySurah[surahID, default: 0]
    }

    public func isRead(surahID: Int, verseID: Int) -> Bool {
        readVerses.contains(VerseReference(surahID: surahID, verseID: verseID))
    }

    public func nextUnreadVerse(in surahID: Int) -> Verse? {
        guard let surah = library.surah(surahID) else { return nil }
        return surah.verses.first { verse in
            !isRead(surahID: surahID, verseID: verse.id)
        }
    }

    public func startSurah(_ id: Int) {
        guard library.surah(id) != nil else { return }
        selectedSurahID = id
        var updatedSettings = settings
        updatedSettings.mode = .surah
        updatedSettings.remindersEnabled = true
        settings = updatedSettings
    }

    public func startAutomaticReading() {
        var updatedSettings = settings
        updatedSettings.mode = .automatic
        updatedSettings.remindersEnabled = true
        settings = updatedSettings
    }

    public func markRead(surahID: Int, verseID: Int) {
        let reference = VerseReference(surahID: surahID, verseID: verseID)
        guard Self.contains(reference, in: library) else { return }
        let inserted = readVerses.insert(reference).inserted
        guard inserted else { return }
        readCountsBySurah[surahID, default: 0] += 1

        if readVerseCount == library.verseCount, library.verseCount > 0 {
            celebration = .khatm
        } else if let surah = library.surah(surahID),
                  !surah.verses.isEmpty,
                  readCount(in: surahID) == surah.verses.count {
            celebration = .surah(surahID)
        }
    }

    public func setBookmark(surahID: Int, verseID: Int) {
        let reference = VerseReference(surahID: surahID, verseID: verseID)
        guard Self.contains(reference, in: library) else { return }
        bookmark = reference
    }

    public func nextReminder() -> ReminderContent? {
        guard settings.remindersEnabled else {
            lastReminder = nil
            return nil
        }
        let reminder = makeReminder(
            for: settings.mode,
            sequence: reminderSequence,
            automaticID: automaticReminderID
        )
        if reminder != nil {
            reminderSequence &+= 1
            ayahReminderID = UUID()
            duaReminderID = UUID()
            surahReminderID = UUID()
            automaticReminderID = UUID()
        }
        lastReminder = reminder
        return reminder
    }

    public func previewReminder() -> ReminderContent? {
        makeReminder(
            for: settings.mode,
            sequence: reminderSequence,
            automaticID: automaticPreviewID
        )
    }

    public func acknowledge(_ reminder: ReminderContent) {
        if reminder.kind == .automatic {
            guard settings.mode == .automatic,
                  lastReminder?.id == reminder.id,
                  let reference = reminder.reference,
                  reference == automaticNextReference else { return }
            // Persist the cursor and unique mark together through markRead's write.
            automaticVerseOffset += 1
            markRead(surahID: reference.surahID, verseID: reference.verseID)
            if isAutomaticComplete {
                celebration = .khatm
            }
            return
        }

        guard reminder.kind == .surah,
              settings.mode == .surah,
              lastReminder?.id == reminder.id,
              let reference = reminder.reference,
              reference.surahID == selectedSurahID else { return }
        markRead(surahID: reference.surahID, verseID: reference.verseID)
    }

    public func resetProgress() {
        automaticVerseOffset = 0
        readVerses = []
        readCountsBySurah = [:]
        selectedSurahID = nil
        bookmark = nil
        lastReminder = nil
        celebration = nil
        reminderSequence = 0
        ayahReminderID = UUID()
        duaReminderID = UUID()
        surahReminderID = UUID()
        automaticReminderID = UUID()
        automaticPreviewID = UUID()
    }

    private func makeReminder(
        for mode: ReminderMode,
        sequence: UInt64,
        automaticID: UUID
    ) -> ReminderContent? {
        let selection = Self.pseudoRandom(reminderSeed &+ sequence)
        return switch mode {
        case .ayah:
            makeRandomAyahReminder(selection: selection)
        case .dua:
            makeDuaReminder(selection: selection)
        case .surah:
            makeSurahReminder()
        case .automatic:
            makeAutomaticReminder(id: automaticID)
        case .mixed:
            if selection.isMultiple(of: 2) {
                makeRandomAyahReminder(selection: selection) ?? makeDuaReminder(selection: selection)
            } else {
                makeDuaReminder(selection: selection) ?? makeRandomAyahReminder(selection: selection)
            }
        }
    }

    private func makeRandomAyahReminder(selection: UInt64) -> ReminderContent? {
        let count = library.verseCount
        guard count > 0,
              let result = library.verse(atGlobalOffset: Int(selection % UInt64(count))) else {
            return nil
        }
        let l10n = AppLocalization(language: settings.language, quranNumberStyle: settings.quranNumberStyle)
        let reference = VerseReference(surahID: result.surah.id, verseID: result.verse.id)
        return ReminderContent(
            id: ayahReminderID,
            kind: .ayah,
            arabic: result.verse.text,
            title: l10n.surahName(result.surah),
            subtitle: l10n.format("Quran %@", l10n.reference(reference)),
            reference: reference
        )
    }

    private func makeDuaReminder(selection: UInt64) -> ReminderContent? {
        let references = Self.duaReferences
        guard !references.isEmpty else { return nil }
        let start = Int(selection % UInt64(references.count))
        for offset in 0..<references.count {
            let reference = references[(start + offset) % references.count]
            guard let surah = library.surah(reference.surahID),
                  let verse = surah.verses.first(where: { $0.id == reference.verseID }) else {
                continue
            }
            let l10n = AppLocalization(language: settings.language, quranNumberStyle: settings.quranNumberStyle)
            return ReminderContent(
                id: duaReminderID,
                kind: .dua,
                arabic: verse.text,
                title: l10n.text("Quranic supplication"),
                subtitle: l10n.format("Quran %@", l10n.reference(reference)),
                reference: reference
            )
        }
        return nil
    }

    private func makeSurahReminder() -> ReminderContent? {
        guard let surah = activeSurah,
              let verse = nextUnreadVerse(in: surah.id) else { return nil }
        let l10n = AppLocalization(language: settings.language, quranNumberStyle: settings.quranNumberStyle)
        let reference = VerseReference(surahID: surah.id, verseID: verse.id)
        return ReminderContent(
            id: surahReminderID,
            kind: .surah,
            arabic: verse.text,
            title: l10n.format("Continue %@", l10n.surahName(surah)),
            subtitle: l10n.format("Quran %@", l10n.reference(reference)),
            reference: reference
        )
    }

    private func makeAutomaticReminder(id: UUID) -> ReminderContent? {
        guard let result = library.verse(atGlobalOffset: automaticVerseOffset) else { return nil }
        let l10n = AppLocalization(language: settings.language, quranNumberStyle: settings.quranNumberStyle)
        let reference = VerseReference(surahID: result.surah.id, verseID: result.verse.id)
        return ReminderContent(
            id: id,
            kind: .automatic,
            arabic: result.verse.text,
            title: l10n.text("Automatic Quran"),
            subtitle: l10n.format("Quran %@", l10n.reference(reference)),
            reference: reference
        )
    }

    private func invalidatePendingReminder() {
        lastReminder = nil
        ayahReminderID = UUID()
        duaReminderID = UUID()
        surahReminderID = UUID()
        automaticReminderID = UUID()
        automaticPreviewID = UUID()
    }

    private func persist() {
        let state = PersistedState(
            settings: settings,
            selectedSurahID: selectedSurahID,
            bookmark: bookmark,
            readVerses: readVerses.sorted {
                ($0.surahID, $0.verseID) < ($1.surahID, $1.verseID)
            },
            automaticVerseOffset: automaticVerseOffset
        )
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: Self.persistenceKey)
            persistenceError = nil
        } catch {
            persistenceError = AppLocalization(language: settings.language)
                .format("Sukoon could not save progress: %@", error.localizedDescription)
        }
    }

    private static func contains(_ reference: VerseReference, in library: QuranLibrary) -> Bool {
        guard let surah = library.surah(reference.surahID) else { return false }
        return surah.verses.contains { $0.id == reference.verseID }
    }

    private static func pseudoRandom(_ value: UInt64) -> UInt64 {
        var result = value &+ 0x9E3779B97F4A7C15
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        return result ^ (result >> 31)
    }
}

private struct PersistedState: Codable {
    var settings: AppSettings
    var selectedSurahID: Int?
    var bookmark: VerseReference?
    var readVerses: [VerseReference]
    var automaticVerseOffset: Int

    private enum CodingKeys: String, CodingKey {
        case settings, selectedSurahID, bookmark, readVerses, automaticVerseOffset
    }

    init(
        settings: AppSettings = AppSettings(),
        selectedSurahID: Int? = nil,
        bookmark: VerseReference? = nil,
        readVerses: [VerseReference] = [],
        automaticVerseOffset: Int = 0
    ) {
        self.settings = settings
        self.selectedSurahID = selectedSurahID
        self.bookmark = bookmark
        self.readVerses = readVerses
        self.automaticVerseOffset = automaticVerseOffset
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        settings = try values.decode(AppSettings.self, forKey: .settings)
        selectedSurahID = try values.decodeIfPresent(Int.self, forKey: .selectedSurahID)
        bookmark = try values.decodeIfPresent(VerseReference.self, forKey: .bookmark)
        readVerses = try values.decode([VerseReference].self, forKey: .readVerses)
        automaticVerseOffset = try values.decodeIfPresent(Int.self, forKey: .automaticVerseOffset) ?? 0
    }
}

private struct SavedLanguage: Decodable {
    let settings: AppSettings
}
