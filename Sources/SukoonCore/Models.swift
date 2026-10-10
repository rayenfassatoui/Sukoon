import Foundation

public struct Verse: Codable, Identifiable, Sendable, Equatable, Hashable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

public struct Surah: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let transliteration: String
    public let type: String
    public let totalVerses: Int
    public let verses: [Verse]

    private enum CodingKeys: String, CodingKey {
        case id, name, transliteration, type, verses
        case totalVerses = "total_verses"
    }

    public init(
        id: Int,
        name: String,
        transliteration: String,
        type: String,
        totalVerses: Int,
        verses: [Verse]
    ) {
        self.id = id
        self.name = name
        self.transliteration = transliteration
        self.type = type
        self.totalVerses = totalVerses
        self.verses = verses
    }
}

public struct VerseReference: Codable, Hashable, Sendable {
    public let surahID: Int
    public let verseID: Int

    public init(surahID: Int, verseID: Int) {
        self.surahID = surahID
        self.verseID = verseID
    }
}

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum AccentTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case jade, gold, rose

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .jade: "Jade"
        case .gold: "Gold"
        case .rose: "Rose"
        }
    }
}

public enum ReminderMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case mixed, ayah, dua, surah, automatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mixed: "Ayahs & duas"
        case .ayah: "Random ayah"
        case .dua: "Quranic dua"
        case .surah: "Selected surah"
        case .automatic: "Automatic Quran"
        }
    }
}

public enum ReminderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ayah, dua, surah, automatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ayah: "Ayah"
        case .dua: "Dua"
        case .surah: "Surah"
        case .automatic: "Automatic Quran"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: AppTheme
    public var accent: AccentTheme
    public var intervalSeconds: Int
    public var mode: ReminderMode
    public var remindersEnabled: Bool
    public var arabicFontSize: Double
    public var autoAdvance: Bool
    public var language: AppLanguage

    public init(
        theme: AppTheme = .system,
        accent: AccentTheme = .jade,
        intervalSeconds: Int = 120,
        mode: ReminderMode = .mixed,
        remindersEnabled: Bool = true,
        arabicFontSize: Double = 32,
        autoAdvance: Bool = true,
        language: AppLanguage = .english
    ) {
        self.theme = theme
        self.accent = accent
        self.intervalSeconds = intervalSeconds
        self.mode = mode
        self.remindersEnabled = remindersEnabled
        self.arabicFontSize = arabicFontSize
        self.autoAdvance = autoAdvance
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case theme, accent, intervalSeconds, mode, remindersEnabled, arabicFontSize, autoAdvance, language
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case intervalMinutes
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        accent = try values.decodeIfPresent(AccentTheme.self, forKey: .accent) ?? .jade
        if let seconds = try values.decodeIfPresent(Int.self, forKey: .intervalSeconds) {
            intervalSeconds = seconds
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            intervalSeconds = (try legacy.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 2) * 60
        }
        mode = try values.decodeIfPresent(ReminderMode.self, forKey: .mode) ?? .mixed
        remindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        arabicFontSize = try values.decodeIfPresent(Double.self, forKey: .arabicFontSize) ?? 32
        autoAdvance = try values.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? true
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
    }
}

public struct ReminderContent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ReminderKind
    public let arabic: String
    public let title: String
    public let subtitle: String
    public let reference: VerseReference?

    public init(
        id: UUID = UUID(),
        kind: ReminderKind,
        arabic: String,
        title: String,
        subtitle: String,
        reference: VerseReference? = nil
    ) {
        self.id = id
        self.kind = kind
        self.arabic = arabic
        self.title = title
        self.subtitle = subtitle
        self.reference = reference
    }
}

public enum Celebration: Equatable, Identifiable, Sendable {
    case surah(Int)
    case khatm

    public var id: String {
        switch self {
        case let .surah(id): "surah-\(id)"
        case .khatm: "khatm"
        }
    }
}
