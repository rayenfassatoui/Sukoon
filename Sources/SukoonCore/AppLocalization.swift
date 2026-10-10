import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case arabic = "ar"

    public var id: String { rawValue }
    public var nativeName: String { self == .arabic ? "العربية" : "English" }
}

/// Explicit app language, independent of the Mac's language. Bundles are shared across renders.
public struct AppLocalization: Sendable {
    public let language: AppLanguage
    public let locale: Locale
    private let bundle: Bundle

    private static let englishBundle = languageBundle(.english)
    private static let arabicBundle = languageBundle(.arabic)

    public init(language: AppLanguage) {
        self.language = language
        locale = Locale(identifier: language == .arabic ? "ar@numbers=arab" : "en")
        bundle = language == .arabic ? Self.arabicBundle : Self.englishBundle
    }

    public var isArabic: Bool { language == .arabic }

    public func text(_ source: String, table: String = "Interface") -> String {
        bundle.localizedString(forKey: source, value: source, table: table)
    }

    public func format(_ source: String, _ arguments: CVarArg..., table: String = "Interface") -> String {
        String(format: text(source, table: table), locale: locale, arguments: arguments)
    }

    public func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    public func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.percent.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    public func surahName(_ surah: Surah) -> String {
        isArabic ? surah.name : surah.transliteration
    }

    public func revelationType(_ type: String) -> String {
        switch type {
        case "meccan": text("Meccan")
        case "medinan": text("Medinan")
        default: type
        }
    }

    public func reference(_ reference: VerseReference) -> String {
        // References are always surah:ayah, even inside an Arabic sentence.
        "\u{2066}\(number(reference.surahID)):\(number(reference.verseID))\u{2069}"
    }

    public func reminderTitle(_ content: ReminderContent, library: QuranLibrary) -> String {
        if content.kind == .dua { return text("Quranic supplication") }
        if content.kind == .automatic { return text("Automatic Quran") }
        guard let reference = content.reference, let surah = library.surah(reference.surahID) else {
            return text(content.title)
        }
        let name = surahName(surah)
        return content.kind == .surah ? format("Continue %@", name) : name
    }

    public func reminderSubtitle(_ content: ReminderContent) -> String {
        guard let source = content.reference else { return text(content.subtitle) }
        return format("Quran %@", reference(source))
    }

    public func libraryError(_ error: any Error) -> String {
        guard let error = error as? QuranLibraryError else { return error.localizedDescription }
        switch error {
        case .resourceMissing:
            return text("The bundled Quran resource is missing.")
        case let .unreadableResource(reason):
            return format("The bundled Quran resource could not be read: %@", reason)
        case let .invalidJSON(reason):
            return format("The bundled Quran resource is not valid JSON: %@", reason)
        case let .invalidSurahSequence(expected, actual):
            return format("Expected surah %@, found surah %@.", number(expected), number(actual))
        case let .invalidVerseSequence(surahID, expected, actual):
            return format("Expected verse %@ in surah %@, found verse %@.", number(expected), number(surahID), number(actual))
        case let .incorrectSurahCount(count):
            return format("Expected 114 surahs, found %@.", number(count))
        case let .incorrectVerseCount(count):
            return format("Expected 6,236 verses, found %@.", number(count))
        case let .incorrectDeclaredVerseCount(surahID, declared, actual):
            return format("Surah %@ declares %@ verses but contains %@.", number(surahID), number(declared), number(actual))
        }
    }

    private static func languageBundle(_ language: AppLanguage) -> Bundle {
        guard let path = SukoonResources.bundle.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            preconditionFailure("The bundled \(language.rawValue) localization is missing.")
        }
        return bundle
    }
}

/// The same resource lookup serves SwiftPM development/tests and the portable application bundle.
enum SukoonResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Sukoon_SukoonCore.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return Bundle.module
    }()
}
