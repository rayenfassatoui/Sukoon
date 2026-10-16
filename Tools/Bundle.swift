#!/usr/bin/env swift
import AppKit
import Foundation

// Run from the package root; use --help for local and distribution options.
let help = """
Usage: swift Tools/Bundle.swift [--debug] [--sign-identity IDENTITY] [--notarize-profile PROFILE]

Options:
  --debug                     Build debug instead of release (not for notarization).
  --sign-identity IDENTITY     Exact Developer ID Application certificate name or SHA-1.
                              Requires a valid signing identity and private key in Keychain.
  --notarize-profile PROFILE   Notarize using an existing notarytool Keychain profile.
                              Requires --sign-identity and a release build.
  --help, -h                  Show this help (cannot be combined with other options).

Default: release arm64, ad-hoc signed, NOT notarized; suitable for local use only.
Developer ID signing uses hardened runtime and a secure timestamp. Without a
notarization profile it remains NOT notarized. Apple Development is not supported.
Notarization submits a temporary ZIP, waits for Accepted, staples and validates
the app, and checks Gatekeeper before creating the final distribution ZIP.

Examples:
  swift Tools/Bundle.swift
  swift Tools/Bundle.swift --debug
  swift Tools/Bundle.swift --sign-identity "Developer ID Application: YOUR NAME (TEAMID)" --notarize-profile "YOUR_PROFILE"

Prerequisites for distribution: a Developer ID Application certificate with its
private key in Keychain, Xcode's notarytool/stapler, and an authenticated Keychain
profile. Create the profile interactively (credentials stay in Keychain):
  xcrun notarytool store-credentials "YOUR_PROFILE"
No credentials are accepted by this script or written into its artifacts.

Output: build/Sukoon.app, build/Sukoon-v1.1.0-macos-arm64.zip, build/SHA256SUMS
"""

func invalidArguments(_ message: String) -> Never {
    fputs("Error: \(message)\nUse swift Tools/Bundle.swift --help for usage.\n", stderr)
    exit(EXIT_FAILURE)
}

struct BundleOptions {
    var debug = false
    var signingIdentity: String?
    var notarizationProfile: String?

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--debug":
                guard !debug else { invalidArguments("Duplicate --debug option.") }
                debug = true
            case "--sign-identity", "--notarize-profile":
                guard index + 1 < arguments.count else {
                    invalidArguments("\(option) requires a value.")
                }
                let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !value.hasPrefix("-") else {
                    invalidArguments("\(option) requires a nonempty value.")
                }
                if option == "--sign-identity" {
                    guard signingIdentity == nil else { invalidArguments("Duplicate --sign-identity option.") }
                    signingIdentity = value
                } else {
                    guard notarizationProfile == nil else { invalidArguments("Duplicate --notarize-profile option.") }
                    notarizationProfile = value
                }
                index += 1
            default:
                invalidArguments("Unknown option: \(option)")
            }
            index += 1
        }
        if notarizationProfile != nil {
            guard signingIdentity != nil else {
                invalidArguments("--notarize-profile requires --sign-identity.")
            }
            guard !debug else { invalidArguments("Notarization requires a release build; omit --debug.") }
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    guard arguments.count == 1 else { invalidArguments("--help cannot be combined with other options.") }
    print(help)
    exit(EXIT_SUCCESS)
}
let options = BundleOptions(arguments: arguments)
let manager = FileManager.default
let root = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
let configuration = options.debug ? "debug" : "release"
let version = "1.3.0"
let buildNumber = "4"
var buildEnvironment = ProcessInfo.processInfo.environment

func run(_ executable: String, _ arguments: [String], capture: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.environment = buildEnvironment
    let pipe = capture ? Pipe() : nil
    if let pipe { process.standardOutput = pipe }
    try process.run()
    let data = pipe?.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "Sukoon.Build", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(executable) failed (\(process.terminationStatus))"])
    }
    return data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

if buildEnvironment["DEVELOPER_DIR"] == nil {
    let selectedDeveloper = try run("/usr/bin/xcode-select", ["-p"], capture: true)
    let xcodeDeveloper = "/Applications/Xcode.app/Contents/Developer"
    if selectedDeveloper.contains("CommandLineTools"), manager.fileExists(atPath: xcodeDeveloper) {
        buildEnvironment["DEVELOPER_DIR"] = xcodeDeveloper
        print("Using Xcode for SwiftUI compiler plugins (system selection is unchanged).")
    }
}

