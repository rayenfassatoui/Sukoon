# Native redesign verification

## Implemented direction

Quiet, reading-first macOS surfaces: opaque ivory/stone in Light, readable charcoal-green in Dark, restrained accents, smaller headings, consistent borders/corners, and native navigation and controls. Quran fonts and full Arabic text remain the content, not interface decoration.

- Shared styling stays in `DesignSystem.swift`; no new UI framework or dependency.
- The welcome tour has two steps, shared preference controls, real font/reminder previews, Back/Skip/Finish, and Settings replay. Completion is separate from existing reading state and backup JSON. Existing installations are not forced through onboarding.
- Settings uses General, Reading & appearance, Reminders, Reading plans, and Data & updates. Existing startup, quiet-hour, snooze, reading-mode, backup, sizing, and update functions remain available.
- Reader search stays visible. Search and favourites open exact ayahs; small favourite/read actions precede long passages. Compact and wide navigation share the same reader identity and scroll position.
- Menu bar, reminders, Journey, favourites/empty states, and completion feedback use the same restrained hierarchy. Surah completion remains a nonactivating toast, not a confirmation dialog.

The `NSStatusItem`, `NSPopover`, nonactivating `NSPanel`, offline dataset, bundled fonts, `@Observable AppStore`, localization tables, reminder semantics, and compatible `bookmarks` backup field remain in place.

## Before / after

These are captures of the running app, with isolated demonstration preferences. Reading content and viewport sizes vary between scenarios; they are not pixel-matched mockups.

| Surface | Before | After |
| --- | --- | --- |
| Today | [Original workspace](../assets/screenshots/redesign-before-home.png) | [Reading-first workspace](../assets/screenshots/redesign-home.png) |
| Reader | [Original reader](../assets/screenshots/redesign-before-reader.png) | [Wide reader / exact 2:255](../assets/screenshots/redesign-reader-wide.png) · [Compact reader / same target](../assets/screenshots/redesign-reader-compact.png) |
| Settings | [Original long settings page](../assets/screenshots/redesign-before-settings.png) | [Grouped General settings](../assets/screenshots/redesign-settings-general.png) · [Reading preview](../assets/screenshots/redesign-settings.png) |

Additional native captures:

| Scenario | Evidence |
| --- | --- |
| Welcome tour | [English reading step](../assets/screenshots/redesign-onboarding.png) · [Reminder timing step](../assets/screenshots/redesign-onboarding-reminders.png) · [Arabic, independent Western Quran digits](../assets/screenshots/redesign-onboarding-arabic.png) |
| Arabic and large text | [Light settings / 54 pt](../assets/screenshots/redesign-settings-arabic.png) · [Compact reader / 2:282 at 54 pt](../assets/screenshots/redesign-reader-arabic-large.png) |
| Long chapter title | [Al-Mumtahanah at the compact minimum](../assets/screenshots/redesign-long-surah-name.png) |
| Collections | [Favourites](../assets/screenshots/redesign-favourites.png) · [Empty favourites](../assets/screenshots/redesign-favourites-empty.png) · [Journey](../assets/screenshots/redesign-journey.png) |
| Menu bar | [Arabic](../assets/screenshots/redesign-menu-bar.png) · [English with long reference and untruncated action](../assets/screenshots/redesign-menu-bar-english.png) |
| Reminders | [Real scheduled 112:4](../assets/screenshots/redesign-scheduled-reminder.png) · [Arabic fitted preview](../assets/screenshots/redesign-reminder-arabic.png) |
| Completion | [Nonactivating surah toast](../assets/screenshots/redesign-surah-success.png) · [Full-Quran completion sheet](../assets/screenshots/redesign-quran-complete.png) |

## Exercised in the running app

