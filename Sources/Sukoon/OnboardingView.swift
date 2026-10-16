import SwiftUI
import SukoonCore

struct OnboardingView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable private var store: AppStore
    private let onPreview: () -> Void
    private let onFinish: () -> Void
    @State private var step: Step = .reading

    init(store: AppStore, onPreview: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.store = store
        self.onPreview = onPreview
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)

            Divider()

            ViewThatFits(in: .vertical) {
                stepContent
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    stepContent
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: 480)
            .id(step)

            Divider()
            actions
                .padding(16)
        }
        .frame(minWidth: 440, idealWidth: 560, maxWidth: 620)
        .background(palette.canvas)
        .controlSize(.small)
        .presentationSizing(.fitted)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("onboarding")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(l10n.number(step == .reading ? 1 : 2))
                Text(verbatim: "/")
                Text(l10n.number(2))
            }
                .environment(\.layoutDirection, .leftToRight)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(l10n.format(
                    "Step %@ of %@",
                    l10n.number(step == .reading ? 1 : 2),
                    l10n.number(2),
                    table: "Preferences"
                ))
                .accessibilityIdentifier("onboarding.step")
            Text(l10n.text(step == .reading ? "Welcome to Sukoon" : "A gentle reading rhythm", table: "Preferences"))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(l10n.text(
                step == .reading
                    ? "Read the complete Quran offline from your menu bar. Make it comfortable for you."
                    : "Choose when reminders appear and how long they stay. Your current choices are kept.",
                table: "Preferences"
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .reading:
                VStack(alignment: .leading, spacing: 12) {
                    LanguagePreferencesControls(store: store)
                    Divider()
                    QuranReadingPreferences(store: store)
                }
                .sukoonCard(padding: 16)
            case .reminders:
                remindersStep
            }
        }
        .padding(20)
    }

    private var remindersStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ReminderSchedulePreferences(store: store)
                Divider()
                SettingsRow(
                    title: l10n.text("Reminder content", table: "Preferences"),
                    detail: l10n.text("Reading plans and quiet hours are available in Settings.", table: "Preferences")
                ) {
                    Picker(l10n.text("Reminder content", table: "Preferences"), selection: $store.settings.mode) {
                        ForEach(ReminderMode.allCases) { mode in
                            Text(l10n.text(mode.title)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .id(store.settings.language)
                    .frame(minWidth: 140, idealWidth: 180, maxWidth: 260)
                    .accessibilityIdentifier("onboarding.reminderMode")
                }
            }
            .sukoonCard(padding: 16)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onPreview) {
                    Label(l10n.text("Preview reminder", table: "Preferences"), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!canPreview)
                .help(l10n.text("Show a preview without changing progress", table: "Preferences"))
                .accessibilityIdentifier("onboarding.preview")
                Text(l10n.text(
                    canPreview
                        ? "This opens a real reminder without changing your reading progress."
                        : "No reminder content is available to preview. Choose another content mode or set a reading plan in Settings.",
                    table: "Preferences"
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(l10n.text(
                "Run at startup is optional. Enable it yourself in Settings → General; this tour does not change it or request permissions.",
                table: "Preferences"
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(l10n.text("Skip", table: "Preferences"), action: onFinish)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("onboarding.skip")
            Spacer(minLength: 16)
            if step == .reminders {
                Button(l10n.text("Back", table: "Preferences")) {
                    step = .reading
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.back")
            }
            Button(l10n.text(step == .reading ? "Continue" : "Finish", table: "Preferences")) {
                if step == .reading {
                    step = .reminders
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.controlAccent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(step == .reading ? "onboarding.continue" : "onboarding.finish")
        }
    }

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

    private enum Step: Hashable {
        case reading, reminders
    }
}
