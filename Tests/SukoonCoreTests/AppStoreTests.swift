import Foundation
import XCTest
@testable import SukoonCore

final class AppStoreTests: XCTestCase {
    @MainActor
    func testOnboardingResumesUntilFinishedWithoutResettingChoices() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()
        let firstLaunch = AppStore(library: library, defaults: defaults)
        XCTAssertTrue(firstLaunch.needsOnboarding)
        firstLaunch.settings.language = .arabic
        firstLaunch.settings.quranNumberStyle = .western
        firstLaunch.settings.arabicFontSize = 48
        defaults.set(true, forKey: "hasOpenedSukoon")

        let interrupted = AppStore(library: library, defaults: defaults)
        XCTAssertTrue(interrupted.needsOnboarding)
        XCTAssertEqual(interrupted.settings.language, .arabic)
        XCTAssertEqual(interrupted.settings.quranNumberStyle, .western)
        XCTAssertEqual(interrupted.settings.arabicFontSize, 48)
        interrupted.markRead(surahID: 1, verseID: 1)
        interrupted.toggleBookmark(surahID: 1, verseID: 2)
        interrupted.completeOnboarding()

        let completed = AppStore(library: library, defaults: defaults)
        XCTAssertFalse(completed.needsOnboarding)
        XCTAssertEqual(completed.settings, interrupted.settings)
        XCTAssertTrue(completed.isRead(surahID: 1, verseID: 1))
        XCTAssertTrue(completed.isBookmarked(surahID: 1, verseID: 2))
    }

    @MainActor
    func testExistingInstallationsDoNotReceiveOnboarding() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "hasOpenedSukoon")
        XCTAssertFalse(AppStore(library: twoSurahLibrary(), defaults: defaults).needsOnboarding)

        let (legacyDefaults, legacySuite) = makeDefaults()
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        let legacyState = Data("""
            {"settings":{"language":"ar"},"readVerses":[{"surahID":1,"verseID":1}],
             "bookmarks":[{"surahID":1,"verseID":2}],"automaticVerseOffset":1}
            """.utf8)
        legacyDefaults.set(legacyState, forKey: "Sukoon.AppStore.state.v1")
        let upgraded = AppStore(library: twoSurahLibrary(), defaults: legacyDefaults)
        XCTAssertFalse(upgraded.needsOnboarding)
        XCTAssertEqual(upgraded.settings.language, .arabic)
        XCTAssertTrue(upgraded.isRead(surahID: 1, verseID: 1))
        XCTAssertTrue(upgraded.isBookmarked(surahID: 1, verseID: 2))
        XCTAssertEqual(upgraded.automaticVerseOffset, 1)
    }

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
                quranFontName: "AmiriQuran-Regular",
                reminderPanelWidth: 424,
                reminderPanelHeight: 218,
                autoAdvance: false,
                quranNumberStyle: .arabic
            )
            store.startSurah(2)
            store.settings.autoAdvance = false
            store.toggleBookmark(surahID: 1, verseID: 2)
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
        XCTAssertEqual(restored.settings.quranFontName, "AmiriQuran-Regular")
        XCTAssertEqual(restored.settings.reminderPanelWidth, 424)
        XCTAssertEqual(restored.settings.reminderPanelHeight, 218)
        XCTAssertEqual(restored.settings.quranNumberStyle, .arabic)
        XCTAssertEqual(restored.bookmarks, [VerseReference(surahID: 1, verseID: 2)])
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
        XCTAssertEqual(restored.bookmarks, [VerseReference(surahID: 1, verseID: 2)])
        XCTAssertEqual(restored.readVerseCount, 1)
        XCTAssertTrue(restored.isRead(surahID: 1, verseID: 1))
        XCTAssertEqual(restored.nextUnreadVerse(in: 1)?.id, 2)
        XCTAssertEqual(restored.automaticVerseOffset, 0)
        XCTAssertEqual(restored.automaticNextReference, VerseReference(surahID: 1, verseID: 1))
    }

    @MainActor
    func testArabicStateUpgradePreservesDigitsWhileLanguageAndNumberChoicesChangeIndependently() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = """
        {
          "settings": { "language": "ar", "intervalSeconds": 60, "menuBarAutoCloseSeconds": 20 },
          "selectedSurahID": 1,
          "automaticVerseOffset": 1,
          "bookmark": { "surahID": 1, "verseID": 2 },
          "readVerses": [{ "surahID": 1, "verseID": 1 }]
        }
        """
        defaults.set(Data(state.utf8), forKey: "Sukoon.AppStore.state.v1")
        let library = twoSurahLibrary()
        let upgraded = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(upgraded.settings.quranNumberStyle, .arabic)
        XCTAssertNil(upgraded.persistenceError)

        upgraded.settings.language = .english
        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.settings.language, .english)
        XCTAssertEqual(restored.settings.quranNumberStyle, .arabic)
        XCTAssertEqual(restored.settings.intervalSeconds, 60)
        XCTAssertEqual(restored.settings.menuBarAutoCloseSeconds, 20)
        XCTAssertEqual(restored.selectedSurahID, 1)
        XCTAssertEqual(restored.automaticVerseOffset, 1)
        XCTAssertEqual(restored.bookmarks, [VerseReference(surahID: 1, verseID: 2)])
        XCTAssertTrue(restored.isRead(surahID: 1, verseID: 1))

        restored.settings.quranNumberStyle = .western
        XCTAssertEqual(restored.settings.language, .english)
        restored.settings.language = .arabic
        let switched = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(switched.settings.language, .arabic)
        XCTAssertEqual(switched.settings.quranNumberStyle, .western)
        XCTAssertEqual(switched.automaticVerseOffset, 1)
        XCTAssertEqual(switched.readVerseCount, 1)
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
        store.toggleBookmark(surahID: 1, verseID: 1)
        store.markRead(surahID: 1, verseID: 1)
        _ = store.nextReminder()

        store.resetProgress()

        XCTAssertEqual(store.readVerseCount, 0)
        XCTAssertNil(store.selectedSurahID)
        XCTAssertEqual(store.bookmarks, [])
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
        XCTAssertEqual(restored.bookmarks, [])
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
        store.markRead(surahID: 2, verseID: 1)
        XCTAssertTrue(store.canScheduleReminder)
        XCTAssertEqual(store.selectedSurahID, 1, "Chosen reading wraps to the first unread surah")
        XCTAssertTrue(store.canScheduleReminder)
        XCTAssertEqual(store.nextReminder()?.reference, VerseReference(surahID: 1, verseID: 1))
        store.markRead(surahID: 1, verseID: 1)
        store.markRead(surahID: 1, verseID: 2)
        XCTAssertEqual(store.celebration, .khatm)
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
    func testChosenSurahCompletionAdvancesUnreadPlanPersistsWithoutTouchingAutomaticState() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = fourSurahLibrary()
        let store = AppStore(library: library, defaults: defaults)
        store.settings.theme = .dark
        store.settings.accent = .gold

        store.startAutomaticReading()
        let automaticDelivery = try XCTUnwrap(store.nextReminder())
        store.acknowledge(automaticDelivery)
        XCTAssertEqual(store.automaticVerseOffset, 1)
        store.toggleBookmark(surahID: 4, verseID: 1)

        store.startSurah(2)
        XCTAssertEqual(store.selectedSurahID, 2)
        let preview = try XCTUnwrap(store.previewReminder())
        store.acknowledge(preview)
        XCTAssertEqual(store.readVerseCount, 1, "A preview cannot advance the chosen plan")

        let staleDelivery = try XCTUnwrap(store.nextReminder())
        let currentDelivery = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(staleDelivery.reference, currentDelivery.reference)
        XCTAssertNotEqual(staleDelivery.id, currentDelivery.id)
        let activePreview = try XCTUnwrap(store.previewReminder())
        XCTAssertNotEqual(activePreview.id, currentDelivery.id)
        store.acknowledge(activePreview)
        XCTAssertEqual(store.readVerseCount, 1, "A chosen-plan preview cannot acknowledge the active delivery")
        store.acknowledge(staleDelivery)
        XCTAssertEqual(store.readVerseCount, 1, "A stale chosen-plan delivery is inert")
        XCTAssertEqual(store.selectedSurahID, 2)

        store.acknowledge(currentDelivery)
        let finalDelivery = try XCTUnwrap(store.nextReminder())
        XCTAssertEqual(finalDelivery.reference, VerseReference(surahID: 2, verseID: 2))
        store.acknowledge(finalDelivery)
        XCTAssertEqual(store.selectedSurahID, 3)
        XCTAssertEqual(store.celebration, .surah(2))
        XCTAssertEqual(store.automaticVerseOffset, 1, "Chosen completion cannot move the automatic cursor")

        store.celebration = nil
        store.acknowledge(finalDelivery)
        XCTAssertNil(store.celebration, "A completed chosen surah emits success only once")
        XCTAssertEqual(store.selectedSurahID, 3)

        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.settings.mode, .surah)
        XCTAssertEqual(restored.settings.theme, .dark)
        XCTAssertEqual(restored.settings.accent, .gold)
        XCTAssertEqual(restored.selectedSurahID, 3)
        XCTAssertEqual(restored.automaticVerseOffset, 1)
        XCTAssertEqual(restored.automaticNextReference, VerseReference(surahID: 1, verseID: 2))
        XCTAssertEqual(restored.bookmarks, [VerseReference(surahID: 4, verseID: 1)])
        XCTAssertNil(restored.celebration, "Transient success is not replayed after relaunch")

        let thirdDelivery = try XCTUnwrap(restored.nextReminder())
        restored.acknowledge(thirdDelivery)
        XCTAssertEqual(restored.selectedSurahID, 4)
        XCTAssertEqual(restored.celebration, .surah(3))
        restored.celebration = nil

        let fourthDelivery = try XCTUnwrap(restored.nextReminder())
        restored.acknowledge(fourthDelivery)
        XCTAssertEqual(restored.selectedSurahID, 1, "Chosen reading wraps to the first unread chapter")
        XCTAssertEqual(restored.celebration, .surah(4))
        restored.celebration = nil

        let lastDelivery = try XCTUnwrap(restored.nextReminder())
        XCTAssertEqual(lastDelivery.reference, VerseReference(surahID: 1, verseID: 2))
        restored.acknowledge(lastDelivery)
        XCTAssertEqual(restored.celebration, .khatm, "All-read completion remains the khatm boundary")
        XCTAssertEqual(restored.selectedSurahID, 1)
        XCTAssertEqual(restored.automaticVerseOffset, 1)

        restored.celebration = nil
        restored.acknowledge(lastDelivery)
        XCTAssertNil(restored.celebration, "The terminal chosen delivery cannot complete twice")
        XCTAssertNil(restored.nextReminder())
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
        store.toggleBookmark(surahID: 2, verseID: 1)
        XCTAssertEqual(store.automaticVerseOffset, 1)

        store.startAutomaticReading()
        XCTAssertEqual(store.selectedSurahID, 1, "Completing the selected surah advances the chosen plan")
        XCTAssertEqual(store.bookmarks, [VerseReference(surahID: 2, verseID: 1)])
        XCTAssertEqual(store.automaticNextReference, VerseReference(surahID: 1, verseID: 2))

        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.settings.mode, .automatic)
        XCTAssertTrue(restored.settings.remindersEnabled)
        XCTAssertEqual(restored.selectedSurahID, 1)
        XCTAssertEqual(restored.bookmarks, [VerseReference(surahID: 2, verseID: 1)])
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

    @MainActor
    func testQuietHoursRespectOvernightBoundariesAndDeferredDelivery() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.settings.quietHoursEnabled = true
        store.settings.intervalSeconds = 120
        let calendar = testCalendar()
        XCTAssertTrue(store.canDeliverReminder(at: testDate("2026-06-01T22:59:00Z"), calendar: calendar))
        XCTAssertFalse(store.canDeliverReminder(at: testDate("2026-06-01T23:00:00Z"), calendar: calendar))
        XCTAssertFalse(store.canDeliverReminder(at: testDate("2026-06-02T07:59:00Z"), calendar: calendar))
        XCTAssertTrue(store.canDeliverReminder(at: testDate("2026-06-02T08:00:00Z"), calendar: calendar))
        XCTAssertEqual(store.nextReminderDate(after: testDate("2026-06-01T22:59:00Z"), calendar: calendar),
                       testDate("2026-06-02T08:00:00Z"))
        XCTAssertEqual(store.readVerseCount, 0)
        XCTAssertEqual(store.automaticVerseOffset, 0)
        store.settings.quietHoursStartMinute = 12 * 60
        store.settings.quietHoursEndMinute = 13 * 60
        XCTAssertFalse(store.canDeliverReminder(at: testDate("2026-06-01T12:30:00Z"), calendar: calendar))
        XCTAssertTrue(store.canDeliverReminder(at: testDate("2026-06-01T13:00:00Z"), calendar: calendar))
        store.settings.quietHoursEndMinute = store.settings.quietHoursStartMinute
        XCTAssertTrue(store.canDeliverReminder(at: testDate("2026-06-01T12:30:00Z"), calendar: calendar))
        store.settings.remindersEnabled = false
        XCTAssertNil(store.nextReminderDate(after: testDate("2026-06-01T12:30:00Z"), calendar: calendar))
    }

    @MainActor
    func testSnoozePersistsOverlapsQuietHoursAndCanBeCancelled() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()
        let store = AppStore(library: library, defaults: defaults)
        let calendar = testCalendar()
        let now = testDate("2026-06-01T20:30:00Z")
        store.settings.quietHoursEnabled = true
        store.settings.quietHoursStartMinute = 21 * 60
        store.settings.quietHoursEndMinute = 22 * 60
        store.snooze(for: 3600, now: now)
        XCTAssertFalse(store.canDeliverReminder(at: now, calendar: calendar))
        XCTAssertEqual(store.reminderSuspensionEnd(at: now, calendar: calendar), testDate("2026-06-01T22:00:00Z"))
        XCTAssertEqual(store.nextReminderDate(after: now, calendar: calendar), testDate("2026-06-01T22:00:00Z"))
        let restored = AppStore(library: library, defaults: defaults)
        XCTAssertEqual(restored.snoozedUntil, testDate("2026-06-01T21:30:00Z"))
        XCTAssertTrue(restored.canDeliverReminder(at: testDate("2026-06-01T22:00:00Z"), calendar: calendar))
        restored.cancelSnooze()
        XCTAssertTrue(restored.canDeliverReminder(at: now, calendar: calendar))
        XCTAssertEqual(restored.nextReminderDate(after: now, calendar: calendar), now.addingTimeInterval(120))
        XCTAssertNil(AppStore(library: library, defaults: defaults).snoozedUntil)
    }

    @MainActor
    func testQuietHourEndHandlesSpringGapAndBothRepeatedHours() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        let calendar = testCalendar("America/Los_Angeles")
        store.settings.quietHoursEnabled = true
        store.settings.quietHoursStartMinute = 60
        store.settings.quietHoursEndMinute = 150
        XCTAssertEqual(
            store.reminderSuspensionEnd(at: testDate("2026-03-08T09:30:00Z"), calendar: calendar),
            testDate("2026-03-08T10:00:00Z")
        )
        store.settings.quietHoursStartMinute = 0
        store.settings.quietHoursEndMinute = 105
        XCTAssertEqual(
            store.reminderSuspensionEnd(at: testDate("2026-11-01T08:30:00Z"), calendar: calendar),
            testDate("2026-11-01T08:45:00Z")
        )
        XCTAssertEqual(
            store.reminderSuspensionEnd(at: testDate("2026-11-01T09:30:00Z"), calendar: calendar),
            testDate("2026-11-01T09:45:00Z")
        )
    }

    @MainActor
    func testMultipleBookmarksToggleIndependentlyAndPersistOrder() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = twoSurahLibrary()
        let store = AppStore(library: library, defaults: defaults)
        store.toggleBookmark(surahID: 1, verseID: 2)
        store.toggleBookmark(surahID: 2, verseID: 1)
        XCTAssertEqual(store.bookmarks, [VerseReference(surahID: 2, verseID: 1), VerseReference(surahID: 1, verseID: 2)])
        store.toggleBookmark(surahID: 1, verseID: 2)
        XCTAssertTrue(store.isBookmarked(surahID: 2, verseID: 1))
        XCTAssertFalse(store.isBookmarked(surahID: 1, verseID: 2))
        store.toggleBookmark(surahID: 99, verseID: 1)
        XCTAssertEqual(AppStore(library: library, defaults: defaults).bookmarks, [VerseReference(surahID: 2, verseID: 1)])
        store.removeBookmark(VerseReference(surahID: 2, verseID: 1))
        XCTAssertEqual(AppStore(library: library, defaults: defaults).bookmarks, [])
    }

    @MainActor
    func testReadingBackupRestoresPlansMarksAndBookmarksWithoutChangingPreferences() throws {
        let (sourceDefaults, sourceSuite) = makeDefaults()
        let (targetDefaults, targetSuite) = makeDefaults()
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            targetDefaults.removePersistentDomain(forName: targetSuite)
        }
        let library = twoSurahLibrary()
        let source = AppStore(library: library, defaults: sourceDefaults)
        source.startAutomaticReading()
        source.acknowledge(try XCTUnwrap(source.nextReminder()))
        source.startSurah(2)
        source.toggleBookmark(surahID: 1, verseID: 2)
        source.toggleBookmark(surahID: 2, verseID: 1)
        let target = AppStore(library: library, defaults: targetDefaults)
        target.settings.theme = .dark
        target.settings.language = .arabic
        target.settings.reminderAutoCloseSeconds = 30
        target.settings.quietHoursEnabled = true
        target.snooze(for: 1800, now: testDate("2026-06-01T12:00:00Z"))
        let previousSettings = target.settings
        let previousSnooze = target.snoozedUntil
        target.markRead(surahID: 1, verseID: 2)
        try target.importReadingBackup(source.exportReadingBackup())
        XCTAssertTrue(target.isRead(surahID: 1, verseID: 1))
        XCTAssertFalse(target.isRead(surahID: 1, verseID: 2))
        XCTAssertEqual(target.readVerseCount, 1)
        XCTAssertEqual(target.automaticVerseOffset, 1)
        XCTAssertEqual(target.selectedSurahID, 2)
        XCTAssertEqual(target.bookmarks, source.bookmarks)
        XCTAssertEqual(target.settings, previousSettings)
        XCTAssertEqual(target.snoozedUntil, previousSnooze)
        XCTAssertNil(target.lastReminder)
        let restored = AppStore(library: library, defaults: targetDefaults)
        XCTAssertEqual(restored.automaticNextReference, VerseReference(surahID: 1, verseID: 2))
        XCTAssertEqual(restored.bookmarks, source.bookmarks)
        XCTAssertEqual(restored.settings, previousSettings)
    }

    @MainActor
    func testInvalidBackupNeverMutatesExistingReadingState() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(library: twoSurahLibrary(), defaults: defaults)
        store.markRead(surahID: 1, verseID: 1)
        store.toggleBookmark(surahID: 2, verseID: 1)
        let before = try store.exportReadingBackup()
        let invalidBackups = [
            #"{"formatVersion":2,"readVerses":[],"automaticVerseOffset":0,"bookmarks":[]}"#,
            #"{"formatVersion":1,"readVerses":[{"surahID":99,"verseID":1}],"automaticVerseOffset":0,"bookmarks":[]}"#,
            #"{"formatVersion":1,"readVerses":[],"automaticVerseOffset":4,"bookmarks":[]}"#,
            #"{"formatVersion":1,"readVerses":[],"automaticVerseOffset":0,"selectedSurahID":99,"bookmarks":[]}"#,
            #"{"formatVersion":1,"readVerses":[],"automaticVerseOffset":0,"bookmarks":[{"surahID":1,"verseID":99}]}"#,
            "{broken JSON"
        ]
        for invalid in invalidBackups {
            XCTAssertThrowsError(try store.importReadingBackup(Data(invalid.utf8)))
            XCTAssertEqual(try store.exportReadingBackup(), before)
        }
    }
}

private func fourSurahLibrary() -> QuranLibrary {
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
            totalVerses: 2,
            verses: [
                Verse(id: 1, text: "الآية الثالثة"),
                Verse(id: 2, text: "الآية الرابعة")
            ]
        ),
        Surah(
            id: 3,
            name: "الثالثة",
            transliteration: "Third",
            type: "meccan",
            totalVerses: 1,
            verses: [Verse(id: 1, text: "الآية الخامسة")]
        ),
        Surah(
            id: 4,
            name: "الرابعة",
            transliteration: "Fourth",
            type: "medinan",
            totalVerses: 1,
            verses: [Verse(id: 1, text: "الآية السادسة")]
        )
    ])
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

private func testCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func testDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
