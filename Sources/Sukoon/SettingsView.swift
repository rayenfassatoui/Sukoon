import AppKit
import SwiftUI
import Foundation
import SukoonCore

struct SettingsView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable var store: AppStore
    let navigation: AppNavigation
    let onPreview: () -> Void
    @State private var showingResetConfirmation = false
    @State private var services = AppServices()
    @State private var fonts = QuranFonts.shared

    private let intervalOptions = [30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
    private let menuBarAutoCloseOptions = [10, 15, 20]
    private let reminderAutoCloseOptions = [10, 15, 20, 30, 60]

    private var canPreview: Bool {
        switch store.settings.mode {
        case .surah:
            guard let surah = store.activeSurah else { return false }
            return store.nextUnreadVerse(in: surah.id) != nil
        case .automatic:
            return store.automaticNextReference != nil
        case .mixed, .ayah, .dua:
            return store.library.verseCount > 0
        }
    }

    private var planWarning: String? {
        switch store.settings.mode {
        case .surah:
            guard let surah = store.activeSurah else {
                return l10n.text("Select a surah before chosen-surah reminders can begin.", table: "Preferences")
            }
            guard store.nextUnreadVerse(in: surah.id) == nil else { return nil }
            return l10n.format(
                "%@ is complete. Choose another surah to continue chosen-surah reminders.",
                l10n.surahName(surah),
                table: "Preferences"
            )
        case .automatic where store.isAutomaticComplete:
            return l10n.text("Your automatic Quran reading is complete.", table: "Preferences")
        case .mixed, .ayah, .dua, .automatic:
            return nil
        }
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader

                settingsSection(l10n.text("Language", table: "Preferences"), symbol: "globe") {
                    SettingsRow(
                        title: l10n.text("App language", table: "Preferences"),
                        detail: l10n.text(
                            "Arabic uses a right-to-left layout. Your language choice is saved automatically.",
                            table: "Preferences"
                        )
                    ) {
                        Picker(
                            l10n.text("App language", table: "Preferences"),
                            selection: $store.settings.language
                        ) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.nativeName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .id(store.settings.language)
                        .accessibilityIdentifier("settings.language")
                        .help(l10n.text("Choose the app language", table: "Preferences"))
                    }

                    Divider()

                    SettingsRow(
                        title: l10n.text("Ayah numbers", table: "Preferences"),
                        detail: l10n.text(
                            "The digit style for ayah numbers and Quran references is saved separately from the app language.",
                            table: "Preferences"
                        )
                    ) {
                        Picker(
                            l10n.text("Ayah numbers", table: "Preferences"),
                            selection: $store.settings.quranNumberStyle
                        ) {
                            ForEach(QuranNumberStyle.allCases) { style in
                                Text(l10n.text(style.title, table: "Preferences")).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .id(store.settings.language)
                        .accessibilityIdentifier("settings.ayahNumbers")
                        .help(l10n.text("Choose the digits for ayah numbers and Quran references", table: "Preferences"))
                    }
                }

                startupSection

                settingsSection(l10n.text("Menu bar", table: "Preferences"), symbol: "menubar.rectangle") {
                    SettingsRow(
                        title: l10n.text("Auto-close after", table: "Preferences"),
                        detail: l10n.text(
                            "The menu bar popover closes automatically after this delay. Default: 10 seconds.",
                            table: "Preferences"
                        )
                    ) {
                        Picker(
                            l10n.text("Auto-close after", table: "Preferences"),
                            selection: $store.settings.menuBarAutoCloseSeconds
                        ) {
                            ForEach(menuBarAutoCloseOptions, id: \.self) { seconds in
                                Text(l10n.format("%@ sec", l10n.number(seconds), table: "Preferences"))
                                    .tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .id(store.settings.language)
                        .accessibilityIdentifier("settings.menuBarAutoClose")
                        .help(l10n.text("Choose when the menu bar popover closes", table: "Preferences"))
                    }
                }

                settingsSection(l10n.text("Reminders", table: "Preferences"), symbol: "bell") {
                    SettingsRow(
                        title: l10n.text("Quran reminders", table: "Preferences"),
                        detail: l10n.text(
                            "Allow Sukoon to offer a quiet reading moment at your chosen interval.",
                            table: "Preferences"
                        )
                    ) {
                        Toggle("", isOn: $store.settings.remindersEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(l10n.text("Quran reminders", table: "Preferences"))
                            .help(l10n.text("Turn Quran reminders on or off", table: "Preferences"))
                    }

                    Divider()

                    SettingsRow(
                        title: l10n.text("Interval", table: "Preferences"),
                        detail: l10n.text(
                            store.settings.remindersEnabled
                                ? "Sukoon schedules one reminder at a time—never a catch-up burst."
                                : "Your interval is kept while reminders are paused.",
                            table: "Preferences"
                        )
                    ) {
                        Picker(
                            l10n.text("Interval", table: "Preferences"),
                            selection: $store.settings.intervalSeconds
                        ) {
                            ForEach(intervalOptions, id: \.self) { seconds in
                                Text(intervalLabel(seconds)).tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .id(store.settings.language)
                        .accessibilityIdentifier("settings.interval")
                        .help(l10n.text("Choose how often reminders appear", table: "Preferences"))
                    }

                    Divider()

                    reminderTimingControls

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.text("Reminder content", table: "Preferences"))
                            .font(.headline)
                        Picker(
                            l10n.text("Reminder content", table: "Preferences"),
                            selection: $store.settings.mode
                        ) {
                            ForEach(ReminderMode.allCases) { mode in
                                Text(l10n.text(mode.title)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 280, alignment: .leading)
                        .id(store.settings.language)
                        .help(l10n.text("Choose the reminder content", table: "Preferences"))

                        Text(modeExplanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let planWarning {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(palette.gold)
                                    .accessibilityHidden(true)
                                Text(planWarning)
                                    .font(.callout.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                if store.settings.mode == .surah {
                                    Button(l10n.text("Choose in reader", table: "Preferences")) {
                                        navigation.section = .quran
                                    }
                                    .buttonStyle(.bordered)
                                    .help(l10n.text("Open the Quran reader", table: "Preferences"))
                                }
                            }
                            .padding(12)
                            .background(
                                palette.gold.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                        }
                    }

                    Divider()

                    automaticReadingSection

                    Divider()

                    chosenSurahSection

                    Divider()

                    SettingsRow(
                        title: l10n.text("Automatic delivered progress", table: "Preferences"),
                        detail: autoAdvanceExplanation
                    ) {
                        Toggle("", isOn: $store.settings.autoAdvance)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(
                                l10n.text("Automatic delivered progress", table: "Preferences")
                            )
                            .help(
                                l10n.text(
                                    "Turn automatic delivered progress on or off",
                                    table: "Preferences"
                                )
                            )
                    }
                }

                settingsSection(l10n.text("Reading", table: "Preferences"), symbol: "textformat.size") {
                    SettingsRow(
                        title: l10n.text("Quran font", table: "Preferences"),
                        detail: l10n.text("Choose a mushaf font for ayahs in every view. Bundled fonts work offline.", table: "Preferences")
                    ) {
                        HStack(spacing: 8) {
                            Picker(l10n.text("Quran font", table: "Preferences"), selection: Binding(
                                get: { fonts.resolvedFontName(store.settings.quranFontName) },
                                set: { store.settings.quranFontName = $0 }
                            )) {
                                ForEach(fonts.options) { font in
                                    Text(font.name).tag(font.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220)
                            .accessibilityIdentifier("settings.quranFont")
                            Button {
                                fonts.refreshInstalledFonts()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(l10n.text("Refresh installed fonts", table: "Preferences"))
                            .accessibilityLabel(l10n.text("Refresh installed fonts", table: "Preferences"))
                            .accessibilityIdentifier("settings.refreshFonts")
                        }
                    }
                    if fonts.resolvedFontName(store.settings.quranFontName) != store.settings.quranFontName {
                        Label(
                            l10n.text("The saved font is unavailable. Geeza Pro is being used.", table: "Preferences"),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    if !fonts.registrationErrors.isEmpty {
                        Text(l10n.format(
                            "Some fonts could not be loaded: %@",
                            fonts.registrationErrors.joined(separator: "\n"),
                            table: "Preferences"
                        ))
                        .font(.callout)
                        .foregroundStyle(.red)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.text("Arabic text size", table: "Preferences"))
                                    .font(.headline)
                                Text(
                                    l10n.format(
                                        "%@ pt",
                                        l10n.number(Int(store.settings.arabicFontSize)),
                                        table: "Preferences"
                                    )
                                )
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Slider(value: $store.settings.arabicFontSize, in: 22...54, step: 2)
                                .frame(width: 260)
                                .accessibilityLabel(
                                    l10n.text("Arabic text size", table: "Preferences")
                                )
                                .accessibilityValue(
                                    l10n.format(
                                        "%@ pt",
                                        l10n.number(Int(store.settings.arabicFontSize)),
                                        table: "Preferences"
                                    )
                                )
                                .help(l10n.text("Adjust the Quran text size", table: "Preferences"))
                        }

                        if let sample = store.library.surah(1)?.verses.first {
                            ArabicText(sample.text, size: store.settings.arabicFontSize)
                                .padding(12)
                                .background(
                                    palette.raisedSurface,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                    }
                }

                settingsSection(l10n.text("Appearance", table: "Preferences"), symbol: "paintpalette") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.text("Theme", table: "Preferences"))
                            .font(.headline)
                        Picker(
                            l10n.text("Theme", table: "Preferences"),
                            selection: $store.settings.theme
                        ) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(l10n.text(theme.title)).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        .id(store.settings.language)
                        .help(l10n.text("Choose the app theme", table: "Preferences"))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.text("Accent", table: "Preferences"))
                            .font(.headline)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 118), spacing: 12)],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(AccentTheme.allCases) { accent in
                                AccentChoice(
                                    accent: accent,
                                    selected: store.settings.accent == accent,
                                    action: { store.settings.accent = accent }
                                )
                            }
                        }
                    }
                }

                updatesSection

                backupSection

                settingsSection(
                    l10n.text("Data & sources", table: "Preferences"),
                    symbol: "info.circle"
                ) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(l10n.text("Quran text attribution", table: "Preferences"))
                            .font(.headline)
                        Text(
                            l10n.text(
                                "The bundled Quran dataset is quran-json 3.1.2. Its Uthmani text source is The Noble Qur'an Encyclopedia, and its transliteration source is Tanzil. The dataset remains available offline in Sukoon.",
                                table: "Preferences"
                            )
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 16) {
                                Link(
                                    l10n.text("Dataset project", table: "Preferences"),
                                    destination: SourceLinks.project
                                )
                                Link(
                                    l10n.text("Pinned dataset", table: "Preferences"),
                                    destination: SourceLinks.dataset
                                )
                                Link("QuranEnc", destination: QuranAttribution.quranTextSourceURL)
                            }
                            HStack(spacing: 16) {
                                Link("Tanzil", destination: QuranAttribution.transliterationSourceURL)
                                Link(
                                    l10n.text("CC BY-SA 4.0 license", table: "Preferences"),
                                    destination: SourceLinks.license
                                )
                            }
                        }
                        .font(.callout)
                    }

                    Divider()

                    SettingsRow(
                        title: l10n.text("Reset Quran progress", table: "Preferences"),
                        detail: l10n.text(
                            "Removes all marked verses, both reading positions, and your favourites. Appearance and reminder preferences are preserved.",
                            table: "Preferences"
                        )
                    ) {
                        Button(
                            l10n.text("Reset progress", table: "Preferences"),
                            role: .destructive
                        ) {
                            showingResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .help(l10n.text("Reset Quran progress", table: "Preferences"))
                    }

                    if let error = store.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(
            colorScheme == .dark
                ? Color(red: 0.055, green: 0.065, blue: 0.06)
                : palette.canvas
        )
        .onAppear { services.refreshStartupStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            services.refreshStartupStatus()
        }
        .confirmationDialog(
            l10n.text("Reset all Quran progress?", table: "Preferences"),
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                l10n.text("Reset progress", table: "Preferences"),
                role: .destructive
            ) {
                store.resetProgress()
            }
            Button(l10n.text("Cancel", table: "Preferences"), role: .cancel) {}
        } message: {
            Text(
                l10n.text(
                    "This cannot be undone. Your marked verses, automatic and chosen-surah positions, and favourites will be removed.",
                    table: "Preferences"
                )
            )
        }
    }

    private var settingsHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                settingsTitle
                Spacer(minLength: 12)
                previewButton
            }
            VStack(alignment: .leading, spacing: 12) {
                settingsTitle
                previewButton
            }
        }
    }

    private var settingsTitle: some View {
        SukoonSectionTitle(
            l10n.text("Settings", table: "Preferences"),
            eyebrow: l10n.text("Make Sukoon yours", table: "Preferences"),
            detail: l10n.text(
                "Shape the pace, appearance, and way reminders become reading progress.",
                table: "Preferences"
            )
        )
    }

    private var previewButton: some View {
        Button(action: onPreview) {
            Label(l10n.text("Preview reminder", table: "Preferences"), systemImage: "play.circle")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canPreview)
        .help(l10n.text(
            canPreview ? "Show a preview without changing progress" : "No reminder content is available to preview.",
            table: "Preferences"
        ))
    }

    private var startupSection: some View {
        settingsSection(l10n.text("Startup", table: "Preferences"), symbol: "power") {
            SettingsRow(
                title: l10n.text("Run at startup", table: "Preferences"),
                detail: l10n.text("Open Sukoon automatically when you log in to your Mac.", table: "Preferences")
            ) {
                Toggle("", isOn: Binding(
                    get: { services.launchAtLoginEnabled },
                    set: { services.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(l10n.text("Run at startup", table: "Preferences"))
                .accessibilityIdentifier("settings.launchAtLogin")
            }
            if services.requiresStartupApproval {
                Label(
                    l10n.text("Approve Sukoon in Login Items to finish enabling startup.", table: "Preferences"),
                    systemImage: "exclamationmark.circle"
                )
                .foregroundStyle(palette.gold)
            }
            Button(l10n.text("Open Login Items", table: "Preferences")) {
                services.openLoginItemSettings()
            }
            .buttonStyle(.bordered)
            if let error = services.startupError {
                Text(l10n.format("Startup could not be changed: %@", error, table: "Preferences"))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var reminderTimingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(
                title: l10n.text("Reminder auto-close", table: "Preferences"),
                detail: l10n.text("How long reminder and preview panels stay open. Default: 10 seconds.", table: "Preferences")
            ) {
                Picker(l10n.text("Reminder auto-close", table: "Preferences"), selection: $store.settings.reminderAutoCloseSeconds) {
                    ForEach(reminderAutoCloseOptions, id: \.self) { seconds in
                        Text(l10n.format("%@ sec", l10n.number(seconds), table: "Preferences")).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
                .accessibilityIdentifier("settings.reminderAutoClose")
            }

            Divider()

            SettingsRow(
                title: l10n.text("Reminder size", table: "Preferences"),
                detail: l10n.text("Drag the popup edges to resize it. Your size is saved; fit it to the verse to remove extra space.", table: "Preferences")
            ) {
                Button(l10n.text("Fit to verse", table: "Preferences")) {
                    var settings = store.settings
                    settings.reminderPanelWidth = nil
                    settings.reminderPanelHeight = nil
                    store.settings = settings
                }
                .buttonStyle(.bordered)
                .disabled(store.settings.reminderPanelWidth == nil && store.settings.reminderPanelHeight == nil)
                .accessibilityIdentifier("settings.fitReminder")
            }

            Divider()

            SettingsRow(
                title: l10n.text("Quiet hours", table: "Preferences"),
                detail: l10n.text("Pause scheduled reminders during these local times. Matching times mean no quiet interval.", table: "Preferences")
            ) {
                Toggle("", isOn: $store.settings.quietHoursEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(l10n.text("Quiet hours", table: "Preferences"))
                    .accessibilityIdentifier("settings.quietHours")
            }
            HStack(spacing: 24) {
                DatePicker(
                    l10n.text("From", table: "Preferences"),
                    selection: quietTimeBinding(\.quietHoursStartMinute),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("settings.quietHoursStart")
                DatePicker(
                    l10n.text("Until", table: "Preferences"),
                    selection: quietTimeBinding(\.quietHoursEndMinute),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("settings.quietHoursEnd")
            }
            .disabled(!store.settings.quietHoursEnabled)

            Divider()

            SettingsRow(
                title: l10n.text("Snooze reminders", table: "Preferences"),
                detail: l10n.text("Pause temporarily; reminders resume automatically.", table: "Preferences")
            ) {
                HStack {
                    Menu(l10n.text("Snooze reminders", table: "Preferences")) {
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button(l10n.format("For %@ minutes", l10n.number(minutes))) {
                                store.snooze(for: minutes * 60)
                            }
                        }
                    }
                    .disabled(!store.settings.remindersEnabled)
                    .accessibilityIdentifier("settings.snooze")
                    if let deadline = store.snoozedUntil, deadline > Date() {
                        Button(l10n.text("Cancel snooze")) { store.cancelSnooze() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("settings.cancelSnooze")
                    }
                }
            }
            if let end = store.reminderSuspensionEnd() {
                Text(l10n.format(
                    "Reminders resume %@.",
                    end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(l10n.locale))
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func quietTimeBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding {
            let minute = min(max(store.settings[keyPath: keyPath], 0), 1439)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            return calendar.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60))!
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.settings[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private var updatesSection: some View {
        settingsSection(l10n.text("Updates", table: "Preferences"), symbol: "arrow.down.circle") {
            SettingsRow(
                title: l10n.text("Check for updates", table: "Preferences"),
                detail: l10n.text("Contacts GitHub only when you check. Sukoon otherwise stays offline.", table: "Preferences")
            ) {
                Button(l10n.text(
                    services.updateState == .checking ? "Checking…" : "Check for updates",
                    table: "Preferences"
                )) {
                    Task { await services.checkForUpdates() }
                }
                .buttonStyle(.bordered)
                .disabled(services.updateState == .checking)
                .accessibilityIdentifier("settings.checkUpdates")
            }
            if let version = services.currentVersion {
                Text(l10n.format("Installed version: %@", version, table: "Preferences"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            switch services.updateState {
            case .idle, .checking:
                EmptyView()
            case .upToDate:
                Label(l10n.text("You are up to date.", table: "Preferences"), systemImage: "checkmark.circle")
                    .foregroundStyle(palette.success)
            case let .updateAvailable(version, _):
                HStack {
                    Text(l10n.format("Sukoon %@ is available.", version, table: "Preferences"))
                    Spacer()
                    Button(l10n.text("Open release page", table: "Preferences")) { services.openRelease() }
                        .buttonStyle(.borderedProminent)
                }
            case let .failed(failure):
                Text(failure.localizedMessage(l10n))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var backupSection: some View {
        settingsSection(l10n.text("Reading backup", table: "Preferences"), symbol: "externaldrive") {
            Text(l10n.text(
                "Save or restore your read marks, both reading positions and favourites. Other preferences stay unchanged.",
                table: "Preferences"
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Button(l10n.text("Export reading progress")) {
                    services.exportReadingProgress(from: store, localization: l10n)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.exportProgress")
                Button(l10n.text("Import reading progress")) {
                    services.importReadingProgress(into: store, localization: l10n)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.importProgress")
            }
            switch services.readingTransferState {
            case .idle, .cancelled:
                EmptyView()
            case .exported:
                Label(l10n.text("Reading progress exported.", table: "Preferences"), systemImage: "checkmark.circle")
                    .foregroundStyle(palette.success)
            case .imported:
                Label(l10n.text("Reading progress imported.", table: "Preferences"), systemImage: "checkmark.circle")
                    .foregroundStyle(palette.success)
            case let .failed(error):
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var automaticReadingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.text("Automatic Quran", table: "Preferences"))
                        .font(.headline)
                    Text(
                        l10n.text(
                            "Read the complete Quran in order from a separately saved position.",
                            table: "Preferences"
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Button(
                    l10n.text(
                        store.automaticVerseOffset == 0 ? "Start automatic reading" : "Resume automatic reading",
                        table: "Preferences"
                    )
                ) {
                    store.startAutomaticReading()
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isAutomaticComplete)
            }

            if store.isAutomaticComplete {
                Label(
                    l10n.text("Complete — all Quran verses were acknowledged in order.", table: "Preferences"),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.success)
            } else if let reference = store.automaticNextReference,
                      let surah = store.automaticSurah {
                Text(
                    l10n.format(
                        "Saved next position: %@ · %@",
                        l10n.surahName(surah),
                        l10n.reference(reference),
                        table: "Preferences"
                    )
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.accent)
            }
        }
        .padding(16)
        .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chosenSurahSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.text("Chosen-surah reading", table: "Preferences"))
                .font(.headline)
            Text(
                l10n.text(
                    "Choose one surah for its own reminders and unread-verse progress. This does not change your automatic Quran position.",
                    table: "Preferences"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let surah = store.activeSurah {
                    Text(l10n.surahName(surah))
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 12)
                    if store.settings.mode != .surah {
                        Button(l10n.text("Use chosen surah", table: "Preferences")) {
                            store.startSurah(surah.id)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text(l10n.text("No surah chosen", table: "Preferences"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                }
                Button(l10n.text("Choose in reader", table: "Preferences")) {
                    navigation.section = .quran
                }
                .buttonStyle(.bordered)
                .help(l10n.text("Open the Quran reader", table: "Preferences"))
            }
        }
        .padding(16)
        .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var modeExplanation: String {
        let source: String
        switch store.settings.mode {
        case .mixed:
            source = "A varied rotation of Quran verses and sourced Quranic duas. It does not change reading-plan progress."
        case .ayah:
            source = "Quran verses from across the full text. Random ayahs do not change reading-plan progress."
        case .dua:
            source = "Authentic supplications drawn from complete Quran verses, with their source references."
        case .surah:
            source = "The next unread verse from your chosen surah, in order."
        case .automatic:
            source = "The next verse in your saved full-Quran sequence, without changing your chosen surah."
        }
        return l10n.text(source, table: "Preferences")
    }

    private var autoAdvanceExplanation: String {
        let source = store.settings.autoAdvance
            ? "For chosen-surah and automatic Quran reminders, the delivered verse advances after its real panel appears. Previews never count. Reminder panels close after %@ seconds."
            : "For chosen-surah and automatic Quran reminders, press Read & continue to confirm the verse. An unconfirmed verse repeats after the panel closes in %@ seconds."
        return l10n.format(source, l10n.number(store.settings.reminderAutoCloseSeconds), table: "Preferences")
    }

    private func intervalLabel(_ seconds: Int) -> String {
        if seconds < 3600 {
            let subMinute = seconds < 60
            return l10n.format(
                subMinute ? "Every %@ sec" : "Every %@ min",
                l10n.number(subMinute ? seconds : seconds / 60),
                table: "Preferences"
            )
        }
        return l10n.text(
            seconds == 3600 ? "Every hour" : "Every 2 hours",
            table: "Preferences"
        )
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.accent)
            content()
        }
        .sukoonCard(padding: 16)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String
    let trailing: Trailing

    init(title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                text
                trailing
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                text
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccentChoice: View {
    @Environment(\.sukoonLocalization) private var l10n
    let accent: AccentTheme
    let selected: Bool
    let action: () -> Void

    private var color: Color {
        Palette(accent: accent).accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 17, height: 17)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(l10n.text(accent.title))
                    .font(.callout.weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                selected ? color.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selected ? color.opacity(0.55) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.text(accent.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(
            l10n.format(
                "Use %@ accent",
                l10n.text(accent.title),
                table: "Preferences"
            )
        )
    }
}

private enum SourceLinks {
    static let project = URL(string: "https://github.com/risan/quran-json/tree/v3.1.2")!
    static let dataset = URL(string: "https://cdn.jsdelivr.net/npm/quran-json@3.1.2/dist/quran.json")!
    static let license = URL(string: "https://raw.githubusercontent.com/risan/quran-json/v3.1.2/LICENSE.txt")!
}