func buildError(_ message: String) -> NSError {
    NSError(domain: "Sukoon.Build", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

func resolveSigningIdentity(_ requested: String) throws -> String {
    let output = try run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"], capture: true)
    let pattern = try NSRegularExpression(
        pattern: #"^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"\s*$"#,
        options: .anchorsMatchLines
    )
    let text = output as NSString
    let identities = pattern.matches(in: output, range: NSRange(location: 0, length: text.length))
        .map { match in
            (hash: text.substring(with: match.range(at: 1)), name: text.substring(with: match.range(at: 2)))
        }
    let matches = identities.filter {
        $0.name == requested || $0.hash.caseInsensitiveCompare(requested) == .orderedSame
    }
    guard !matches.isEmpty else {
        throw buildError("No valid signing identity matches the requested name or SHA-1. Install a Developer ID Application certificate and its private key in Keychain.")
    }
    guard matches.count == 1, let identity = matches.first else {
        throw buildError("The signing name is ambiguous. Pass the SHA-1 of the intended Developer ID Application identity.")
    }
    guard identity.name.hasPrefix("Developer ID Application: ") else {
        throw buildError("Distribution signing requires Developer ID Application; Apple Development and other certificate types are not supported.")
    }
    return identity.hash
}

// Resolve all credentials and tool prerequisites before building or replacing output.
let signingIdentity: String?
do {
    signingIdentity = try options.signingIdentity.map { try resolveSigningIdentity($0) }
    if let profile = options.notarizationProfile {
        _ = try run("/usr/bin/xcrun", ["--find", "notarytool"], capture: true)
        _ = try run("/usr/bin/xcrun", ["--find", "stapler"], capture: true)
        // This read-only authenticated request rejects missing/invalid Keychain profiles early.
        _ = try run("/usr/bin/xcrun", [
            "notarytool", "history", "--keychain-profile", profile, "--output-format", "json"
        ], capture: true)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
if signingIdentity == nil {
    print("Local build: ad-hoc signed, NOT notarized.")
} else if options.notarizationProfile == nil {
    print("Developer ID signed build, NOT notarized.")
} else {
    print("Developer ID signed release; notarization must succeed before distribution artifacts are created.")
}

func createZIP(of app: URL, at archive: URL) throws {
    if manager.fileExists(atPath: archive.path) { try manager.removeItem(at: archive) }
    _ = try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
}

struct NotarizationResult: Decodable {
    let id: String
    let status: String
}

func createIcon(in directory: URL) throws {
    let iconset = directory.appendingPathComponent("Sukoon.iconset", isDirectory: true)
    try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: iconset) }
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "Sukoon.Build", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not render the app icon"])
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            let shape = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
            NSGradient(starting: NSColor(red: 0.15, green: 0.36, blue: 0.31, alpha: 1),
                       ending: NSColor(red: 0.065, green: 0.22, blue: 0.19, alpha: 1))?.draw(in: shape, angle: -70)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            shape.lineWidth = 3
            shape.stroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 180, y: 180, width: 664, height: 664))
            NSColor(red: 0.89, green: 0.82, blue: 0.62, alpha: 0.25).setStroke()
            ring.lineWidth = 2
            ring.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: 360, weight: .light)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(red: 0.96, green: 0.92, blue: 0.79, alpha: 1)]))
            if let image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                image.draw(in: NSRect(x: 290, y: 275, width: 444, height: 474))
            }
            NSGraphicsContext.restoreGraphicsState()
            let suffix = scale == 2 ? "@2x" : ""
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Sukoon.Build", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not encode the app icon"])
            }
            try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
    _ = try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", directory.appendingPathComponent("Sukoon.icns").path])
}

