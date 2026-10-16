import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public let library: QuranLibrary

    public var settings: AppSettings {
        didSet {
            if oldValue.mode != settings.mode || oldValue.remindersEnabled != settings.remindersEnabled
                || oldValue.quietHoursEnabled != settings.quietHoursEnabled
                || oldValue.quietHoursStartMinute != settings.quietHoursStartMinute
                || oldValue.quietHoursEndMinute != settings.quietHoursEndMinute {
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

    public private(set) var bookmarks: [VerseReference] {
        didSet { persist() }
    }

    public private(set) var snoozedUntil: Date? {
        didSet {
            if oldValue != snoozedUntil { invalidatePendingReminder() }
            persist()
        }
    }

    public private(set) var automaticVerseOffset: Int

    public var celebration: Celebration?
    public private(set) var persistenceError: String?
    public private(set) var needsOnboarding: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reminderSeed: UInt64
    @ObservationIgnored private var reminderSequence: UInt64
    @ObservationIgnored private var ayahReminderID: UUID
    @ObservationIgnored private var duaReminderID: UUID
    @ObservationIgnored private var surahReminderID: UUID
    @ObservationIgnored private var automaticReminderID: UUID
    @ObservationIgnored private var surahPreviewID: UUID
    @ObservationIgnored private var automaticPreviewID: UUID
    @ObservationIgnored private var applyingReadingBackup = false
    private var readVerses: Set<VerseReference> {
        didSet { persist() }
    }
    private var readCountsBySurah: [Int: Int]

    private static let persistenceKey = "Sukoon.AppStore.state.v1"
    private static let onboardingKey = "Sukoon.onboardingCompleted"
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
        if let completed = defaults.object(forKey: Self.onboardingKey) as? Bool {
            needsOnboarding = !completed
        } else {
            // Any legacy state counts as an existing installation, even if it needs recovery.
            let existingInstallation = defaults.object(forKey: Self.persistenceKey) != nil
                || defaults.bool(forKey: "hasOpenedSukoon")
            needsOnboarding = !existingInstallation
            defaults.set(existingInstallation, forKey: Self.onboardingKey)
        }
        reminderSeed = UInt64.random(in: UInt64.min...UInt64.max)
        reminderSequence = 0
        ayahReminderID = UUID()
        duaReminderID = UUID()
        surahReminderID = UUID()
        automaticReminderID = UUID()
        surahPreviewID = UUID()
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
        var seenBookmarks = Set<VerseReference>()
        bookmarks = state.bookmarks.filter {
            Self.contains($0, in: library) && seenBookmarks.insert($0).inserted
        }
        snoozedUntil = state.snoozedUntil
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

    public func completeOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
        needsOnboarding = false
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

    public func reminderSuspensionEnd(at now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let quietEnd = settings.quietHoursEnd(containing: now, calendar: calendar)
        let snoozeEnd = snoozedUntil.flatMap { $0 > now ? $0 : nil }
        let candidate: Date
        switch (quietEnd, snoozeEnd) {
        case let (quiet?, snooze?): candidate = max(quiet, snooze)
        case let (quiet?, nil): candidate = quiet
        case let (nil, snooze?): candidate = snooze
        case (nil, nil): return nil
        }
        return settings.quietHoursEnd(containing: candidate, calendar: calendar) ?? candidate
    }

    public func canDeliverReminder(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        canScheduleReminder && reminderSuspensionEnd(at: now, calendar: calendar) == nil
    }

    public func nextReminderDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard canScheduleReminder else { return nil }
        var candidate = now.addingTimeInterval(TimeInterval(max(30, settings.intervalSeconds)))
        if let snoozedUntil { candidate = max(candidate, snoozedUntil) }
        return settings.quietHoursEnd(containing: candidate, calendar: calendar) ?? candidate
    }

    public func snooze(for seconds: Int, now: Date = Date()) {
        guard seconds > 0 else {
            cancelSnooze()
            return
        }
        snoozedUntil = now.addingTimeInterval(TimeInterval(seconds))
    }

    public func cancelSnooze() {
        snoozedUntil = nil
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

        guard let surah = library.surah(surahID),
              readCount(in: surahID) == surah.verses.count else { return }

        if settings.mode == .surah, selectedSurahID == surahID,
           let nextSurahID = nextUnreadSurahID(after: surahID) {
            selectedSurahID = nextSurahID
        }

        celebration = readVerseCount == library.verseCount ? .khatm : .surah(surahID)
    }

    public func toggleBookmark(surahID: Int, verseID: Int) {
        let reference = VerseReference(surahID: surahID, verseID: verseID)
        guard Self.contains(reference, in: library) else { return }
        if bookmarks.contains(reference) {
            bookmarks.removeAll { $0 == reference }
        } else {
            bookmarks.insert(reference, at: 0)
        }
    }

    public func removeBookmark(_ reference: VerseReference) {
        bookmarks.removeAll { $0 == reference }
    }

    public func isBookmarked(surahID: Int, verseID: Int) -> Bool {
        bookmarks.contains(VerseReference(surahID: surahID, verseID: verseID))
    }

    public func exportReadingBackup() throws -> Data {
        let backup = ReadingBackup(
            formatVersion: 1,
            readVerses: readVerses.sorted { ($0.surahID, $0.verseID) < ($1.surahID, $1.verseID) },
            automaticVerseOffset: automaticVerseOffset,
            selectedSurahID: selectedSurahID,
            bookmarks: bookmarks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public func importReadingBackup(_ data: Data) throws {
        let backup = try JSONDecoder().decode(ReadingBackup.self, from: data)
        let l10n = AppLocalization(language: settings.language)
        guard backup.formatVersion == 1 else {
            throw ReadingBackupError(message: l10n.text("This backup version is not supported."))
        }
        guard (0...library.verseCount).contains(backup.automaticVerseOffset),
              backup.selectedSurahID == nil || library.surah(backup.selectedSurahID!) != nil,
              backup.readVerses.allSatisfy({ Self.contains($0, in: library) }),
              backup.bookmarks.allSatisfy({ Self.contains($0, in: library) }) else {
            throw ReadingBackupError(message: l10n.text("The backup contains invalid Quran references or reading positions."))
        }
        let restoredMarks = Set(backup.readVerses)
        var seenBookmarks = Set<VerseReference>()
        let restoredBookmarks = backup.bookmarks.filter { seenBookmarks.insert($0).inserted }
        applyingReadingBackup = true
        automaticVerseOffset = backup.automaticVerseOffset
        selectedSurahID = backup.selectedSurahID
        readVerses = restoredMarks
        readCountsBySurah = Dictionary(grouping: restoredMarks, by: \.surahID).mapValues(\.count)
        bookmarks = restoredBookmarks
        celebration = nil
        invalidatePendingReminder()
        applyingReadingBackup = false
        persist()
    }

    public func nextReminder() -> ReminderContent? {
        guard canDeliverReminder() else {
            lastReminder = nil
            return nil
        }
        let reminder = makeReminder(
            for: settings.mode,
            sequence: reminderSequence,
            automaticID: automaticReminderID,
            isPreview: false
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
            automaticID: automaticPreviewID,
            isPreview: true
        )
    }

    public func acknowledge(_ reminder: ReminderContent) {
        if reminder.kind == .automatic {
            guard settings.mode == .automatic,
                  lastReminder?.id == reminder.id,
                  let reference = reminder.reference,
                  reference == automaticNextReference else { return }
            // A cursor step and its unique mark share the same persisted boundary.
            let wasAlreadyRead = readVerses.contains(reference)
            automaticVerseOffset += 1
            markRead(surahID: reference.surahID, verseID: reference.verseID)
            if wasAlreadyRead {
                persist()
            }
            if isAutomaticComplete, celebration != .khatm {
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
        bookmarks = []
        lastReminder = nil
        celebration = nil
        reminderSequence = 0
        ayahReminderID = UUID()
        duaReminderID = UUID()
        surahReminderID = UUID()
        automaticReminderID = UUID()
        surahPreviewID = UUID()
        automaticPreviewID = UUID()
    }

    private func makeReminder(
        for mode: ReminderMode,
        sequence: UInt64,
        automaticID: UUID,
        isPreview: Bool
    ) -> ReminderContent? {
        let selection = Self.pseudoRandom(reminderSeed &+ sequence)
        return switch mode {
        case .ayah:
            makeRandomAyahReminder(selection: selection)
        case .dua:
            makeDuaReminder(selection: selection)
        case .surah:
            makeSurahReminder(id: isPreview ? surahPreviewID : surahReminderID)
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

    private func makeSurahReminder(id: UUID) -> ReminderContent? {
        guard let surah = activeSurah,
              let verse = nextUnreadVerse(in: surah.id) else { return nil }
        let l10n = AppLocalization(language: settings.language, quranNumberStyle: settings.quranNumberStyle)
        let reference = VerseReference(surahID: surah.id, verseID: verse.id)
        return ReminderContent(
            id: id,
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

    private func nextUnreadSurahID(after surahID: Int) -> Int? {
        guard let completedIndex = library.surahs.firstIndex(where: { $0.id == surahID }) else {
            return nil
        }
        for surah in library.surahs.dropFirst(completedIndex + 1)
            where !surah.verses.isEmpty && readCount(in: surah.id) < surah.verses.count {
            return surah.id
        }
        for surah in library.surahs.prefix(completedIndex)
            where !surah.verses.isEmpty && readCount(in: surah.id) < surah.verses.count {
            return surah.id
        }
        return nil
    }

    private func invalidatePendingReminder() {
        lastReminder = nil
        ayahReminderID = UUID()
        duaReminderID = UUID()
        surahReminderID = UUID()
        automaticReminderID = UUID()
        surahPreviewID = UUID()
        automaticPreviewID = UUID()
    }

    private func persist() {
        guard !applyingReadingBackup else { return }
        let state = PersistedState(
            settings: settings,
            selectedSurahID: selectedSurahID,
            bookmarks: bookmarks,
            snoozedUntil: snoozedUntil,
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
    var bookmarks: [VerseReference]
    var snoozedUntil: Date?
    var readVerses: [VerseReference]
    var automaticVerseOffset: Int

    private enum CodingKeys: String, CodingKey {
        case settings, selectedSurahID, bookmarks, snoozedUntil, readVerses, automaticVerseOffset
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case bookmark
    }

    init(
        settings: AppSettings = AppSettings(),
        selectedSurahID: Int? = nil,
        bookmarks: [VerseReference] = [],
        snoozedUntil: Date? = nil,
        readVerses: [VerseReference] = [],
        automaticVerseOffset: Int = 0
    ) {
        self.settings = settings
        self.selectedSurahID = selectedSurahID
        self.bookmarks = bookmarks
        self.snoozedUntil = snoozedUntil
        self.readVerses = readVerses
        self.automaticVerseOffset = automaticVerseOffset
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        settings = try values.decode(AppSettings.self, forKey: .settings)
        selectedSurahID = try values.decodeIfPresent(Int.self, forKey: .selectedSurahID)
        if let savedBookmarks = try values.decodeIfPresent([VerseReference].self, forKey: .bookmarks) {
            bookmarks = savedBookmarks
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            bookmarks = try legacy.decodeIfPresent(VerseReference.self, forKey: .bookmark).map { [$0] } ?? []
        }
        snoozedUntil = try values.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        readVerses = try values.decode([VerseReference].self, forKey: .readVerses)
        automaticVerseOffset = try values.decodeIfPresent(Int.self, forKey: .automaticVerseOffset) ?? 0
    }
}

private struct SavedLanguage: Decodable {
    let settings: AppSettings
}

private struct ReadingBackup: Codable {
    let formatVersion: Int
    let readVerses: [VerseReference]
    let automaticVerseOffset: Int
    let selectedSurahID: Int?
    let bookmarks: [VerseReference]
}

private struct ReadingBackupError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
