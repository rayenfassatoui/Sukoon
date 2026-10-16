import SwiftUI
import SukoonCore

struct WorkspaceView: View {
    static let minimumContentSize = CGSize(width: 680, height: 520)

    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable private var store: AppStore
    @Bindable private var navigation: AppNavigation
    private let reminderClock: ReminderClock
    private let onPreview: () -> Void
    @State private var onboardingIsPresented = false

    init(store: AppStore, navigation: AppNavigation, reminderClock: ReminderClock, onPreview: @escaping () -> Void) {
        self.store = store
        self.navigation = navigation
        self.reminderClock = reminderClock
        self.onPreview = onPreview
    }

    private var celebrationBinding: Binding<Celebration?> {
        Binding(
            get: {
                guard !navigation.showsOnboarding, !onboardingIsPresented,
                      case .khatm? = store.celebration else { return nil }
                return .khatm
            },
            set: { celebration in
                // Onboarding temporarily hides this sheet without consuming the completion.
                guard !navigation.showsOnboarding, !onboardingIsPresented else { return }
                store.celebration = celebration
            }
        )
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch navigation.section {
        case .today:
            TodayView(store: store, navigation: navigation, reminderClock: reminderClock, onPreview: onPreview)
        case .quran:
            ReaderView(store: store, navigation: navigation)
        case .journey:
            JourneyView(store: store, navigation: navigation)
        case .favourites:
            FavouritesView(store: store, navigation: navigation)
        case .settings:
            SettingsView(store: store, navigation: navigation, onPreview: onPreview)
        }
    }

