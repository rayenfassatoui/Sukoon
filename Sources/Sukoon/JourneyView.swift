import SwiftUI
import SukoonCore

struct JourneyView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
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
            VStack(alignment: .leading, spacing: 25) {
                SukoonSectionTitle(
                    l10n.text("Your journey", table: "Workspace"),
                    eyebrow: l10n.text("Quran progress", table: "Workspace"),
                    detail: l10n.text(
                        "Every marked verse is kept here, while automatic Quran reading also keeps its own sequential position.",
                        table: "Workspace"
                    )
                )

                overallProgress(completedCount: completed.count)

                deliveryExplanation

                automaticPlan

                if let chosen = store.activeSurah {
                    currentPlan(chosen)
                } else {
                    choosePlan
                }

                if inProgress.isEmpty && completed.isEmpty {
                    ContentUnavailableView {
                        Label(l10n.text("A clear beginning", table: "Workspace"), systemImage: "book.closed")
                    } description: {
                        Text(
                            l10n.text(
                                "No verses are marked yet. Open a surah and begin at your own pace.",
                                table: "Workspace"
                            )
                        )
                    } actions: {
                        Button(l10n.text("Choose a surah", table: "Workspace")) {
                            navigation.section = .quran
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
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
            .padding(.horizontal, 38)
            .padding(.top, 38)
            .padding(.bottom, 50)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(colorScheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : palette.canvas)
    }

    private func overallProgress(completedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .center, spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(palette.hairline, lineWidth: 11)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(store.completionFraction, 0), 1)))
                        .stroke(
                            palette.accent.gradient,
                            style: StrokeStyle(lineWidth: 11, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(l10n.percent(store.completionFraction))
                            .font(.title2.monospacedDigit().weight(.bold))
                        Text(l10n.text("marked", table: "Workspace"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 128, height: 128)
                .accessibilityElement()
                .accessibilityLabel(l10n.text("Overall Quran progress", table: "Workspace"))
                .accessibilityValue(l10n.percent(store.completionFraction))

                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.text("The whole Quran", table: "Workspace"))
                        .font(.title2.weight(.semibold))
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
                    Text(
                        l10n.format(
                            "%@ of %@ surahs complete",
                            l10n.number(completedCount),
                            l10n.number(store.library.surahs.count),
                            table: "Workspace"
                        )
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SukoonProgress(value: store.completionFraction)
                        .frame(maxWidth: 440)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sukoonCard(padding: 26)
    }

    private var deliveryExplanation: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.message")
                .font(.title3)
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.text("What a marked verse means", table: "Workspace"))
                    .font(.headline)
                Text(
                    l10n.text(
                        "A manual mark confirms your reading. A real chosen-surah or automatic Quran delivery can also mark its verse when delivered progress is on; previews, random ayahs, and duas never add progress. Automatic position advances separately and only for its matching reminder.",
                        table: "Workspace"
                    )
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(palette.accentSoft.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.accent.opacity(0.16), lineWidth: 1)
        }
    }

    private var automaticPlan: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.text("Automatic Quran", table: "Workspace"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        l10n.text(
                            store.isAutomaticComplete ? "Full Quran sequence complete" : "Full-Quran saved position",
                            table: "Workspace"
                        )
                    )
                    .font(.title2.weight(.semibold))
                }
                Spacer()
                Image(systemName: store.isAutomaticComplete ? "checkmark.seal.fill" : "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(store.isAutomaticComplete ? palette.success : palette.accent)
            }

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
            SukoonProgress(
                value: store.library.verseCount == 0
                    ? 0
                    : Double(store.automaticVerseOffset) / Double(store.library.verseCount)
            )

            HStack {
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
                    Spacer()
                    Button(l10n.text("Resume automatic reading", table: "Workspace")) {
                        store.startAutomaticReading()
                        navigation.readerSurahID = reference.surahID
                        navigation.section = .quran
                    }
                    .buttonStyle(.borderedProminent)
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
        .sukoonCard()
    }

    private func currentPlan(_ surah: Surah) -> some View {
        let count = store.readCount(in: surah.id)
        let nextUnread = store.nextUnreadVerse(in: surah.id)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.text("Chosen-surah reading", table: "Workspace"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(l10n.surahName(surah))
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Text(l10n.isArabic ? surah.transliteration : surah.name)
                    .font(l10n.isArabic ? .callout : .custom("Geeza Pro", size: 27).weight(.bold))
                    .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
                    .foregroundStyle(palette.accent)
            }
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
            SukoonProgress(value: surah.totalVerses == 0 ? 0 : Double(count) / Double(surah.totalVerses))
            HStack {
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
                Spacer()
                Button(
                    l10n.text(nextUnread == nil ? "Open Quran" : "Continue reading", table: "Workspace")
                ) {
                    navigation.readerSurahID = surah.id
                    navigation.section = .quran
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sukoonCard()
    }

    private var choosePlan: some View {
        HStack(spacing: 18) {
            Image(systemName: "bookmark.circle")
                .font(.system(size: 35))
                .foregroundStyle(palette.accent)
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
            Spacer()
            Button(l10n.text("Open Quran", table: "Workspace")) {
                navigation.section = .quran
            }
            .buttonStyle(.borderedProminent)
        }
        .sukoonCard()
    }

    @ViewBuilder
    private func journeyGroup(
        title: String,
        detail: String,
        surahs: [Surah],
        completed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 12)], spacing: 12) {
                ForEach(surahs) { surah in
                    JourneySurahCard(
                        surah: surah,
                        readCount: store.readCount(in: surah.id),
                        completed: completed,
                        action: {
                            navigation.readerSurahID = surah.id
                            navigation.section = .quran
                        }
                    )
                }
            }
        }
    }
}

private struct JourneySurahCard: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let readCount: Int
    let completed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text(l10n.quranNumber(surah.id))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if completed {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(palette.success)
                    }
                    Text(l10n.isArabic ? surah.transliteration : surah.name)
                        .font(l10n.isArabic ? .caption : .custom("Geeza Pro", size: 19))
                        .environment(\.layoutDirection, l10n.isArabic ? .leftToRight : .rightToLeft)
                }
                Text(l10n.surahName(surah))
                    .font(.headline)
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
                SukoonProgress(value: surah.totalVerses == 0 ? 0 : Double(readCount) / Double(surah.totalVerses))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        }
        .help(
            l10n.format(
                "Open Surah %@",
                l10n.surahName(surah),
                table: "Workspace"
            )
        )
    }
}
