import SwiftUI
import SukoonCore

struct JourneyView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    let navigation: AppNavigation

    private var completedSurahs: [Surah] {
        let completedIDs = store.completedSurahIDs
        return store.library.surahs.filter { completedIDs.contains($0.id) }
    }

    private var inProgressSurahs: [Surah] {
        store.library.surahs.filter {
            let count = store.readCount(in: $0.id)
            return count > 0 && count < $0.totalVerses
        }
    }

    var body: some View {
        let completed = completedSurahs
        let inProgress = inProgressSurahs
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SukoonSectionTitle(
                    l10n.text("Your journey", table: "Workspace"),
                    detail: l10n.text(
                        "Every marked verse is kept here, while automatic Quran reading also keeps its own sequential position.",
                        table: "Workspace"
                    )
                )

                overallProgress(completedCount: completed.count)

                VStack(alignment: .leading, spacing: 16) {
                    automaticPlan
                    Divider()
                    if let chosen = store.activeSurah {
                        currentPlan(chosen)
                    } else {
                        choosePlan
                    }
                }
                .sukoonCard()

                deliveryExplanation

                if inProgress.isEmpty && completed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(l10n.text("A clear beginning", table: "Workspace"), systemImage: "book.closed")
                            .font(.headline)
                        Text(
                            l10n.text(
                                "No verses are marked yet. Open a surah and begin at your own pace.",
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sukoonCard()
                } else {
                    if !inProgress.isEmpty {
                        journeyGroup(
                            title: l10n.text("In progress", table: "Workspace"),
                            detail: l10n.text("Chapters with at least one marked verse", table: "Workspace"),
                            surahs: inProgress,
                            completed: false
                        )
                    }

                    if !completed.isEmpty {
                        journeyGroup(
                            title: l10n.text("Completed surahs", table: "Workspace"),
                            detail: l10n.text("Every verse in these chapters is marked", table: "Workspace"),
                            surahs: completed,
                            completed: true
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvas)
    }

    private func overallProgress(completedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(l10n.text("The whole Quran", table: "Workspace"))
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
            Text(
                l10n.format(
                    "%@ of %@ surahs complete",
                    l10n.number(completedCount),
                    l10n.number(store.library.surahs.count),
                    table: "Workspace"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sukoonCard()
    }

    private var deliveryExplanation: some View {
        DisclosureGroup {
            Text(
                l10n.text(
                    "A manual mark confirms your reading. A real chosen-surah or automatic Quran delivery can also mark its verse when delivered progress is on; previews, random ayahs, and duas never add progress. Automatic position advances separately and only for its matching reminder.",
                    table: "Workspace"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        } label: {
            Text(l10n.text("What a marked verse means", table: "Workspace"))
                .font(.callout.weight(.medium))
        }
    }

    private var automaticPlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.text("Automatic Quran", table: "Workspace"), systemImage: "books.vertical")
                .font(.headline)
            Text(
                l10n.text(
                    store.isAutomaticComplete ? "Full Quran sequence complete" : "Full-Quran saved position",
                    table: "Workspace"
                )
            )
            .font(.callout)

            Text(
                l10n.format(
                    "%@ of %@ verses acknowledged in order",
                    l10n.number(store.automaticVerseOffset),
                    l10n.number(store.library.verseCount),
                    table: "Workspace"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                if let reference = store.automaticNextReference,
                   let surah = store.automaticSurah {
                    Text(
                        l10n.format(
                            "Next: %@ · %@",
                            l10n.surahName(surah),
                            l10n.reference(reference),
                            table: "Workspace"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button(l10n.text("Resume automatic reading", table: "Workspace")) {
                        store.startAutomaticReading()
                        navigation.readerSurahID = reference.surahID
                        navigation.readerReference = reference
                        navigation.section = .quran
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label(
                        l10n.text("Automatic Quran complete"),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.success)
                }
            }
        }
    }

    private func currentPlan(_ surah: Surah) -> some View {
        let count = store.readCount(in: surah.id)
        let nextUnread = store.nextUnreadVerse(in: surah.id)
        return VStack(alignment: .leading, spacing: 8) {
            Label(l10n.text("Chosen-surah reading", table: "Workspace"), systemImage: "bookmark")
                .font(.headline)
            Text(l10n.surahName(surah))
                .font(.callout.weight(.medium))
            Text(
                l10n.format(
                    "%@ of %@ verses marked",
                    l10n.number(count),
                    l10n.number(surah.totalVerses),
                    table: "Workspace"
                )
            )
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                if let next = nextUnread {
                    Text(
                        l10n.format(
                            "Next: verse %@",
                            l10n.quranNumber(next.id),
                            table: "Workspace"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(l10n.text("Surah complete", table: "Workspace"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.success)
                }
                Button(
                    l10n.text(nextUnread == nil ? "Open Quran" : "Continue reading", table: "Workspace")
                ) {
                    navigation.readerSurahID = surah.id
                    navigation.readerReference = nextUnread.map {
                        VerseReference(surahID: surah.id, verseID: $0.id)
                    }
                    navigation.section = .quran
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var choosePlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.text("Choose a surah", table: "Workspace"))
                    .font(.headline)
                Text(
                    l10n.text(
                        "Select one surah for its own ordered reminders without changing automatic Quran progress.",
                        table: "Workspace"
                    )
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(l10n.text("Open Quran", table: "Workspace")) {
                navigation.section = .quran
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func journeyGroup(
        title: String,
        detail: String,
        surahs: [Surah],
        completed: Bool
    ) -> some View {
        let lastSurahID = surahs.last?.id
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(surahs) { surah in
                    VStack(spacing: 0) {
                        JourneySurahRow(
                            surah: surah,
                            readCount: store.readCount(in: surah.id),
                            completed: completed,
                            action: {
                                navigation.readerSurahID = surah.id
                                navigation.readerReference = store.nextUnreadVerse(in: surah.id).map {
                                    VerseReference(surahID: surah.id, verseID: $0.id)
                                }
                                navigation.section = .quran
                            }
                        )
                        if surah.id != lastSurahID {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .sukoonCard(padding: 0)
        }
    }
}

private struct JourneySurahRow: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let readCount: Int
    let completed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(l10n.quranNumber(surah.id))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 26, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.surahName(surah))
                        .font(.body.weight(.medium))
                    Text(l10n.isArabic ? surah.transliteration : surah.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
                }
                Spacer(minLength: 0)
                Text(
                    completed
                        ? l10n.format(
                            "All %@ verses marked",
                            l10n.number(surah.totalVerses),
                            table: "Workspace"
                        )
                        : l10n.format(
                            "%@ of %@ marked",
                            l10n.number(readCount),
                            l10n.number(surah.totalVerses),
                            table: "Workspace"
                        )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: completed ? "checkmark.circle" : "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(completed ? palette.success : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.primary)
        .help(
            l10n.format(
                "Open Surah %@",
                l10n.surahName(surah),
                table: "Workspace"
            )
        )
    }
}