    private var compactNavigation: some View {
        HStack(spacing: 12) {
            Text("سكون")
                .font(.headline)
                .environment(\.layoutDirection, .rightToLeft)

            Picker(
                l10n.text("Choose a section", table: "Workspace"),
                selection: $navigation.section
            ) {
                ForEach(AppSection.allCases) { section in
                    Label(l10n.text(section.title), systemImage: section.symbol)
                        .tag(section)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 220)
            Spacer(minLength: 0)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(palette.canvas)
    }


    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 760
            // Keep the destination's identity when only the navigation chrome changes.
            HStack(spacing: 0) {
                if !compact {
                    WorkspaceSidebar(navigation: navigation)
                        .frame(width: 186)
                    Divider()
                }
                VStack(spacing: 0) {
                    if compact {
                        compactNavigation
                        Divider()
                    }
                    sectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: Self.minimumContentSize.width, minHeight: Self.minimumContentSize.height)
        .background(palette.canvas)
        .sheet(isPresented: $navigation.showsOnboarding, onDismiss: {
            onboardingIsPresented = false
        }) {
            ThemeRoot(store: store) {
                OnboardingView(
                    store: store,
                    onPreview: onPreview,
                    onFinish: {
                        store.completeOnboarding()
                        navigation.showsOnboarding = false
                    }
                )
            }
            .onAppear { onboardingIsPresented = true }
        }
        .sheet(item: celebrationBinding) { _ in
            ThemeRoot(store: store) {
                CelebrationView(
                    store: store,
                    navigation: navigation,
                    onDismiss: { store.celebration = nil }
                )
            }
        }
    }
}


private struct WorkspaceSidebar: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable var navigation: AppNavigation

    private var selection: Binding<AppSection?> {
        Binding(
            get: { navigation.section },
            set: { if let section = $0 { navigation.section = section } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("سكون")
                    .font(.title2.weight(.semibold))
                    .environment(\.layoutDirection, .rightToLeft)
                Text(l10n.text("A quiet rhythm with the Quran", table: "Workspace"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            List(selection: selection) {
                ForEach(AppSection.allCases) { section in
                    Label(l10n.text(section.title), systemImage: section.symbol)
                        .font(.body)
                        .foregroundStyle(navigation.section == section ? Color.white : palette.primary)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .tint(palette.controlAccent)
            .scrollContentBackground(.hidden)
            .accessibilityLabel(l10n.text("Choose a section", table: "Workspace"))

            Divider()
                .padding(.horizontal, 12)
            Text(l10n.text("Read gently. Return often.", table: "Workspace"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
        .background(palette.canvas)
    }
}

private struct TodayView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    let navigation: AppNavigation
    let reminderClock: ReminderClock
    let onPreview: () -> Void
    @State private var remembrance: ReminderContent?

    init(store: AppStore, navigation: AppNavigation, reminderClock: ReminderClock, onPreview: @escaping () -> Void) {
        self.store = store
        self.navigation = navigation
        self.reminderClock = reminderClock
        self.onPreview = onPreview
        _remembrance = State(initialValue: store.previewReminder())
    }

    private var suspension: ReminderSuspensionStatus? {
        ReminderSuspensionStatus(store: store, now: reminderClock.now)
    }

    private var statusTitle: String {
        if !store.settings.remindersEnabled {
            return l10n.text("Reminders are paused", table: "Workspace")
        }
        if store.settings.mode == .surah && store.activeSurah == nil {
            return l10n.text("Choose a reading plan", table: "Workspace")
        }
        if !store.canScheduleReminder {
            return l10n.text("No reminder is scheduled", table: "Workspace")
        }
        if let suspension {
            return suspension.title(l10n: l10n)
        }
        let seconds = store.settings.intervalSeconds
        let subMinute = seconds < 60
        return l10n.format(
            subMinute ? "A quiet moment every %@ sec" : "A quiet moment every %@ min",
            l10n.number(subMinute ? seconds : seconds / 60),
            table: "Workspace"
        )
    }

    private var statusDetail: String {
        if !store.settings.remindersEnabled {
            return l10n.text("Turn reminders on in Settings whenever you are ready.", table: "Workspace")
        }
        if store.settings.mode == .surah && store.activeSurah == nil {
            return l10n.text("Chosen-surah mode needs a chapter before it can begin.", table: "Workspace")
        }
        if store.settings.mode == .surah && !store.canScheduleReminder {
            return l10n.text("This chosen-surah plan is complete. Select another surah to continue.", table: "Workspace")
        }
        if store.settings.mode == .automatic && store.isAutomaticComplete {
            return l10n.text("Your automatic full-Quran reading is complete.", table: "Workspace")
        }
        if let suspension {
            return suspension.detail(l10n: l10n)
        }
        if store.settings.autoAdvance && store.settings.mode == .surah {
            return l10n.text("Delivered chosen-surah verses advance after the panel appears.", table: "Workspace")
        }
        if store.settings.autoAdvance && store.settings.mode == .automatic {
            return l10n.text("Delivered automatic Quran verses advance from your saved position.", table: "Workspace")
        }
        if store.settings.mode == .surah || store.settings.mode == .automatic {
            return l10n.text("Use Read & continue in the reminder to confirm each verse manually.", table: "Workspace")
        }
        return l10n.text("The next panel will offer a quiet moment of Quran or dua.", table: "Workspace")
    }

    private var emptyReminderDetail: String {
        if store.settings.mode == .automatic && store.isAutomaticComplete {
            return l10n.text(
                "Automatic Quran is complete. Open Journey to review your progress.",
                table: "Workspace"
            )
        }
        if store.settings.mode == .surah {
            return l10n.text(
                "Choose a surah in the Quran reader, or select another reminder mode in Settings.",
                table: "Workspace"
            )
        }
        return l10n.text("No reminder content is available right now.", table: "Workspace")
    }

    private var previewButton: some View {
        Button(action: onPreview) {
            Label(
                l10n.text("Preview reminder", table: "Workspace"),
                systemImage: "bell.and.waves.left.and.right"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(remembrance == nil)
    }

    private var reminderStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                l10n.text(store.settings.mode.title),
                systemImage: store.canDeliverReminder(at: reminderClock.now) ? "bell" : "bell.slash"
            )
            .font(.headline)
            Text(statusTitle)
                .font(.callout.weight(.medium))
            Text(statusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(l10n.text("Open reminder settings", table: "Workspace")) {
                navigation.section = .settings
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    SukoonSectionTitle(
                        l10n.text("Today", table: "Workspace"),
                        detail: l10n.text("A moment of sukoon", table: "Workspace")
                    )
                    Spacer(minLength: 0)
                    previewButton
                }

                if let remembrance {
                    passage(remembrance)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(l10n.text("Nothing queued yet", table: "Workspace"), systemImage: "book.closed")
                            .font(.headline)
                        Text(emptyReminderDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sukoonCard()
                }

                ReadingPlanCard(store: store, navigation: navigation)

                VStack(alignment: .leading, spacing: 16) {
                    reminderStatus
                    Divider()
                    journeySummary
                }
                .padding(.horizontal, 2)
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(palette.canvas)
        .onChange(of: store.settings.mode) { _, _ in
            remembrance = store.previewReminder()
        }
        .onChange(of: store.selectedSurahID) { _, _ in
            remembrance = store.previewReminder()
        }
        .onChange(of: store.automaticVerseOffset) { _, _ in
            remembrance = store.previewReminder()
        }
        .onChange(of: store.readVerseCount) { _, _ in
            remembrance = store.previewReminder()
        }
    }

    private func passage(_ content: ReminderContent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    l10n.reminderTitle(content, library: store.library),
                    systemImage: content.kind == .dua ? "hands.sparkles" : "book.pages"
                )
                .font(.headline)
                Text(l10n.reminderSubtitle(content))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ArabicText(content.arabic, size: store.settings.arabicFontSize)
                .textSelection(.enabled)
            if let reference = content.reference {
                Button(l10n.text("Continue in reader", table: "Workspace")) {
                    navigation.readerSurahID = reference.surahID
                    navigation.readerReference = reference
                    navigation.section = .quran
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.controlAccent)
            }
        }
        .sukoonCard()
    }

    private var journeySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(l10n.text("Your Quran journey", table: "Workspace"))
                    .font(.headline)
                Spacer(minLength: 0)
                Text(l10n.percent(store.completionFraction))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(
                l10n.format(
                    "%@ of %@ verses marked",
                    l10n.number(store.readVerseCount),
                    l10n.number(store.library.verseCount),
                    table: "Workspace"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            SukoonProgress(value: store.completionFraction)
            Button(l10n.text("View journey", table: "Workspace")) {
                navigation.section = .journey
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ReadingPlanCard: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    let navigation: AppNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.settings.mode == .automatic {
                automaticPlan
            } else if let surah = store.activeSurah {
                chosenSurahPlan(surah)
            } else {
                Text(l10n.text("Begin a chosen-surah plan", table: "Workspace"))
                    .font(.headline)
                Text(
                    l10n.text(
                        "Select any surah for its own ordered reminders. Your automatic Quran position remains separate.",
                        table: "Workspace"
                    )
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l10n.text("Choose a surah", table: "Workspace")) {
                    navigation.section = .quran
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sukoonCard()
    }

    @ViewBuilder
    private var automaticPlan: some View {
        Text(l10n.text("Automatic Quran", table: "Workspace"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if store.isAutomaticComplete {
            Label(
                l10n.text("Full Quran sequence complete", table: "Workspace"),
                systemImage: "checkmark.seal.fill"
            )
            .font(.headline)
            .foregroundStyle(palette.success)
            Button(l10n.text("View journey", table: "Workspace")) {
                navigation.section = .journey
            }
            .buttonStyle(.bordered)
        } else if let reference = store.automaticNextReference,
                  let surah = store.automaticSurah {
            Text(l10n.surahName(surah))
                .font(.headline)
            Text(
                l10n.format(
                    "Next saved position: %@",
                    l10n.reference(reference),
                    table: "Workspace"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(
                l10n.format(
                    "%@ of %@ verses acknowledged in order",
                    l10n.number(store.automaticVerseOffset),
                    l10n.number(store.library.verseCount),
                    table: "Workspace"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button(l10n.text("Continue in reader", table: "Workspace")) {
                navigation.readerSurahID = reference.surahID
                navigation.readerReference = reference
                navigation.section = .quran
            }
            .buttonStyle(.bordered)
        }
    }

    private func chosenSurahPlan(_ surah: Surah) -> some View {
        let read = store.readCount(in: surah.id)
        return Group {
            Text(l10n.text("Chosen-surah reading", table: "Workspace"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(l10n.surahName(surah))
                .font(.headline)
            Text(
                l10n.format(
                    "%@ of %@ verses marked",
                    l10n.number(read),
                    l10n.number(surah.totalVerses),
                    table: "Workspace"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            if let verse = store.nextUnreadVerse(in: surah.id) {
                Text(
                    l10n.format(
                        "Next: verse %@",
                        l10n.quranNumber(verse.id),
                        table: "Workspace"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button(l10n.text("Continue in reader", table: "Workspace")) {
                navigation.readerSurahID = surah.id
                navigation.readerReference = store.nextUnreadVerse(in: surah.id).map {
                    VerseReference(surahID: surah.id, verseID: $0.id)
                }
                navigation.section = .quran
            }
            .buttonStyle(.bordered)
        }
    }
}
