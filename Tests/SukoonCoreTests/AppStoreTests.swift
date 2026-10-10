import Foundation
import XCTest
@testable import SukoonCore

final class AppStoreTests: XCTestCase {
    @MainActor
    func testManualAcknowledgementRepeatsUnconfirmedVerseAndPreviewConsumesNothing() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.startSurah(1)
        store.settings.autoAdvance = false

        let previewOne = try XCTUnwrap(store.previewReminder())
        let previewTwo = try XCTUnwrap(store.previewReminder())
        XCTAssertEqual(previewOne.reference, VerseReference(surahID: 1, verseID: 1))
        XCTAssertEqual(previewTwo.reference, previewOne.reference)
        XCTAssertEqual(previewTwo.arabic, previewOne.arabic)
        XCTAssertEqual(previewTwo.id, previewOne.id)
        XCTAssertNil(store.lastReminder)
        XCTAssertEqual(store.readVerseCount, 0)

        let firstDelivery = try XCTUnwrap(store.nextReminder())
        let deliveredState = store.lastReminder
        _ = store.previewReminder()
        XCTAssertEqual(store.lastReminder, deliveredState)
        XCTAssertEqual(store.readVerseCount, 0, "Delivery alone must not imply manual acknowledgement")
        let secondDelivery = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(secondDelivery.reference, firstDelivery.reference)
        XCTAssertEqual(store.readVerseCount, 0)

