import SwiftUI
import SukoonCore

struct CelebrationView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sukoonLocalization) private var l10n
    let celebration: Celebration
    let store: AppStore
    let navigation: AppNavigation
    let onDismiss: () -> Void
    @State private var appeared = false

    private var completedSurah: Surah? {
        guard case let .surah(id) = celebration else { return nil }
        return store.library.surah(id)
    }

    private var nextSurah: Surah? {
        guard let completedSurah else { return nil }
        let laterUnread = store.library.surahs.first {
            $0.id > completedSurah.id && store.nextUnreadVerse(in: $0.id) != nil
        }
        return laterUnread ?? store.library.surahs.first {
            $0.id < completedSurah.id && store.nextUnreadVerse(in: $0.id) != nil
        }
    }

    private var acceptanceVerse: Verse? {
        store.library.surah(2)?.verses.first(where: { $0.id == 127 })
    }

    private var acceptanceReference: String {
        let reference = l10n.reference(VerseReference(surahID: 2, verseID: 127))
        let surahName = store.library.surah(2).map(l10n.surahName) ?? ""
        return l10n.format(
            "Quran %@ · %@",
            reference,
            surahName,
            table: "Preferences"
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.accentSoft.opacity(0.28), Color.clear, palette.gold.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(palette.accent.opacity(0.07))
                .frame(width: 360, height: 360)
                .blur(radius: 2)
                .offset(x: -250, y: -230)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 24) {
                    celebrationMark
                        .scaleEffect(appeared ? 1 : 0.86)
                        .opacity(appeared ? 1 : 0)

                    switch celebration {
                    case .surah:
                        surahCelebration
                    case .khatm:
                        khatmCelebration
                    }
                }
                .padding(42)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            if celebration == .khatm && !reduceMotion {
                CompletionConfetti()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 650, idealWidth: 720, minHeight: 570, idealHeight: 660)
        .background(palette.canvas)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) {
                    appeared = true
                }
            }
        }
    }

    private var celebrationMark: some View {
        ZStack {
            Circle()
                .fill(palette.accentSoft.opacity(0.28))
                .frame(width: 112, height: 112)
            Circle()
                .stroke(palette.accent.opacity(0.20), lineWidth: 1)
                .frame(width: 92, height: 92)
            Image(systemName: celebration == .khatm ? "sparkles" : "checkmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var surahCelebration: some View {
        if let surah = completedSurah {
            VStack(spacing: 17) {
                Text(l10n.text("Surah complete", table: "Preferences"))
                    .font(.caption.weight(.bold))
                    .tracking(l10n.isArabic ? 0 : 1.8)
                    .foregroundStyle(palette.accent)
                Text(l10n.surahName(surah))
                    .font(
                        l10n.isArabic
                            ? .custom("Geeza Pro", size: 38).weight(.bold)
                            : .system(size: 38, weight: .bold, design: .rounded)
                    )
                    .multilineTextAlignment(.center)
                if !l10n.isArabic {
                    Text(surah.name)
                        .font(.custom("Geeza Pro", size: 37).weight(.bold))
                        .environment(\.layoutDirection, .rightToLeft)
                        .foregroundStyle(palette.accent)
                }
                Text(
                    l10n.format(
                        "You marked all %@ verses. May each return to this surah deepen reflection and bring steadiness to your day.",
                        l10n.number(surah.totalVerses),
                        table: "Preferences"
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)

                HStack(spacing: 12) {
                    Button(
                        l10n.text("Not now", table: "Preferences"),
                        action: onDismiss
                    )
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help(l10n.text("Close this celebration", table: "Preferences"))

                    if store.settings.mode == .automatic,
                       let reference = store.automaticNextReference,
                       let automaticSurah = store.automaticSurah {
                        Button {
                            store.startAutomaticReading()
                            navigation.readerSurahID = reference.surahID
                            navigation.section = .quran
                            onDismiss()
                        } label: {
                            Label(
                                l10n.format(
                                    "Continue automatic reading · %@",
                                    l10n.surahName(automaticSurah),
                                    table: "Preferences"
                                ),
                                systemImage: l10n.isArabic ? "arrow.left" : "arrow.right"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .help(l10n.text("Open the saved automatic Quran position", table: "Preferences"))
                    } else if store.settings.mode == .automatic {
                        Button {
                            navigation.section = .journey
                            onDismiss()
                        } label: {
                            Label(
                                l10n.text("View completed journey", table: "Preferences"),
                                systemImage: "checkmark.seal"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else if let nextSurah {
                        Button {
                            store.startSurah(nextSurah.id)
                            navigation.readerSurahID = nextSurah.id
                            navigation.section = .quran
                            onDismiss()
                        } label: {
                            Label(
                                l10n.format(
                                    "Begin %@",
                                    l10n.surahName(nextSurah),
                                    table: "Preferences"
                                ),
                                systemImage: l10n.isArabic ? "arrow.left" : "arrow.right"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .help(
                            l10n.format(
                                "Start reading %@",
                                l10n.surahName(nextSurah),
                                table: "Preferences"
                            )
                        )
                    } else {
                        Button {
                            navigation.section = .journey
                            onDismiss()
                        } label: {
                            Label(
                                l10n.text("View journey", table: "Preferences"),
                                systemImage: "chart.line.uptrend.xyaxis"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .help(l10n.text("Open your reading journey", table: "Preferences"))
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var khatmCelebration: some View {
        VStack(spacing: 18) {
            Text("خَتْمُ الْقُرْآن")
                .font(.custom("Geeza Pro", size: 22).weight(.bold))
                .environment(\.layoutDirection, .rightToLeft)
                .foregroundStyle(palette.gold)
            Text(l10n.text("You completed the Quran", table: "Preferences"))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(
                l10n.text(
                    "Every verse in your journey is marked. Take a quiet moment for gratitude, and ask Allah to accept what you have offered.",
                    table: "Preferences"
                )
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 560)

            if let acceptanceVerse {
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        l10n.text("A Quranic prayer of acceptance", table: "Preferences"),
                        systemImage: "hands.sparkles"
                    )
                    .font(.headline)
                    .foregroundStyle(palette.accent)
                    ArabicText(
                        acceptanceVerse.text,
                        size: min(store.settings.arabicFontSize, 36)
                    )
                    if !l10n.isArabic {
                        Text(
                            l10n.text(
                                "“Our Lord, accept this from us. You are indeed the All-Hearing, All-Knowing.”",
                                table: "Preferences"
                            )
                        )
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(acceptanceReference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                .sukoonCard(padding: 22)
                .frame(maxWidth: 600)
            }

            HStack(spacing: 12) {
                Button {
                    navigation.readerSurahID = 1
                    navigation.section = .quran
                    onDismiss()
                } label: {
                    Label(
                        l10n.text("Open Quran", table: "Preferences"),
                        systemImage: "book.closed"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help(l10n.text("Open the Quran reader", table: "Preferences"))

                Button {
                    navigation.section = .journey
                    onDismiss()
                } label: {
                    Label(
                        l10n.text("View completed journey", table: "Preferences"),
                        systemImage: "checkmark.seal"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(l10n.text("Open your completed reading journey", table: "Preferences"))
            }
            .padding(.top, 4)
        }
    }
}

private struct CompletionConfetti: View {
    @Environment(\.sukoonPalette) private var palette
    @State private var startedAt = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                guard elapsed >= 0, elapsed < 5 else { return }
                for index in 0..<72 {
                    let seed = Double(index)
                    let delay = Double(index % 9) * 0.055
                    let time = max(0, elapsed - delay)
                    let angle = seed * 2.399963
                    let velocity = 90 + Double(index % 7) * 32
                    let x = size.width / 2 + cos(angle) * velocity * time
                    let y = size.height * 0.15 + sin(angle) * velocity * time + 100 * time * time
                    var particle = context
                    particle.opacity = max(0, min(1, 5 - elapsed))
                    particle.translateBy(x: x, y: y)
                    particle.rotate(by: .radians(angle + time * 2))
                    let rect = CGRect(x: -3, y: -5, width: 6, height: 10)
                    particle.fill(Path(roundedRect: rect, cornerRadius: 2),
                                  with: .color(index.isMultiple(of: 3) ? palette.gold : palette.accent))
                }
            }
        }
        .task {
            startedAt = .now
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            finished = true
        }
    }
}