| Area | Observed result |
| --- | --- |
| Onboarding | New-install flow, Back/Continue/Skip/Finish and Settings replay exercised. Choices survived relaunch. Startup remained off; no login-item registration was performed. |
| Language and numerals | English with Arabic Quran digits, and Arabic with Western Quran digits. Arabic RTL settings, reader, onboarding and reminder controls were inspected through native AX and images. The onboarding step fraction keeps its order in RTL. |
| Reading | Direct searches for 2:255 and 2:282, repeated Return, search clearing and no-match state. Exact favourite jump to 2:255; save, remove, empty state and re-add. Manual mark persisted. |
| Long text | Amiri Quran at 32 and 54 pt; long 2:282 exposed its complete 1,189-character text through AX. Page-scrolling within it, widening and returning to compact retained the same passage. Al-Mumtahanah's full title remained visible. |
| Appearance | App-only Light, Dark and System choices exercised. No macOS appearance or accessibility setting was changed. |
| Main-window sizing | Requested 300 × 200 pt content was clamped to 680 × 520. Native frame minimum was 680 × 552 including its title bar. Wide 1200 × 760 and compact layouts retained exact 2:255; saved 920 × 700 and 820 × 640 frames survived relaunch. |
| Reminder sizing | A custom 480 × 320 panel survived relaunch. The real Fit to verse action restored automatic sizing, observed at 380 × 277 with the Arabic 54-point preview. |
| Reminder lifecycle | A real scheduled panel appeared with the main window closed while another isolated app remained frontmost. The panel was neither key nor main. Preview did not advance reading marks. |
| Surah continuation | Actual Read & continue on scheduled Al-Ikhlas 112:4 produced the quiet completion toast, followed by scheduled Al-Falaq 113:1. No workspace opened, and the other app retained focus. Explicit Open this ayah then opened exact 113:1. |
| Quran completion | A separate fixture held 6,235 real marks. Marking actual 114:6 in the reader produced the completion sheet and a 6,236/6,236 Journey. Closing the sheet retained completion. |
| Backup error | The real import flow rejected a version-999 JSON fixture. AX exposed “This backup version is not supported.” Existing 6,236 marks and favourite 2:255 remained intact. |
| Keyboard and AX | Native menu commands, Cmd-F, Return/repeated Return, clearing search, and named favourite, reader, preview and onboarding actions exercised. This is not a complete keyboard or VoiceOver audit. |

Selected native sizing/focus observations are retained in [design-window-evidence.json](design-window-evidence.json).

### Runtime defects corrected during verification

1. **The hosting controller reset the main-window minimum.** The workspace now declares one 680 × 520 content minimum, and `NSHostingController.sizingOptions = [.minSize]` propagates it to AppKit. Restored undersized frames are clamped; larger saved sizes are retained. Reminder/popover limits were not changed by this fix.
2. **Resizing drifted from 2:255 to 2:259.** The reader now uses one `ScrollPosition` for programmatic navigation and scroll preservation, rather than competing proxy/ID positioning. Exact-ayah and intra-ayah resize round trips were exercised after the change.
3. **Wide settings rows stacked unnecessarily.** Label/control layout now stacks only when its available content width requires it.
4. **Arabic onboarding reversed the step fraction.** Separate LTR fraction components retain the visual order while the grouped accessibility label remains localized.
5. **The popover truncated “Open Quran”.** Intrinsic sizing now protects the reference/actions so the existing horizontal/vertical fallback can work. The final release was rebuilt and inspected in English and Arabic.

## Build and regression tests

Executed with the full Xcode installation, without changing system-wide `xcode-select`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
swift Tools/Bundle.swift
```

- **30 tests passed, zero failures:** 23 AppStore, 1 localization, 2 library and 4 search tests.
- Durable onboarding regressions cover legacy-user preservation and interrupted/new onboarding choices plus completion persistence.
- The final popover-only layout correction was release-built and exercised in both languages; it did not change core logic.
- The existing packaging pipeline produces `build/Sukoon.app`, the arm64 ZIP and `SHA256SUMS`. The app is **ad-hoc signed, not notarized**. These redesign smoke checks preceded publication; release 1.3.0 uses the same pipeline with updated version/build metadata.

## Isolation and evidence limits

Smoke bundles used only `app.sukoon.design-smoke-before`, `app.sukoon.design-smoke-after` and `app.sukoon.design-smoke-completion`. The production `app.sukoon.mac` preferences and login-item registration were not used for testing. The full-completion and invalid-backup data were disposable fixtures.

Screen Recording was unavailable. Images therefore come from the running app's own native `NSWindow.contentView` through AppKit `cacheDisplay`, not from WindowServer screenshots. They contain real rendered SwiftUI/AppKit content, but do not establish desktop compositing, title-bar appearance or every native material/selection effect. Temporary app-local instrumentation also requested actual NSWindow resizes and pointed the native import picker at the isolated fixture directory. It did not replace reading, backup validation, scheduling or focus logic. No instrumentation is included in the delivered app.

Not claimed as verified:

- VoiceOver speech/navigation end-to-end or a formal contrast audit.
- Runtime changes to system Reduce Motion / Reduce Transparency; source uses the existing motion guard and opaque content surfaces, but those OS settings were deliberately left untouched.
- Physical pointer edge-drag resizing; actual AppKit sizing, minimum constraints, resize callbacks and persistence were exercised programmatically.
- Login-item registration or Developer ID notarization.

No launch of the delivered production bundle was used as a smoke shortcut: the release executable was exercised in isolated copies so personal progress remained untouched.
