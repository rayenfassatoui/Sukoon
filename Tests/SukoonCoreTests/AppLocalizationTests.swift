import XCTest
@testable import SukoonCore

final class AppLocalizationTests: XCTestCase {
    func testQuranReferencesKeepChosenDigitsAndSurahAyahOrderInBothLanguages() {
        let reference = VerseReference(surahID: 2, verseID: 255)
        for language in AppLanguage.allCases {
            for style in QuranNumberStyle.allCases {
                let l10n = AppLocalization(language: language, quranNumberStyle: style)
                let expectedReference = style == .western ? "2:255" : "٢:٢٥٥"
                XCTAssertEqual(l10n.reference(reference), "\u{2066}\(expectedReference)\u{2069}")
                XCTAssertEqual(l10n.quranNumber(12), style == .western ? "12" : "١٢")
                XCTAssertEqual(l10n.number(12), language == .english ? "12" : "١٢")
            }
        }
    }
}