_ = try run("/usr/bin/xcrun", ["swift", "build", "-c", configuration, "--arch", "arm64"])
let binaryPath = try run("/usr/bin/xcrun", ["swift", "build", "-c", configuration, "--arch", "arm64", "--show-bin-path"], capture: true)
let products = URL(fileURLWithPath: binaryPath, isDirectory: true)
_ = try run("/usr/bin/lipo", ["-verify_arch", "arm64", products.appendingPathComponent("Sukoon").path])
let app = root.appendingPathComponent("build/Sukoon.app", isDirectory: true)
// Only replace this tool's generated output, never a user-installed app.
if manager.fileExists(atPath: app.path) { try manager.removeItem(at: app) }
let contents = app.appendingPathComponent("Contents", isDirectory: true)
let executables = contents.appendingPathComponent("MacOS", isDirectory: true)
let resources = contents.appendingPathComponent("Resources", isDirectory: true)
try manager.createDirectory(at: executables, withIntermediateDirectories: true)
try manager.createDirectory(at: resources, withIntermediateDirectories: true)
try manager.copyItem(at: products.appendingPathComponent("Sukoon"), to: executables.appendingPathComponent("Sukoon"))
let resourceBundles = try manager.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "bundle" && $0.lastPathComponent.hasPrefix("Sukoon_") }
for bundle in resourceBundles { try manager.copyItem(at: bundle, to: resources.appendingPathComponent(bundle.lastPathComponent)) }
try createIcon(in: resources)
let info: [String: Any] = [
    "CFBundleName": "Sukoon", "CFBundleDisplayName": "Sukoon", "CFBundleExecutable": "Sukoon",
    "CFBundleIdentifier": "app.sukoon.mac", "CFBundlePackageType": "APPL", "CFBundleIconFile": "Sukoon",
    "CFBundleShortVersionString": version, "CFBundleVersion": buildNumber, "LSMinimumSystemVersion": "26.0",
    "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "ar"],
    "LSUIElement": true, "NSHighResolutionCapable": true, "NSPrincipalClass": "NSApplication",
    "LSApplicationCategoryType": "public.app-category.lifestyle",
    "NSHumanReadableCopyright": "Quran dataset: Quran JSON by Risan, CC BY-SA 4.0. See Settings for source attribution."
]
let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
try plist.write(to: contents.appendingPathComponent("Info.plist"))
if let signingIdentity {
    _ = try run("/usr/bin/codesign", [
        "--force", "--sign", signingIdentity, "--options", "runtime", "--timestamp", app.path
    ])
} else {
    _ = try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
}
_ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", app.path])

if let profile = options.notarizationProfile {
    let submissionDirectory = manager.temporaryDirectory
        .appendingPathComponent("Sukoon-notarization-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: submissionDirectory, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: submissionDirectory) }
    let submissionZIP = submissionDirectory.appendingPathComponent("Sukoon.zip")
    try createZIP(of: app, at: submissionZIP)
    let response = try run("/usr/bin/xcrun", [
        "notarytool", "submit", submissionZIP.path, "--keychain-profile", profile,
        "--wait", "--output-format", "json"
    ], capture: true)
    let result = try JSONDecoder().decode(NotarizationResult.self, from: Data(response.utf8))
    guard result.status == "Accepted" else {
        throw buildError("Notarization was not Accepted (status: \(result.status), submission: \(result.id)). No new distribution ZIP was created. Retrieve the log with xcrun notarytool log using the same Keychain profile.")
    }
    print("Notarization Accepted (submission: \(result.id)).")
    _ = try run("/usr/bin/xcrun", ["stapler", "staple", app.path])
    _ = try run("/usr/bin/xcrun", ["stapler", "validate", app.path])
    _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", app.path])
    _ = try run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", app.path])
}

// Archive only the final app: notarized distributions include the stapled ticket.
let archiveName = "Sukoon-v\(version)-macos-arm64.zip"
let archive = app.deletingLastPathComponent().appendingPathComponent(archiveName)
try createZIP(of: app, at: archive)
let checksum = try run("/usr/bin/shasum", ["-a", "256", archive.path], capture: true)
guard let digest = checksum.split(whereSeparator: { $0.isWhitespace }).first,
      digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else {
    throw buildError("Could not read the distribution ZIP's SHA-256 checksum.")
}
let checksums = app.deletingLastPathComponent().appendingPathComponent("SHA256SUMS")
try "\(digest)  \(archiveName)\n".write(to: checksums, atomically: true, encoding: .utf8)
let distributionStatus = options.notarizationProfile != nil
    ? "Developer ID signed, notarized, stapled, and Gatekeeper assessed."
    : signingIdentity != nil ? "Developer ID signed, NOT notarized." : "Ad-hoc signed, NOT notarized (local use only)."
print("\nBuilt \(app.path)\n\(distributionStatus)\nZIP: \(archive.path)\nChecksums: \(checksums.path)\nLaunch: open build/Sukoon.app")
