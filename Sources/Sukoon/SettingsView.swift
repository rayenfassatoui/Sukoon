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

    private let intervalOptions = [30, 120, 300, 600, 900, 1800, 3600, 7200]

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
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SukoonSectionTitle(
                        l10n.text("Settings", table: "Preferences"),
                        eyebrow: l10n.text("Make Sukoon yours", table: "Preferences"),
                        detail: l10n.text(
                            "Shape the pace, appearance, and way reminders become reading progress.",
                            table: "Preferences"
                        )
                    )
                    Spacer(minLength: 24)
                    Button(action: onPreview) {
                        Label(
                            l10n.text("Preview reminder", table: "Preferences"),
                            systemImage: "play.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canPreview)
                    .help(
                        l10n.text(
                            canPreview
                                ? "Show a preview without changing progress"
                                : "No reminder content is available to preview.",
                            table: "Preferences"
                        )
                    )
                }

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
                        .help(l10n.text("Choose how often reminders appear", table: "Preferences"))
                    }

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
                    VStack(alignment: .leading, spacing: 14) {
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
                                .padding(18)
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
                            "Removes all marked verses, both reading positions, and your bookmark. Appearance and reminder preferences are preserved.",
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
            .padding(.horizontal, 38)
            .padding(.top, 38)
            .padding(.bottom, 48)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(
            colorScheme == .dark
                ? Color(red: 0.055, green: 0.065, blue: 0.06)
                : palette.canvas
        )
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
                    "This cannot be undone. Your marked verses, automatic and chosen-surah positions, and bookmark will be removed.",
                    table: "Preferences"
                )
            )
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
            ? "For chosen-surah and automatic Quran reminders, the delivered verse advances after its real panel appears. Previews never count. Reminder panels close after ten seconds."
            : "For chosen-surah and automatic Quran reminders, press Read & continue to confirm the verse. An unconfirmed verse repeats after the panel closes in ten seconds."
        return l10n.text(source, table: "Preferences")
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
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.accent)
            content()
        }
        .sukoonCard(padding: 24)
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
            HStack(alignment: .center, spacing: 24) {
                text
                trailing
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 12) {
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
