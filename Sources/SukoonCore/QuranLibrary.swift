import Foundation

public struct QuranLibrary: Sendable {
    public let surahs: [Surah]
    private let indexByID: [Int: Int]
    private let storedVerseCount: Int

    public var verseCount: Int {
        storedVerseCount
    }

    public init(surahs: [Surah]) {
        self.surahs = surahs
        var index: [Int: Int] = [:]
        var verseCount = 0
        for (offset, surah) in surahs.enumerated() {
            if index[surah.id] == nil {
                index[surah.id] = offset
            }
            verseCount += surah.verses.count
        }
        indexByID = index
        storedVerseCount = verseCount
    }

    public static func load() throws -> QuranLibrary {
        let resourceBundle = SukoonResources.bundle
        guard let url = resourceBundle.url(forResource: "quran", withExtension: "json") else {
            throw QuranLibraryError.resourceMissing
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw QuranLibraryError.unreadableResource(error.localizedDescription)
        }

        let surahs: [Surah]
        do {
            surahs = try JSONDecoder().decode([Surah].self, from: data)
        } catch {
            throw QuranLibraryError.invalidJSON(error.localizedDescription)
        }

        try validateBundledQuran(surahs)
        return QuranLibrary(surahs: surahs)
    }

    public func surah(_ id: Int) -> Surah? {
        guard let index = indexByID[id] else { return nil }
        return surahs[index]
    }

    func verse(atGlobalOffset offset: Int) -> (surah: Surah, verse: Verse)? {
        guard offset >= 0 else { return nil }
        var remaining = offset
        for surah in surahs {
            if remaining < surah.verses.count {
                return (surah, surah.verses[remaining])
            }
            remaining -= surah.verses.count
        }
        return nil
    }
}

public enum QuranLibraryError: LocalizedError, Equatable {
    case resourceMissing
    case unreadableResource(String)
    case invalidJSON(String)
    case invalidSurahSequence(expected: Int, actual: Int)
    case invalidVerseSequence(surahID: Int, expected: Int, actual: Int)
    case incorrectSurahCount(Int)
    case incorrectVerseCount(Int)
    case incorrectDeclaredVerseCount(surahID: Int, declared: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing:
            "The bundled Quran resource is missing."
        case let .unreadableResource(reason):
            "The bundled Quran resource could not be read: \(reason)"
        case let .invalidJSON(reason):
            "The bundled Quran resource is not valid JSON: \(reason)"
        case let .invalidSurahSequence(expected, actual):
            "Expected surah \(expected), found surah \(actual)."
        case let .invalidVerseSequence(surahID, expected, actual):
            "Expected verse \(expected) in surah \(surahID), found verse \(actual)."
        case let .incorrectSurahCount(count):
            "Expected 114 surahs, found \(count)."
        case let .incorrectVerseCount(count):
            "Expected 6,236 verses, found \(count)."
        case let .incorrectDeclaredVerseCount(surahID, declared, actual):
            "Surah \(surahID) declares \(declared) verses but contains \(actual)."
        }
    }
}

private func validateBundledQuran(_ surahs: [Surah]) throws {
    guard surahs.count == 114 else {
        throw QuranLibraryError.incorrectSurahCount(surahs.count)
    }

    var verseCount = 0
    for (surahOffset, surah) in surahs.enumerated() {
        let expectedSurahID = surahOffset + 1
        guard surah.id == expectedSurahID else {
            throw QuranLibraryError.invalidSurahSequence(expected: expectedSurahID, actual: surah.id)
        }
        guard surah.totalVerses == surah.verses.count else {
            throw QuranLibraryError.incorrectDeclaredVerseCount(
                surahID: surah.id,
                declared: surah.totalVerses,
                actual: surah.verses.count
            )
        }
        for (verseOffset, verse) in surah.verses.enumerated() {
            let expectedVerseID = verseOffset + 1
            guard verse.id == expectedVerseID else {
                throw QuranLibraryError.invalidVerseSequence(
                    surahID: surah.id,
                    expected: expectedVerseID,
                    actual: verse.id
                )
            }
        }
        verseCount += surah.verses.count
    }

    guard verseCount == 6_236 else {
        throw QuranLibraryError.incorrectVerseCount(verseCount)
    }
}

public enum QuranAttribution {
    public static let datasetName = "Quran JSON 3.1.2"
    public static let datasetURL = URL(string: "https://github.com/risan/quran-json/tree/v3.1.2")!
    public static let quranTextSourceName = "The Noble Qur'an Encyclopedia"
    public static let quranTextSourceURL = URL(string: "https://quranenc.com/en/home")!
    public static let transliterationSourceName = "Tanzil.net"
    public static let transliterationSourceURL = URL(string: "https://tanzil.net/trans/en.transliteration")!
    public static let licenseName = "CC BY-SA 4.0"
    public static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
}
