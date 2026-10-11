import XCTest
@testable import SukoonCore

final class QuranSearchTests: XCTestCase {
    func testDirectReferencesAcceptArabicDigitsAndCanonicalBoundaries() throws {
        let library = try QuranLibrary.load()
        let cases: [(String, VerseReference)] = [
            ("2:255", VerseReference(surahID: 2, verseID: 255)),
            ("٢:٢٥٥", VerseReference(surahID: 2, verseID: 255)),
            ("۲:۲۵۵", VerseReference(surahID: 2, verseID: 255)),
            (" ٢ : 255 \n", VerseReference(surahID: 2, verseID: 255)),
            ("1:1", VerseReference(surahID: 1, verseID: 1)),
            ("1:7", VerseReference(surahID: 1, verseID: 7)),
            ("2:286", VerseReference(surahID: 2, verseID: 286)),
            ("114:6", VerseReference(surahID: 114, verseID: 6))
        ]

        for (query, reference) in cases {
            let result = library.search(query)
            XCTAssertEqual(result.verses, [reference], query)
            XCTAssertTrue(result.surahIDs.isEmpty, query)
        }
    }

    func testInvalidReferencesReturnNoUnrelatedNameOrTextMatches() throws {
        let library = try QuranLibrary.load()
        for query in [
            "0:1", "115:1", "1:0", "1:8", "2:287", "114:7", "٢:٢٨٧",
            "-2:255", "Al-Baqarah:255", "الفاتحة:1", "2:", ":255", "2:255:1",
            "2:٢٥٥a", "999999999999999999999999999999:1"
        ] {
            XCTAssertTrue(library.search(query).isEmpty, query)
        }
    }

    func testUnvowelledPhraseFindsAyatAlKursiAndChapterSearchIsPreserved() throws {
        let library = try QuranLibrary.load()
        let reference = VerseReference(surahID: 2, verseID: 255)
        let originalText = try XCTUnwrap(library.surah(2)?.verses.first { $0.id == 255 }?.text)

        XCTAssertTrue(library.search("الله لا اله الا هو الحي القيوم").verses.contains(reference))
        XCTAssertTrue(library.search("لا تأخذه سنة ولا نوم").verses.contains(reference))
        XCTAssertTrue(library.search(originalText).verses.contains(reference))
        XCTAssertEqual(library.surah(2)?.verses.first { $0.id == 255 }?.text, originalText)
        XCTAssertEqual(library.search("aL-bAqArAh").surahIDs, [2])
        XCTAssertEqual(library.search("الفاتحة").surahIDs, [1])
        XCTAssertEqual(library.search("البَقَرة").surahIDs, [2])
        XCTAssertEqual(library.search("٢").surahIDs, [2])
        XCTAssertTrue(library.search("٢").verses.isEmpty)
        XCTAssertTrue(library.search("115").isEmpty)
        XCTAssertTrue(library.search(" \n\t").isEmpty)
        XCTAssertTrue(library.search("َۡـ").isEmpty)
    }

    func testNormalizationAndRepeatedSearchRetainCanonicalOrderAndSourceText() {
        let basmala = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"
        let source = [
            Surah(id: 1, name: "الفاتحة", transliteration: "Al-Fatihah", type: "meccan", totalVerses: 2,
                  verses: [Verse(id: 1, text: basmala), Verse(id: 2, text: "ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ")]),
            Surah(id: 27, name: "النمل", transliteration: "An-Naml", type: "meccan", totalVerses: 1,
                  verses: [Verse(id: 30, text: "إِنَّهُۥ مِن سُلَيۡمَٰنَ وَإِنَّهُۥ بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ")])
        ]
        let library = QuranLibrary(surahs: source)
        let expected = [VerseReference(surahID: 1, verseID: 1), VerseReference(surahID: 27, verseID: 30)]

        for query in ["بسم الله الرحمن الرحيم", "بِسۡمِ ٱللَّهِ", "  بِـسْمِ  \n الله  "] {
            XCTAssertEqual(library.search(query).verses, expected, query)
        }
        XCTAssertEqual(library.search("الله").verses, expected)
        XCTAssertEqual(library.search("بسم الله").verses, expected)
        XCTAssertEqual(library.surahs, source)
    }
}
