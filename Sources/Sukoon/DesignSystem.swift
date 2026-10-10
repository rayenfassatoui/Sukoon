import SwiftUI
import Observation
import SukoonCore

@MainActor
@Observable
final class AppNavigation {
    var section: AppSection = .today
    var readerSurahID: Int = 1
}

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case quran
    case journey
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .quran: "Quran"
        case .journey: "Journey"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .quran: "book.closed"
        case .journey: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}

struct Palette {
    let accent: Color
    let accentSoft: Color
    let canvas: Color
    let raisedSurface: Color
    let primary: Color
    let hairline: Color
    let success: Color
    let gold: Color

    init(accent theme: AccentTheme, dark: Bool = false) {
        switch theme {
        case .jade:
            accent = dark ? Color(red: 0.42, green: 0.80, blue: 0.66) : Color(red: 0.08, green: 0.43, blue: 0.33)
            accentSoft = Color(red: 0.73, green: 0.87, blue: 0.80)
        case .gold:
            accent = dark ? Color(red: 0.89, green: 0.73, blue: 0.40) : Color(red: 0.63, green: 0.43, blue: 0.12)
            accentSoft = Color(red: 0.91, green: 0.83, blue: 0.64)
        case .rose:
            accent = dark ? Color(red: 0.92, green: 0.60, blue: 0.67) : Color(red: 0.64, green: 0.27, blue: 0.34)
            accentSoft = Color(red: 0.91, green: 0.75, blue: 0.78)
        }
        canvas = dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : Color(red: 0.98, green: 0.965, blue: 0.92)
        primary = dark ? Color(red: 0.93, green: 0.94, blue: 0.92) : Color(red: 0.12, green: 0.14, blue: 0.12)
        raisedSurface = primary.opacity(0.075)
        hairline = primary.opacity(0.12)
        success = dark ? Color(red: 0.42, green: 0.80, blue: 0.66) : Color(red: 0.10, green: 0.50, blue: 0.34)
        gold = dark ? Color(red: 0.89, green: 0.73, blue: 0.40) : Color(red: 0.72, green: 0.53, blue: 0.20)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(accent: .jade)
}

private struct LocalizationKey: EnvironmentKey {
    static let defaultValue = AppLocalization(language: .english)
}

extension EnvironmentValues {
    var sukoonPalette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var sukoonLocalization: AppLocalization {
        get { self[LocalizationKey.self] }
        set { self[LocalizationKey.self] = newValue }
    }
}

struct ThemeRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: AppStore
    private let content: Content

    init(store: AppStore, @ViewBuilder content: () -> Content) {
        self.store = store
        self.content = content()
    }


    var body: some View {
        let palette = Palette(accent: store.settings.accent, dark: colorScheme == .dark)
        let l10n = AppLocalization(language: store.settings.language)
        content
            .environment(\.sukoonPalette, palette)
            .environment(\.sukoonLocalization, l10n)
            .environment(\.locale, l10n.locale)
            .environment(\.layoutDirection, l10n.isArabic ? .rightToLeft : .leftToRight)
            .tint(palette.accent)
            .foregroundStyle(palette.primary)
    }
}

struct ArabicText: View {
    private let text: String
    private let size: Double

    init(_ text: String, size: Double) {
        self.text = text
        self.size = size
    }

    var body: some View {
        let pointSize = CGFloat(size)
        Text(text)
            .font(.custom("Geeza Pro", size: pointSize))
            .lineSpacing(max(8, pointSize * 0.42))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityLabel(Text(text))
    }
}

struct PassageReference: View {
    @Environment(\.sukoonLocalization) private var l10n
    let library: QuranLibrary
    let content: ReminderContent

    var body: some View {
        if let reference = content.reference, let surah = library.surah(reference.surahID) {
            Text("\(surah.name) · \(reference.verseID.arabicIndicNumerals)")
                .font(.custom("Geeza Pro", size: 14))
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilityLabel(l10n.reminderSubtitle(content))
        } else {
            Text(l10n.reminderSubtitle(content)).font(.caption)
        }
    }
}

struct SukoonCardModifier: ViewModifier {
    @Environment(\.sukoonPalette) private var palette
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(palette.hairline, lineWidth: 1)
                    }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .foregroundStyle(palette.primary)
    }
}

extension View {
    func sukoonCard(padding: CGFloat = 22) -> some View {
        modifier(SukoonCardModifier(padding: padding))
    }
}

struct SukoonSectionTitle: View {
    @Environment(\.sukoonLocalization) private var l10n
    let eyebrow: String?
    let title: String
    let detail: String?

    init(_ title: String, eyebrow: String? = nil, detail: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let eyebrow {
                Text(l10n.isArabic ? eyebrow : eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(l10n.isArabic ? 0 : 1.4)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SukoonProgress: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.hairline)
                Capsule()
                    .fill(palette.accent.gradient)
                    .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(l10n.text("Quran progress"))
        .accessibilityValue(l10n.percent(value, fractionDigits: 0))
    }
}

extension Int {
    private static let arabicDigits = Array("٠١٢٣٤٥٦٧٨٩")
    var arabicIndicNumerals: String {
        let digits = Self.arabicDigits
        return String(String(self).map { character in
            guard let value = character.wholeNumberValue else { return character }
            return digits[value]
        })
    }
}