        store.acknowledge(secondDelivery)
        XCTAssertTrue(store.isRead(surahID: 1, verseID: 1))
        XCTAssertEqual(store.readVerseCount, 1)
        XCTAssertEqual(store.nextReminder()?.reference, VerseReference(surahID: 1, verseID: 2))
    }

    @MainActor
    func testAutoAdvanceStillRequiresSuccessfulDeliveryAcknowledgement() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.startSurah(1)
        store.settings.autoAdvance = true

        _ = store.previewReminder()
        XCTAssertEqual(store.readVerseCount, 0)
        let delivered = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(store.readVerseCount, 0)

        store.acknowledge(delivered)
        XCTAssertEqual(store.readVerseCount, 1)
        XCTAssertEqual(store.nextUnreadVerse(in: 1)?.id, 2)
    }

    @MainActor
    func testOnlySelectedSurahRemindersCanAdvanceProgress() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.startSurah(1)

        let randomAyah = ReminderContent(
            kind: .ayah,
            arabic: "آية",
            title: "Ayah",
            subtitle: "Quran 1:1",
            reference: VerseReference(surahID: 1, verseID: 1)
        )
        let dua = ReminderContent(
            kind: .dua,
            arabic: "دعاء",
            title: "Dua",
            subtitle: "Quran 1:1",
            reference: VerseReference(surahID: 1, verseID: 1)
        )
        let otherPlan = ReminderContent(
            kind: .surah,
            arabic: "آية",
            title: "Other plan",
            subtitle: "Quran 2:1",
            reference: VerseReference(surahID: 2, verseID: 1)
        )

        store.acknowledge(randomAyah)
        store.acknowledge(dua)
        store.acknowledge(otherPlan)
        XCTAssertEqual(store.readVerseCount, 0)

        store.settings.mode = .ayah
        let deliveredAyah = try XCTUnwrap(store.nextReminder())
        store.acknowledge(deliveredAyah)
        store.settings.mode = .mixed
        let mixedDelivery = try XCTUnwrap(store.nextReminder())
        store.acknowledge(mixedDelivery)
        XCTAssertEqual(store.readVerseCount, 0)

        store.startSurah(1)
        let oldManualPanel = try XCTUnwrap(store.nextReminder())
        store.startAutomaticReading()
        store.acknowledge(oldManualPanel)
        XCTAssertEqual(store.readVerseCount, 0, "A manual panel from a previous mode must be inert")
        XCTAssertEqual(store.automaticVerseOffset, 0)
    }

    @MainActor
    func testUniqueProgressCompletionPrecedenceAndIdempotentCelebrations() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)

        store.markRead(surahID: 1, verseID: 1)
        store.markRead(surahID: 1, verseID: 1)
        XCTAssertEqual(store.readVerseCount, 1)
        XCTAssertNil(store.celebration)

        store.markRead(surahID: 1, verseID: 2)
        XCTAssertEqual(store.celebration, .surah(1))
        XCTAssertEqual(store.completedSurahIDs, [1])
        store.celebration = nil
        store.markRead(surahID: 1, verseID: 2)
        XCTAssertNil(store.celebration, "An already-counted verse must not emit completion again")

        store.markRead(surahID: 2, verseID: 1)
        XCTAssertEqual(store.readVerseCount, 3)
        XCTAssertEqual(store.completionFraction, 1, accuracy: 0.000_001)
        XCTAssertEqual(store.celebration, .khatm, "Khatm takes precedence over final-surah completion")
        store.celebration = nil
        store.markRead(surahID: 2, verseID: 1)
        XCTAssertNil(store.celebration, "Khatm is emitted only once before reset")

        let relaunchedAtKhatm = AppStore(library: twoSurahLibrary(), defaults: defaults)
        XCTAssertEqual(relaunchedAtKhatm.readVerseCount, 3)
        XCTAssertNil(relaunchedAtKhatm.celebration)
        relaunchedAtKhatm.markRead(surahID: 2, verseID: 1)
        XCTAssertNil(relaunchedAtKhatm.celebration, "Relaunch must not replay a persisted completion")

        store.resetProgress()
        store.markRead(surahID: 1, verseID: 1)
        store.markRead(surahID: 1, verseID: 2)
        store.celebration = nil
        store.markRead(surahID: 2, verseID: 1)
        XCTAssertEqual(store.celebration, .khatm, "A reset begins a new completion boundary")
    }

    @MainActor
    func testProgressSettingsPlanAndBookmarkSurviveRelaunch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()

        do {
            let store = AppStore(library: library, defaults: defaults)
            store.settings = AppSettings(
                theme: .dark,
                accent: .gold,
                intervalSeconds: 30,
                menuBarAutoCloseSeconds: 20,
                mode: .ayah,
                remindersEnabled: false,
                arabicFontSize: 41,
                autoAdvance: false
            )
            store.startSurah(2)
            store.settings.autoAdvance = false
            store.setBookmark(surahID: 1, verseID: 2)
            store.markRead(surahID: 1, verseID: 1)
            store.markRead(surahID: 1, verseID: 1)
        }

        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.selectedSurahID, 2)
        XCTAssertEqual(restored.settings.theme, .dark)
        XCTAssertEqual(restored.settings.accent, .gold)
        XCTAssertEqual(restored.settings.intervalSeconds, 30)
        XCTAssertEqual(restored.settings.menuBarAutoCloseSeconds, 20)
        XCTAssertEqual(restored.settings.mode, .surah)
        XCTAssertTrue(restored.settings.remindersEnabled)
        XCTAssertFalse(restored.settings.autoAdvance)
        XCTAssertEqual(restored.settings.arabicFontSize, 41)
        XCTAssertEqual(restored.bookmark, VerseReference(surahID: 1, verseID: 2))
        XCTAssertEqual(restored.readVerseCount, 1)
        XCTAssertTrue(restored.isRead(surahID: 1, verseID: 1))
        XCTAssertNil(restored.lastReminder)
        XCTAssertNil(restored.celebration)
        XCTAssertNil(restored.persistenceError)
    }

    @MainActor
    func testSettingsUpgradeKeepsLegacyProgressAndPersistsNewPreferences() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyState = """
        {
          "settings": {
            "theme": "dark", "accent": "rose", "intervalMinutes": 15,
            "mode": "surah", "remindersEnabled": false,
            "arabicFontSize": 40, "autoAdvance": false
          },
          "selectedSurahID": 1,
          "bookmark": { "surahID": 1, "verseID": 2 },
          "readVerses": [{ "surahID": 1, "verseID": 1 }]
        }
        """
        defaults.set(Data(legacyState.utf8), forKey: "Sukoon.AppStore.state.v1")
        let library = twoSurahLibrary()
        let upgraded = AppStore(library: library, defaults: defaults)
        var expectedSettings = AppSettings(theme: .dark, accent: .rose, intervalSeconds: 900,
                                          mode: .surah, remindersEnabled: false, arabicFontSize: 40,
                                          autoAdvance: false, language: .english)
        XCTAssertEqual(upgraded.settings, expectedSettings)
        XCTAssertNil(upgraded.persistenceError)
        XCTAssertEqual(upgraded.automaticVerseOffset, 0)
        XCTAssertEqual(upgraded.automaticNextReference, VerseReference(surahID: 1, verseID: 1))

        upgraded.settings.language = .arabic
        upgraded.settings.menuBarAutoCloseSeconds = 15
        upgraded.settings.intervalSeconds = 60
        expectedSettings.language = .arabic
        expectedSettings.menuBarAutoCloseSeconds = 15
        expectedSettings.intervalSeconds = 60
        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.settings, expectedSettings)
        XCTAssertEqual(restored.selectedSurahID, 1)
        XCTAssertEqual(restored.bookmark, VerseReference(surahID: 1, verseID: 2))
        XCTAssertEqual(restored.readVerseCount, 1)
        XCTAssertTrue(restored.isRead(surahID: 1, verseID: 1))
        XCTAssertEqual(restored.nextUnreadVerse(in: 1)?.id, 2)
        XCTAssertEqual(restored.automaticVerseOffset, 0)
        XCTAssertEqual(restored.automaticNextReference, VerseReference(surahID: 1, verseID: 1))
    }

    @MainActor
    func testResetClearsOnlyProgressBoundariesAndPersistsTheReset() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()
        let store = AppStore(library: library, defaults: defaults)
        store.settings = AppSettings(theme: .light, accent: .rose, intervalSeconds: 600,
                                     menuBarAutoCloseSeconds: 20, language: .arabic)
        store.startAutomaticReading()
        store.acknowledge(try XCTUnwrap(store.nextReminder()))
        XCTAssertEqual(store.automaticVerseOffset, 1)
        store.startSurah(1)
        store.settings.theme = .light
        store.settings.accent = .rose
        store.settings.intervalSeconds = 600
        store.setBookmark(surahID: 1, verseID: 1)
        store.markRead(surahID: 1, verseID: 1)
        _ = store.nextReminder()

        store.resetProgress()

        XCTAssertEqual(store.readVerseCount, 0)
        XCTAssertNil(store.selectedSurahID)
        XCTAssertNil(store.bookmark)
        XCTAssertNil(store.lastReminder)
        XCTAssertNil(store.celebration)
        XCTAssertEqual(store.automaticVerseOffset, 0)
        XCTAssertEqual(store.automaticNextReference, VerseReference(surahID: 1, verseID: 1))
        XCTAssertEqual(store.settings.theme, .light)
        XCTAssertEqual(store.settings.accent, .rose)
        XCTAssertEqual(store.settings.intervalSeconds, 600)
        XCTAssertEqual(store.settings.menuBarAutoCloseSeconds, 20)
        XCTAssertEqual(store.settings.mode, .surah, "Reset preserves every setting, including mode")
        XCTAssertTrue(store.settings.remindersEnabled)

        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.readVerseCount, 0)
        XCTAssertNil(restored.selectedSurahID)
        XCTAssertNil(restored.bookmark)
        XCTAssertEqual(restored.settings.mode, .surah)
        XCTAssertEqual(restored.settings.intervalSeconds, 600)
        XCTAssertEqual(restored.settings.menuBarAutoCloseSeconds, 20)
        XCTAssertEqual(restored.settings.language, .arabic)
        XCTAssertEqual(restored.automaticVerseOffset, 0)
    }

    @MainActor
    func testSchedulingRequiresEnabledUsableSelectedPlan() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)

        store.settings.mode = .surah
        XCTAssertFalse(store.canScheduleReminder)
        XCTAssertNil(store.nextReminder())
        store.startSurah(2)
        XCTAssertTrue(store.canScheduleReminder)
        store.markRead(surahID: 2, verseID: 1)
        XCTAssertFalse(store.canScheduleReminder)
        XCTAssertNil(store.nextReminder())

        store.settings.mode = .ayah
        XCTAssertTrue(store.canScheduleReminder)
        store.settings.remindersEnabled = false
        XCTAssertFalse(store.canScheduleReminder)
        XCTAssertNil(store.nextReminder())
        XCTAssertNotNil(store.previewReminder(), "A settings preview remains available while scheduling is paused")
    }

    @MainActor
    func testAutomaticSequenceCrossesSurahsAndIgnoresExistingManualMarks() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.markRead(surahID: 1, verseID: 2)
        store.startAutomaticReading()

        XCTAssertEqual(store.settings.mode, .automatic)
        XCTAssertTrue(store.settings.remindersEnabled)
        XCTAssertEqual(store.automaticVerseOffset, 0)
        XCTAssertEqual(store.automaticNextReference, VerseReference(surahID: 1, verseID: 1))
        XCTAssertEqual(store.automaticSurah?.id, 1)

        let preview = try XCTUnwrap(store.previewReminder())
        XCTAssertEqual(preview.kind, .automatic)
        XCTAssertEqual(preview.reference, VerseReference(surahID: 1, verseID: 1))
        store.acknowledge(preview)
        XCTAssertEqual(store.automaticVerseOffset, 0, "A preview is not a delivered verse")

        let first = try XCTUnwrap(store.nextReminder())
        store.acknowledge(first)
        XCTAssertEqual(store.automaticVerseOffset, 1)
        XCTAssertTrue(store.isRead(surahID: 1, verseID: 1))

        let alreadyMarkedSecond = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(alreadyMarkedSecond.reference, VerseReference(surahID: 1, verseID: 2))
        store.acknowledge(alreadyMarkedSecond)
        XCTAssertEqual(store.automaticVerseOffset, 2, "Unique manual progress must not skip the automatic cursor")
        XCTAssertEqual(store.automaticNextReference, VerseReference(surahID: 2, verseID: 1))
        XCTAssertEqual(store.automaticSurah?.id, 2)
    }

    @MainActor
    func testAutomaticAcknowledgementRequiresLatestDeliveredIdentity() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.startAutomaticReading()

        let staleDelivery = try XCTUnwrap(store.nextReminder())
        let currentDelivery = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(staleDelivery.reference, currentDelivery.reference)
        XCTAssertNotEqual(staleDelivery.id, currentDelivery.id)

        store.acknowledge(staleDelivery)
        XCTAssertEqual(store.automaticVerseOffset, 0)
        store.acknowledge(try XCTUnwrap(store.previewReminder()))
        XCTAssertEqual(store.automaticVerseOffset, 0)

        store.settings.mode = .ayah
        XCTAssertNil(store.lastReminder)
        store.startAutomaticReading()
        store.acknowledge(currentDelivery)
        XCTAssertEqual(store.automaticVerseOffset, 0, "Changing plans invalidates an old automatic panel")

        let replacement = try XCTUnwrap(store.nextReminder())
        store.acknowledge(replacement)
        store.acknowledge(replacement)
        XCTAssertEqual(store.automaticVerseOffset, 1, "A delivered verse is acknowledged idempotently")
    }

    @MainActor
    func testAutomaticTerminalCompletionDoesNotWrapAndEmitsKhatmOnce() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()
        let store = AppStore(library: library, defaults: defaults)
        for reference in [
            VerseReference(surahID: 1, verseID: 1),
            VerseReference(surahID: 1, verseID: 2),
            VerseReference(surahID: 2, verseID: 1)
        ] {
            store.markRead(surahID: reference.surahID, verseID: reference.verseID)
        }
        store.celebration = nil
        store.startAutomaticReading()

        var finalDelivery: ReminderContent?
        for expected in [
            VerseReference(surahID: 1, verseID: 1),
            VerseReference(surahID: 1, verseID: 2),
            VerseReference(surahID: 2, verseID: 1)
        ] {
            let delivery = try XCTUnwrap(store.nextReminder())
            XCTAssertEqual(delivery.reference, expected)
            store.acknowledge(delivery)
            finalDelivery = delivery
        }

        XCTAssertEqual(store.automaticVerseOffset, library.verseCount)
        XCTAssertTrue(store.isAutomaticComplete)
        XCTAssertNil(store.automaticNextReference)
        XCTAssertNil(store.automaticSurah)
        XCTAssertFalse(store.canScheduleReminder)
        XCTAssertNil(store.nextReminder())
        XCTAssertNil(store.previewReminder())
        XCTAssertEqual(store.celebration, .khatm, "Sequential completion is independent of unique read progress")

        store.celebration = nil
        store.acknowledge(try XCTUnwrap(finalDelivery))
        XCTAssertNil(store.celebration, "The terminal delivery cannot complete the plan twice")
        XCTAssertEqual(store.automaticVerseOffset, library.verseCount)

        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertTrue(restored.isAutomaticComplete)
        XCTAssertNil(restored.automaticNextReference)
        XCTAssertNil(restored.celebration)
    }

    @MainActor
    func testAutomaticCursorSurvivesPauseManualSelectionModeReturnAndRelaunch() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()
        let store = AppStore(library: library, defaults: defaults)
        store.startAutomaticReading()
        store.acknowledge(try XCTUnwrap(store.nextReminder()))
        store.settings.remindersEnabled = false
        XCTAssertEqual(store.automaticVerseOffset, 1)
        XCTAssertFalse(store.canScheduleReminder)

        store.startSurah(2)
        XCTAssertNil(store.lastReminder)
        XCTAssertEqual(store.selectedSurahID, 2)
        let manualDelivery = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(manualDelivery.kind, .surah)
        store.acknowledge(manualDelivery)
        store.setBookmark(surahID: 2, verseID: 1)
        XCTAssertEqual(store.automaticVerseOffset, 1)

        store.startAutomaticReading()
        XCTAssertEqual(store.selectedSurahID, 2)
        XCTAssertEqual(store.bookmark, VerseReference(surahID: 2, verseID: 1))
        XCTAssertEqual(store.automaticNextReference, VerseReference(surahID: 1, verseID: 2))

        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.settings.mode, .automatic)
        XCTAssertTrue(restored.settings.remindersEnabled)
        XCTAssertEqual(restored.selectedSurahID, 2)
        XCTAssertEqual(restored.bookmark, VerseReference(surahID: 2, verseID: 1))
        XCTAssertEqual(restored.automaticVerseOffset, 1)
        XCTAssertEqual(restored.automaticNextReference, VerseReference(surahID: 1, verseID: 2))
    }

    @MainActor
    func testPersistedAutomaticOffsetIsBoundedToTheCurrentLibrary() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()

        defaults.set(
            Data(#"{"settings":{},"readVerses":[],"automaticVerseOffset":99}"#.utf8),
            forKey: "Sukoon.AppStore.state.v1"
        )
        let beyondEnd = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(beyondEnd.automaticVerseOffset, library.verseCount)
        XCTAssertTrue(beyondEnd.isAutomaticComplete)

        defaults.set(
            Data(#"{"settings":{},"readVerses":[],"automaticVerseOffset":-10}"#.utf8),
            forKey: "Sukoon.AppStore.state.v1"
        )
        let beforeStart = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(beforeStart.automaticVerseOffset, 0)
        XCTAssertEqual(beforeStart.automaticNextReference, VerseReference(surahID: 1, verseID: 1))
    }
}

private func twoSurahLibrary() -> QuranLibrary {
    QuranLibrary(surahs: [
        Surah(
            id: 1,
            name: "الأولى",
            transliteration: "First",
            type: "meccan",
            totalVerses: 2,
            verses: [
                Verse(id: 1, text: "الآية الأولى"),
                Verse(id: 2, text: "الآية الثانية")
            ]
        ),
        Surah(
            id: 2,
            name: "الثانية",
            transliteration: "Second",
            type: "medinan",
            totalVerses: 1,
            verses: [Verse(id: 1, text: "الآية الأخيرة")]
        )
    ])
}

private func makeDefaults() -> (UserDefaults, String) {
    let suite = "SukoonCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}
