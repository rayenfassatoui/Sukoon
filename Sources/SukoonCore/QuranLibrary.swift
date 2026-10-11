import Foundation

/// Search matches retain only canonical identifiers; display text comes from the library.
public struct QuranSearchResults: Sendable, Equatable {
    public let surahIDs: [Int]
    public let verses: [VerseReference]

    public var isEmpty: Bool { surahIDs.isEmpty && verses.isEmpty }
}

public struct QuranLibrary: Sendable {
    public let surahs: [Surah]
    private let indexByID: [Int: Int]
    private let storedVerseCount: Int
    private let searchIndex: [SurahSearchIndex]

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
        // Construct once, never while rendering or on each search keystroke.
        searchIndex = surahs.map { surah in
            SurahSearchIndex(
                id: surah.id,
                name: normalizedQuranSearchText(surah.name),
                transliteration: normalizedQuranSearchText(surah.transliteration),
                verses: surah.verses.map {
                    VerseSearchIndex(id: $0.id, text: normalizedQuranSearchText($0.text))
                }
            )
        }
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

    /// Searches chapter names/numbers and original Arabic ayah text in canonical order.
    /// A colon denotes a direct reference; invalid references never fall back to text search.
    public func search(_ query: String) -> QuranSearchResults {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let empty = QuranSearchResults(surahIDs: [], verses: [])
        guard !term.isEmpty else { return empty }

        if term.contains(":") {
            let parts = term.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let surahID = quranSearchNumber(String(parts[0])),
                  let verseID = quranSearchNumber(String(parts[1])),
                  surahID > 0, verseID > 0,
                  let surah = surah(surahID),
                  surah.verses.contains(where: { $0.id == verseID }) else {
                return empty
            }
            return QuranSearchResults(
                surahIDs: [],
                verses: [VerseReference(surahID: surahID, verseID: verseID)]
            )
        }

        if let number = quranSearchNumber(term) {
            return QuranSearchResults(surahIDs: surah(number) == nil ? [] : [number], verses: [])
        }

        let normalized = normalizedQuranSearchText(term)
        guard !normalized.isEmpty else { return empty }
        var surahIDs: [Int] = []
        var verses: [VerseReference] = []
        for chapter in searchIndex {
            if chapter.name.contains(normalized) || chapter.transliteration.contains(normalized) {
                surahIDs.append(chapter.id)
            }
            for verse in chapter.verses where verse.text.contains(normalized) {
                verses.append(VerseReference(surahID: chapter.id, verseID: verse.id))
            }
        }
        return QuranSearchResults(surahIDs: surahIDs, verses: verses)
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

private struct SurahSearchIndex: Sendable {
    let id: Int
    let name: String
    let transliteration: String
    let verses: [VerseSearchIndex]
}

private struct VerseSearchIndex: Sendable {
    let id: Int
    let text: String
}

private func quranSearchNumber(_ value: String) -> Int? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var number = ""
    for character in trimmed {
        guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
        number.unicodeScalars.append(UnicodeScalar(48 + digit)!)
    }
    return Int(number)
}

private func normalizedQuranSearchText(_ value: String) -> String {
    var result = ""
    var pendingSpace = false
    for scalar in value.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            continue
        default:
            break
        }
        // Tatweel and Quranic recitation annotations are not part of ordinary spelling.
        if scalar.value == 0x0640 || (0x06D6...0x06ED).contains(scalar.value) {
            continue
        }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            pendingSpace = !result.isEmpty
            continue
        }
        if pendingSpace {
            result.append(" ")
            pendingSpace = false
        }
        result.unicodeScalars.append(scalar.value == 0x0671 ? UnicodeScalar(0x0627)! : scalar)
    }
    return result
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
