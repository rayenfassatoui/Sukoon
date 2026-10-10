import Foundation
import XCTest
@testable import SukoonCore

final class QuranLibraryTests: XCTestCase {
    func testBundledQuranIsCompleteSequentialAndUnmodifiedAtBoundaries() throws {
        let library = try QuranLibrary.load()

        XCTAssertEqual(library.surahs.count, 114)
        XCTAssertEqual(library.verseCount, 6_236)
        XCTAssertEqual(library.surahs.map(\.id), Array(1...114))

        for surah in library.surahs {
            XCTAssertEqual(surah.totalVerses, surah.verses.count, "Surah \(surah.id)")
            XCTAssertEqual(surah.verses.map(\.id), Array(1...surah.totalVerses), "Surah \(surah.id)")
        }

        XCTAssertEqual(
            library.surah(1)?.verses.first?.text,
            "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"
        )
        XCTAssertEqual(
            library.surah(114)?.verses.last?.text,
            "مِنَ ٱلۡجِنَّةِ وَٱلنَّاسِ"
        )
        XCTAssertEqual(library.surah(1)?.name, "الفاتحة")
        XCTAssertEqual(library.surah(114)?.transliteration, "An-Nas")
    }

    @MainActor
    func testDuaReminderUsesACompleteVerseFromTheBundledQuran() throws {
        let library = try QuranLibrary.load()
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: library, defaults: defaults)
        store.settings.mode = .dua

        let reminder = try XCTUnwrap(store.previewReminder())
        let reference = try XCTUnwrap(reminder.reference)
        let sourceVerse = try XCTUnwrap(
            library.surah(reference.surahID)?.verses.first { $0.id == reference.verseID }
        )

        XCTAssertEqual(reminder.kind, .dua)
        XCTAssertEqual(reminder.arabic, sourceVerse.text)
    }
}

private func isolatedDefaults() -> (UserDefaults, String) {
    let suite = "SukoonCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}
