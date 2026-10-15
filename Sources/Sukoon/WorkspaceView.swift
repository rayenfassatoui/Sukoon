import SwiftUI
import SukoonCore

struct WorkspaceView: View {
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable private var store: AppStore
    @Bindable private var navigation: AppNavigation
    private let reminderClock: ReminderClock
    private let onPreview: () -> Void

    init(store: AppStore, navigation: AppNavigation, reminderClock: ReminderClock, onPreview: @escaping () -> Void) {
        self.store = store
        self.navigation = navigation
        self.reminderClock = reminderClock
        self.onPreview = onPreview
    }

    private var celebrationBinding: Binding<Celebration?> {
        Binding(
            get: {
                guard case .khatm? = store.celebration else { return nil }
                return .khatm
            },
            set: { store.celebration = $0 }
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
        HStack(spacing: 10) {
            Text("سكون")
                .font(.custom("Geeza Pro", size: 20).weight(.bold))
                .environment(\.layoutDirection, .rightToLeft)

            Menu {
                ForEach(AppSection.allCases) { section in
                    Button {
                        navigation.section = section
                    } label: {
                        Label(l10n.text(section.title), systemImage: section.symbol)
                    }
                }
            } label: {
                Label(l10n.text(navigation.section.title), systemImage: navigation.section.symbol)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(l10n.text("Choose a section", table: "Workspace"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }


    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 760
            // Keep the destination's identity when only the navigation chrome changes.
            HStack(spacing: 0) {
                if !compact {
                    WorkspaceSidebar(navigation: navigation)
                        .frame(width: 214)
                    Divider().opacity(0.5)
                }
                VStack(spacing: 0) {
                    if compact {
                        compactNavigation
                        Divider().opacity(0.5)
                    }
                    sectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.thinMaterial)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("سكون")
                    .font(.custom("Geeza Pro", size: 31).weight(.bold))
                    .environment(\.layoutDirection, .rightToLeft)
                Text(l10n.text("A quiet rhythm with the Quran", table: "Workspace"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 52)
            .padding(.bottom, 24)

            VStack(spacing: 6) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        navigation.section = section
                    } label: {
                        Label(l10n.text(section.title), systemImage: section.symbol)
                            .font(.system(size: 14, weight: navigation.section == section ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(navigation.section == section ? palette.accent : .primary)
                    .background {
                        if navigation.section == section {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(palette.accentSoft.opacity(0.24))
                        }
                    }
                    .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "leaf")
                    .foregroundStyle(palette.accent)
                Text(l10n.text("Read gently. Return often.", table: "Workspace"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .background(.thinMaterial)
    }
}

private struct TodayView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
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
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(remembrance == nil)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: store.canDeliverReminder(at: reminderClock.now) ? "bell.badge" : "bell.slash")
                .font(.title2)
                .foregroundStyle(palette.accent)
            Text(statusTitle)
                .font(.title3.weight(.semibold))
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
        .sukoonCard(padding: 18)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        SukoonSectionTitle(
                            l10n.text("A moment of sukoon", table: "Workspace"),
                            eyebrow: l10n.text("Today", table: "Workspace"),
                            detail: l10n.text(
                                "Pause, breathe, and return to the words that steady the heart.",
                                table: "Workspace"
                            )
                        )
                        Spacer(minLength: 16)
                        previewButton
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SukoonSectionTitle(
                            l10n.text("A moment of sukoon", table: "Workspace"),
                            eyebrow: l10n.text("Today", table: "Workspace"),
                            detail: l10n.text(
                                "Pause, breathe, and return to the words that steady the heart.",
                                table: "Workspace"
                            )
                        )
                        previewButton
                    }
                }

                if let remembrance {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label(
                                l10n.reminderTitle(remembrance, library: store.library),
                                systemImage: remembrance.kind == .dua ? "hands.sparkles" : "book.pages"
                            )
                                .font(.headline)
                                .foregroundStyle(palette.accent)
                            Spacer()
                            Text(l10n.reminderSubtitle(remembrance))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ArabicText(remembrance.arabic, size: min(store.settings.arabicFontSize, 38))
                    }
                    .sukoonCard(padding: 18)
                } else {
                    ContentUnavailableView(
                        l10n.text("Nothing queued yet", table: "Workspace"),
                        systemImage: "moon.stars",
                        description: Text(emptyReminderDetail)
                    )
                    .frame(maxWidth: .infinity)
                    .sukoonCard(padding: 18)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        statusCard
                        ReadingPlanCard(store: store, navigation: navigation)
                            .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        statusCard
                        ReadingPlanCard(store: store, navigation: navigation)
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l10n.text("Your Quran journey", table: "Workspace"))
                                .font(.headline)
                            Text(
                                l10n.format(
                                    "%@ of %@ verses marked",
                                    l10n.number(store.readVerseCount),
                                    l10n.number(store.library.verseCount),
                                    table: "Workspace"
                                )
                            )
                                .foregroundStyle(.secondary)
                        }
                        Text(l10n.percent(store.completionFraction))
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    SukoonProgress(value: store.completionFraction)
                    Button(l10n.text("View journey", table: "Workspace")) {
                        navigation.section = .journey
                    }
                    .buttonStyle(.link)
                }
                .sukoonCard(padding: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(colorScheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : palette.canvas)
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
}

private struct ReadingPlanCard: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    let navigation: AppNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: store.settings.mode == .automatic ? "books.vertical" : "bookmark")
                .font(.title2)
                .foregroundStyle(palette.accent)
            if store.settings.mode == .automatic {
                automaticPlan
            } else if let surah = store.activeSurah {
                chosenSurahPlan(surah)
            } else {
                Text(l10n.text("Begin a chosen-surah plan", table: "Workspace"))
                    .font(.title3.weight(.semibold))
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
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sukoonCard(padding: 18)
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
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.success)
            Button(l10n.text("View journey", table: "Workspace")) {
                navigation.section = .journey
            }
            .buttonStyle(.borderedProminent)
        } else if let reference = store.automaticNextReference,
                  let surah = store.automaticSurah {
            Text(l10n.surahName(surah))
                .font(.title3.weight(.semibold))
            Text(
                l10n.format(
                    "Next saved position: %@",
                    l10n.reference(reference),
                    table: "Workspace"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            SukoonProgress(
                value: store.library.verseCount == 0
                    ? 0
                    : Double(store.automaticVerseOffset) / Double(store.library.verseCount)
            )
            Button(l10n.text("Continue in reader", table: "Workspace")) {
                navigation.readerSurahID = reference.surahID
                navigation.section = .quran
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func chosenSurahPlan(_ surah: Surah) -> some View {
        let read = store.readCount(in: surah.id)
        return Group {
            Text(l10n.text("Chosen-surah reading", table: "Workspace"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.surahName(surah))
                    .font(.title3.weight(.semibold))
                Text(l10n.isArabic ? surah.transliteration : surah.name)
                    .font(l10n.isArabic ? .caption : .custom("Geeza Pro", size: 22))
                    .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
            }
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
            SukoonProgress(value: surah.totalVerses == 0 ? 0 : Double(read) / Double(surah.totalVerses))
            Button(l10n.text("Continue in reader", table: "Workspace")) {
                navigation.readerSurahID = surah.id
                navigation.section = .quran
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
