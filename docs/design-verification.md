# Native redesign verification

## Implemented direction

Quiet, reading-first macOS surfaces: opaque ivory/stone in Light, readable charcoal-green in Dark, restrained accents, smaller headings, consistent borders/corners, and native navigation and controls. Quran fonts and full Arabic text remain the content, not interface decoration.

- Shared styling stays in `DesignSystem.swift`; no additional UI framework.
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

## Font selection correction — local build 1.3.1

The font-switching failure was reported on another Mac. Its exact OS/font environment was not available here; the old Amiri selection did render locally. The correction removes reliance on global installed-font enumeration and a second SwiftUI name lookup for the six bundled faces, rather than asking users to install those fonts.

- `QuranFonts` retains descriptors from the actual packaged font files and adds those faces to the catalogue independently of installed-font enumeration. Rendering and reminder measurement use the same concrete CoreText face. Saved PostScript identifiers, fallback warnings, font files and licenses are unchanged.
- The shared Settings/onboarding chooser stays open while selecting fonts. Its real Quran sample changes immediately, and each choice is saved through `AppStore`; Done only closes it. Bundled choices are identified as **Included with Sukoon**.
- Native buttons expose font names and selection state. The chooser has an opaque themed surface, explicit RTL layout, and a scrollable preview for larger sizes.

| Check | Observed result |
| --- | --- |
| No preinstalled bundled fonts | All six faces resolved to files inside the packaged app and shaped Arabic glyphs. None of those six faces was installed before process registration. |
| Empty installed-font enumeration | A temporary, probe-only override returned an empty available-name list. All six bundled choices still resolved and shaped Arabic; refresh retained them. No override is shipped. |
| Live selection | All six bundled choices were selected through the running app's native AX buttons. The chooser remained open, the sample changed, and each PostScript name was persisted immediately. |
| Applied outside the chooser | Nastaleeq rendered in the reader and a fitted reminder preview; no extra font installation was performed. |
| Languages and size | English/Light at 38 pt and Arabic/Dark at 54 pt inspected. Arabic chooser controls and labels follow RTL; Quran references retained independently chosen Western digits. |
| Onboarding | The replayed tour opened the same chooser and applied Old Madina without resetting preferences. |
| Relaunch and refresh | Old Madina, 54 pt, Arabic UI and Western digits survived a real quit/relaunch. The isolated fixture's marked 1:1, favourite 2:255 and automatic offset 3 remained intact. Refresh also retained the later Amiri choice. |
| Build | 30 core tests passed with zero failures. The final UI corrections were release-built through `Tools/Bundle.swift`, producing version 1.3.1, build 5. |

[English live preview](../assets/screenshots/font-picker-english.png) · [Arabic large-text live preview](../assets/screenshots/font-picker-arabic.png) · [Selected font in the reader](../assets/screenshots/font-picker-reader.png).

Native smoke preferences used only `app.sukoon.font-smoke`. Captures use the app-local method described above because Screen Recording remained unavailable. Native AX actions were exercised, but complete keyboard/VoiceOver navigation is not claimed. Validation ran on macOS 27, not the reporting user's physical Mac. No personal reading data, system font installation, login items or system accessibility settings were changed. This correction is included in 1.4.0 rather than published as a separate 1.3.1 release.

## Signed in-app updates — 1.4.0

`AppServices` owns discovery and one Sparkle 2.10.0 installation session. The native workspace notice and menu-bar entry share that owner; Settings retains manual checking. Discovery does not open a window. Downloading, authenticated extraction, installation and relaunch start only after **Download & Install**. Packaging remains in `Tools/Bundle.swift`; the public signing key is pinned and private signing material stays outside the checkout.

| Scenario | Observed result |
| --- | --- |
| Real GitHub discovery | A launch-time request against the public latest-release endpoint completed without pressing Check. Installed 1.4.0 was correctly reported as up to date against the public 1.3.0 release. With the workspace closed, another app remained frontmost and no workspace window appeared. |
| Newer release | The isolated old-version fixture discovered a newer release automatically. The notice offered Download & Install, Open GitHub release and dismissal. Dismiss/restore and the actual menu-bar App update action worked. |
| Real download and cancellation | Sparkle streamed the actual fixture ZIP. Downloading status and Cancel appeared; Cancel returned to the available-update state without changing the old bundle version or reading data. |
| Invalid signature | An intentionally invalid Ed25519 signature was rejected before installation. The old version remained installed; a persistent installation error and GitHub fallback appeared. Pressing the fallback handed off to the browser. |
| Valid signed installation | Sparkle downloaded, authenticated, extracted and replaced the app at the same isolated path, then restarted it. The process identity changed and the running bundle advanced from fixture 1.2.9/build 3 to 1.3.0/build 4. Actual Settings showed the new installed version and up-to-date state. |
| State preservation | Before/after snapshots matched exactly: marked 1:1, favourite 2:255, selected surah 112, automatic offset 3, Amiri Quran at 38 pt, Arabic UI, Western Quran digits, reminder settings and other recorded preferences. The saved 680 × 520 content size survived the update/relaunch. |
| Incomplete release and HTTP failure | Missing appcast assets produced a manual-download error without starting an installer. A real HTTP 503 response produced a localized Settings error and GitHub fallback. |
| Layout and AX | English/Light at 900 × 680, Arabic/Light and English/Dark at 680 × 520 inspected through native AX and rendered images. Named install, cancel, fallback and dismiss actions were exercised. A parent identifier that incorrectly propagated to all notice buttons was removed; the final build exposes distinct `updates.install`, `updates.release` and `updates.dismiss` identifiers. |
| Release packaging | Debug/release compilation and all 30 core tests passed. The final release was rebuilt without warnings. Full nested Sparkle signing and strict code-signature verification passed; the generated ZIP's Ed25519 signature was independently verified against the pinned key. |
| Publisher safety | A 0644 private-key file and a separate, valid-but-mismatched 0600 key were rejected. App metadata, executable, ZIP and existing appcast hashes stayed unchanged. A build without a signing-key option removed the stale appcast; a subsequent signed build regenerated the final 1.4.0/build 6 feed. |

[Available update / Dark](../assets/screenshots/updater-available-dark.png) · [Arabic / compact](../assets/screenshots/updater-available-arabic.png) · [Downloading](../assets/screenshots/updater-downloading.png) · [Installation error](../assets/screenshots/updater-install-error.png) · [Installed version after relaunch](../assets/screenshots/updater-installed-settings.png).

These update captures use **local fixture versions**, not a newly published GitHub release. The running test copies used only `app.sukoon.update-smoke`. A temporary, app-local URL protocol redirected the official release URLs to a loopback HTTP fixture server, serving a genuinely signed ZIP through the unchanged production installer. It did not replace Sparkle's signature verification, extraction, app replacement or relaunch. No fixture hooks, test domain, injected library or private key are included in the delivered app.

The computer helper reported a closed session. Native AX actions and the app-local AppKit capture method described above were used as the fallback; browser page contents and WindowServer rendering were not audited. The 24-hour check interval is configured but was not tested by waiting a full day. Installation requiring administrator approval, read-only/translocated installs, delayed-quit recovery, other physical Macs, VoiceOver speech, and Developer ID notarization were not exercised. Personal progress, login items and system accessibility/appearance settings were not changed.

These smoke checks were performed before the release-publishing step. Publishing instructions and the one-time manual upgrade requirement for pre-updater versions are in the [README](../README.md#publishing-signed-in-app-updates).

