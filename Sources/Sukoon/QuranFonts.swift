import CoreText
import Foundation
import Observation

/// A selectable Arabic font face. The identifier is the face's PostScript name,
/// which remains stable when the user's saved settings are encoded.
struct QuranFontOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isBundled: Bool
}

/// Registers the bundled Quran fonts for this process and discovers every
/// installed face that can shape Arabic text. No font is installed globally,
/// and refresh never performs network or file-download work.
@MainActor
@Observable
final class QuranFonts {
    static let shared = QuranFonts()

    private(set) var options: [QuranFontOption] = []
    private(set) var registrationErrors: [String] = []
    private var availableFontNames = Set<String>()
    private var bundledFontDescriptors: [String: CTFontDescriptor] = [:]

    @ObservationIgnored
    private var registeredBundledFontFileNames = Set<String>()

    @ObservationIgnored
    private var cachedFont: (name: String, size: CGFloat, font: CTFont)?

    private static let bundledFontFileNames = [
        "oldmadina.otf",
        "madina.otf",
        "indopak.otf",
        "KFGQPCNastaleeq-Regular.ttf",
        "UthmanicHafs_V22.ttf",
        "AmiriQuran.ttf"
    ]

    private static let defaultFontName = "GeezaPro"
    private static let arabicProbeCharacters: [UniChar] = [
        0x0627, // alef
        0x0628, // beh
        0x062C, // jeem
        0x062F, // dal
        0x0631, // reh
        0x0633, // seen
        0x0635, // sad
        0x0639, // ain
        0x0641, // feh
        0x0642, // qaf
        0x0643, // kaf
        0x0644, // lam
        0x0645, // meem
        0x0646, // noon
        0x0647, // heh
        0x0648, // waw
        0x064A  // yeh
    ]

    init() {
        refreshInstalledFonts()
    }

    /// Returns a currently available PostScript name, falling back to the
    /// system Arabic face used by the original app when a saved face was
    /// removed from the machine.
    func resolvedFontName(_ storedName: String) -> String {
        guard availableFontNames.contains(storedName) else {
            return Self.defaultFontName
        }
        return storedName
    }

    /// Use the bundled file's descriptor rather than asking SwiftUI to look
    /// the face up again by name. This also keeps reminder measurement exact.
    func font(_ storedName: String, size: CGFloat) -> CTFont {
        let name = resolvedFontName(storedName)
        if let cachedFont, cachedFont.name == name, cachedFont.size == size {
            return cachedFont.font
        }
        let font: CTFont
        if let descriptor = bundledFontDescriptors[name] {
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        } else {
            font = CTFontCreateWithName(name as CFString, size, nil)
        }
        cachedFont = (name, size, font)
        return font
    }

    /// Registers all bundled font bytes with CoreText for this process, then
    /// rebuilds the complete installed Arabic-capable face catalogue.
    func refreshInstalledFonts() {
        cachedFont = nil
        registrationErrors.removeAll(keepingCapacity: true)
        registerBundledFonts()
        options = discoverArabicFonts()
        availableFontNames = Set(options.map(\.id))
    }

    private func registerBundledFonts() {
        for fileName in Self.bundledFontFileNames {
            guard !registeredBundledFontFileNames.contains(fileName) else { continue }
            guard let url = bundledFontURL(fileName) else {
                registrationErrors.append("\(fileName): bundled font resource is missing")
                continue
            }
            guard CTFontManagerIsSupportedFont(url as CFURL) else {
                registrationErrors.append("\(fileName): this macOS version does not support the bundled font format")
                continue
            }

            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  !descriptors.isEmpty else {
                registrationErrors.append("\(fileName): bundled font has no readable faces")
                continue
            }
            let expectedPostScriptNames = descriptors.compactMap {
                CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
            }
            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &registrationError
            )

            let reason = registrationError?.takeRetainedValue().localizedDescription
            // A face may already have been activated by another framework.
            guard registered || (!expectedPostScriptNames.isEmpty && expectedPostScriptNames.allSatisfy(isAvailable(_:))) else {
                registrationErrors.append("\(fileName): \(reason ?? "CoreText rejected the font resource")")
                continue
            }
            for descriptor in descriptors {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                    bundledFontDescriptors[name] = descriptor
                }
            }
            registeredBundledFontFileNames.insert(fileName)
        }
    }

    private func bundledFontURL(_ fileName: String) -> URL? {
        let fileURL = URL(fileURLWithPath: fileName)
        let resourceName = fileURL.deletingPathExtension().lastPathComponent
        let resourceExtension = fileURL.pathExtension
        return Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Resources/Fonts"
        )
    }

    private func isAvailable(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    private func discoverArabicFonts() -> [QuranFontOption] {
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        var seen = Set<String>()
        var discovered: [QuranFontOption] = []
        discovered.reserveCapacity(names.count + bundledFontDescriptors.count)
        var glyphs = [CGGlyph](repeating: 0, count: Self.arabicProbeCharacters.count)

        func append(_ font: CTFont, isBundled: Bool) {
            let postScriptName = CTFontCopyPostScriptName(font) as String
            guard !postScriptName.isEmpty, seen.insert(postScriptName).inserted else { return }
            guard supportsArabic(font, glyphs: &glyphs) else { return }

            let familyName = CTFontCopyFamilyName(font) as String
            let fullName = CTFontCopyFullName(font) as String
            let displayName = fullName.isEmpty ? familyName : fullName
            discovered.append(QuranFontOption(id: postScriptName, name: displayName, isBundled: isBundled))
        }

        // Process-registered fonts need not be enumerated like installed faces.
        // The app's own resources are authoritative, even on a clean Mac.
        for descriptor in bundledFontDescriptors.values {
            append(CTFontCreateWithFontDescriptor(descriptor, 16, nil), isBundled: true)
        }
        for name in names {
            append(CTFontCreateWithName(name as CFString, 16, nil), isBundled: false)
        }

        return discovered.sorted { left, right in
            if left.isBundled != right.isBundled { return left.isBundled }
            let comparison = left.name.caseInsensitiveCompare(right.name)
            return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
        }
    }

    private func supportsArabic(_ font: CTFont, glyphs: inout [CGGlyph]) -> Bool {
        Self.arabicProbeCharacters.withUnsafeBufferPointer { characters in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                guard let characterBase = characters.baseAddress,
                      let glyphBase = glyphBuffer.baseAddress else { return }
                _ = CTFontGetGlyphsForCharacters(
                    font,
                    characterBase,
                    glyphBase,
                    Self.arabicProbeCharacters.count
                )
            }
        }

        // A face that covers several independent Arabic base letters is an
        // Arabic-capable text face. Individual Quran marks vary by font, so
        // requiring every mark would hide otherwise usable installed fonts.
        let coveredBaseCharacters = glyphs.reduce(into: 0) { count, glyph in
            if glyph != 0 { count += 1 }
        }
        return coveredBaseCharacters >= 4
    }
}
