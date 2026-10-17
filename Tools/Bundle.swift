#!/usr/bin/env swift
import AppKit
import CryptoKit
import Foundation

// Run from the package root; use --help for local and distribution options.
let help = """
Usage: swift Tools/Bundle.swift [--debug] [--sign-identity IDENTITY]
                               [--notarize-profile PROFILE] [--update-key-file PATH]

Options:
  --debug                     Build debug instead of release (not for notarization).
  --sign-identity IDENTITY     Exact Developer ID Application certificate name or SHA-1.
                              Requires a valid signing identity and private key in Keychain.
  --notarize-profile PROFILE   Notarize using an existing notarytool Keychain profile.
                              Requires --sign-identity and a release build.
  --update-key-file PATH       Sign the final ZIP and create build/appcast.xml for GitHub.
                              Requires a protected exported Sparkle Ed25519 key file
                              outside this checkout, matching Tools/UpdatePublicKey.txt.
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
  swift Tools/Bundle.swift --update-key-file "$HOME/.config/sukoon/update-key"

Prerequisites for distribution: a Developer ID Application certificate with its
private key in Keychain, Xcode's notarytool/stapler, and an authenticated Keychain
profile. Create the profile interactively (credentials stay in Keychain):
  xcrun notarytool store-credentials "YOUR_PROFILE"
No credentials or private keys are written into this script's artifacts.

Update signing uses Sparkle's sign_update with an explicit key file, never Keychain.
The exported key is Base64 of a 32-byte Ed25519 private seed (legacy 96-byte
Sparkle exports are also accepted). Restrict its permissions to 0600 or 0400.
Tools/UpdatePublicKey.txt must contain the matching Base64 32-byte public key.
Without --update-key-file, local builds still work, but no signed appcast is
generated and a stale build/appcast.xml is removed. Update signing does not
replace Developer ID signing or notarization.

Output: build/Sukoon.app, build/Sukoon-v1.4.0-macos-arm64.zip, build/SHA256SUMS
        build/appcast.xml only when --update-key-file is supplied.
"""

func invalidArguments(_ message: String) -> Never {
    fputs("Error: \(message)\nUse swift Tools/Bundle.swift --help for usage.\n", stderr)
    exit(EXIT_FAILURE)
}

struct BundleOptions {
    var debug = false
    var signingIdentity: String?
    var notarizationProfile: String?
    var updateKeyFile: String?

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--debug":
                guard !debug else { invalidArguments("Duplicate --debug option.") }
                debug = true
            case "--sign-identity", "--notarize-profile", "--update-key-file":
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
                } else if option == "--notarize-profile" {
                    guard notarizationProfile == nil else { invalidArguments("Duplicate --notarize-profile option.") }
                    notarizationProfile = value
                } else {
                    guard updateKeyFile == nil else { invalidArguments("Duplicate --update-key-file option.") }
                    updateKeyFile = value
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
let version = "1.4.0"
let buildNumber = "6"
let minimumSystemVersion = "26.0"
let releaseURL = "https://github.com/rayenfassatoui/Sukoon/releases/tag/v\(version)"
let archiveName = "Sukoon-v\(version)-macos-arm64.zip"
let downloadURL = "https://github.com/rayenfassatoui/Sukoon/releases/download/v\(version)/\(archiveName)"
let sparkleArtifact = root.appendingPathComponent(".build/artifacts/sparkle/Sparkle", isDirectory: true)
let sparkleFramework = sparkleArtifact.appendingPathComponent("Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework", isDirectory: true)
let updateSigningTool = sparkleArtifact.appendingPathComponent("bin/sign_update")
var buildEnvironment = ProcessInfo.processInfo.environment

func run(_ executable: String, _ arguments: [String], capture: Bool = false,
         suppressDiagnostics: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.environment = buildEnvironment
    let pipe = capture ? Pipe() : nil
    if let pipe { process.standardOutput = pipe }
    if suppressDiagnostics {
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
    }
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

func readUpdatePublicKey() throws -> (encoded: String, key: Curve25519.Signing.PublicKey) {
    let file = root.appendingPathComponent("Tools/UpdatePublicKey.txt")
    guard let text = try? String(contentsOf: file, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let data = Data(base64Encoded: text), data.count == 32,
          data.base64EncodedString() == text else {
        throw buildError("Tools/UpdatePublicKey.txt must contain a valid Base64 32-byte Sparkle public key.")
    }
    return (text, try Curve25519.Signing.PublicKey(rawRepresentation: data))
}

func resolveUpdateKeyFile(_ path: String, publicKey: Curve25519.Signing.PublicKey) throws -> URL {
    let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        .standardizedFileURL.resolvingSymlinksInPath()
    let checkout = root.resolvingSymlinksInPath().path
    guard file.path != checkout, !file.path.hasPrefix(checkout + "/") else {
        throw buildError("The update private key must be stored outside this checkout, never in source or build artifacts.")
    }
    let attributes = try manager.attributesOfItem(atPath: file.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          let permissions = attributes[.posixPermissions] as? NSNumber,
          [0o400, 0o600].contains(permissions.intValue & 0o7777),
          let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 1024 else {
        throw buildError("The update private key must be a regular, owner-readable file with permissions 0600 or 0400.")
    }
    guard let text = try? String(contentsOf: file, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let secret = Data(base64Encoded: text), [32, 96].contains(secret.count),
          secret.base64EncodedString() == text else {
        throw buildError("The update private key must be a Base64 Sparkle export (32-byte seed or legacy 96-byte key).")
    }
    let matchesPublicKey: Bool
    if secret.count == 32 {
        matchesPublicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
            .publicKey.rawRepresentation == publicKey.rawRepresentation
    } else {
        matchesPublicKey = secret.suffix(32) == publicKey.rawRepresentation
    }
    guard matchesPublicKey else {
        throw buildError("The update private key does not match Tools/UpdatePublicKey.txt. Existing output was not replaced.")
    }
    return file
}

func signUpdate(at file: URL, keyFile: URL,
                publicKey: Curve25519.Signing.PublicKey) throws -> (signature: String, length: Int) {
    // Sparkle can echo malformed key text in diagnostics. Never forward its output
    // except the validated public signature, even if a key file changes during a build.
    let signature = try run(updateSigningTool.path, [
        "--ed-key-file", keyFile.path, "-p", file.path
    ], capture: true, suppressDiagnostics: true)
    guard let decoded = Data(base64Encoded: signature), decoded.count == 64 else {
        throw buildError("Sparkle did not return a valid Ed25519 archive signature.")
    }
    let data = try Data(contentsOf: file, options: .mappedIfSafe)
    guard publicKey.isValidSignature(decoded, for: data) else {
        throw buildError("Sparkle's signature did not verify against Tools/UpdatePublicKey.txt. Existing output was not replaced.")
    }
    return (signature, data.count)
}

func validateUpdateSigningTool(keyFile: URL, publicKey: Curve25519.Signing.PublicKey) throws {
    if !manager.isExecutableFile(atPath: updateSigningTool.path) {
        _ = try run("/usr/bin/xcrun", ["swift", "package", "resolve"])
    }
    guard manager.isExecutableFile(atPath: updateSigningTool.path) else {
        throw buildError("Sparkle's resolved sign_update tool is missing or not executable at \(updateSigningTool.path).")
    }
    let directory = manager.temporaryDirectory.appendingPathComponent("Sukoon-update-key-check-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: directory) }
    let probe = directory.appendingPathComponent("key-check.bin")
    try Data("Sukoon update signing key verification\n".utf8).write(to: probe)
    // This also authenticates legacy exports whose private scalar cannot be
    // reconstructed from a CryptoKit seed.
    _ = try signUpdate(at: probe, keyFile: keyFile, publicKey: publicKey)
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
let updatePublicKey: (encoded: String, key: Curve25519.Signing.PublicKey)
let updateKeyFile: URL?
do {
    updatePublicKey = try readUpdatePublicKey()
    updateKeyFile = try options.updateKeyFile.map { try resolveUpdateKeyFile($0, publicKey: updatePublicKey.key) }
    if let updateKeyFile {
        try validateUpdateSigningTool(keyFile: updateKeyFile, publicKey: updatePublicKey.key)
    }
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
if updateKeyFile == nil {
    print("No --update-key-file supplied: no signed appcast will be generated; any stale generated appcast will be removed.")
} else {
    print("Update signing key verified against the pinned public key; signing uses the file only, not Keychain.")
}

func createZIP(of app: URL, at archive: URL) throws {
    if manager.fileExists(atPath: archive.path) { try manager.removeItem(at: archive) }
    _ = try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
}

func signCode(at code: URL, preserveEntitlements: Bool = false) throws {
    var arguments = ["--force", "--sign", signingIdentity ?? "-"]
    if signingIdentity != nil {
        arguments += ["--options", "runtime", "--timestamp"]
    }
    if preserveEntitlements { arguments.append("--preserve-metadata=entitlements") }
    arguments.append(code.path)
    _ = try run("/usr/bin/codesign", arguments)
}

func signSparkleFramework(at framework: URL) throws {
    let current = framework.appendingPathComponent("Versions/Current", isDirectory: true)
    // Sign nested code explicitly inside-out, never --deep. Downloader may carry
    // entitlements that do not apply to the other Sparkle processes.
    try signCode(at: current.appendingPathComponent("XPCServices/Installer.xpc"))
    try signCode(at: current.appendingPathComponent("XPCServices/Downloader.xpc"), preserveEntitlements: true)
    try signCode(at: current.appendingPathComponent("Autoupdate"))
    try signCode(at: current.appendingPathComponent("Updater.app"))
    try signCode(at: framework)
}

func createAppcast(at file: URL, signature: String, length: Int) throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Sukoon Updates</title>
        <link>\(releaseURL)</link>
        <description>Sukoon releases for macOS Apple Silicon.</description>
        <language>en</language>
        <item>
          <title>Sukoon \(version)</title>
          <link>\(releaseURL)</link>
          <pubDate>\(formatter.string(from: Date()))</pubDate>
          <sparkle:version>\(buildNumber)</sparkle:version>
          <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>\(minimumSystemVersion)</sparkle:minimumSystemVersion>
          <enclosure url="\(downloadURL)" length="\(length)" type="application/octet-stream" sparkle:edSignature="\(signature)" />
        </item>
      </channel>
    </rss>

    """
    try feed.write(to: file, atomically: true, encoding: .utf8)
}

func replaceGeneratedOutput(from source: URL, at destination: URL) throws {
    if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
    try manager.moveItem(at: source, to: destination)
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
guard manager.fileExists(atPath: sparkleFramework.path),
      manager.fileExists(atPath: sparkleArtifact.appendingPathComponent("LICENSE").path) else {
    throw buildError("The resolved Sparkle framework or license is missing. Resolve the pinned Swift package before bundling.")
}
let outputDirectory = root.appendingPathComponent("build", isDirectory: true)
let stagingDirectory = outputDirectory.appendingPathComponent(".Sukoon-packaging-\(UUID().uuidString)", isDirectory: true)
try manager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: stagingDirectory) }
// Keep existing generated output intact until the app, archive and any requested
// update signature are complete. Never replace a user-installed application.
let app = stagingDirectory.appendingPathComponent("Sukoon.app", isDirectory: true)
let contents = app.appendingPathComponent("Contents", isDirectory: true)
let executables = contents.appendingPathComponent("MacOS", isDirectory: true)
let resources = contents.appendingPathComponent("Resources", isDirectory: true)
let frameworks = contents.appendingPathComponent("Frameworks", isDirectory: true)
try manager.createDirectory(at: executables, withIntermediateDirectories: true)
try manager.createDirectory(at: resources, withIntermediateDirectories: true)
try manager.createDirectory(at: frameworks, withIntermediateDirectories: true)
let embeddedSparkle = frameworks.appendingPathComponent("Sparkle.framework", isDirectory: true)
// Copy the complete framework, including its versioned symlinks, helper code,
// localized resources and executable permissions. Do not thin or flatten it.
_ = try run("/usr/bin/ditto", ["--rsrc", "--extattr", sparkleFramework.path, embeddedSparkle.path])
try manager.copyItem(at: sparkleArtifact.appendingPathComponent("LICENSE"),
                     to: resources.appendingPathComponent("Sparkle-LICENSE.txt"))
try manager.copyItem(at: products.appendingPathComponent("Sukoon"), to: executables.appendingPathComponent("Sukoon"))
let resourceBundles = try manager.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "bundle" && $0.lastPathComponent.hasPrefix("Sukoon_") }
for bundle in resourceBundles { try manager.copyItem(at: bundle, to: resources.appendingPathComponent(bundle.lastPathComponent)) }
try createIcon(in: resources)
let info: [String: Any] = [
    "CFBundleName": "Sukoon", "CFBundleDisplayName": "Sukoon", "CFBundleExecutable": "Sukoon",
    "CFBundleIdentifier": "app.sukoon.mac", "CFBundlePackageType": "APPL", "CFBundleIconFile": "Sukoon",
    "CFBundleShortVersionString": version, "CFBundleVersion": buildNumber, "LSMinimumSystemVersion": minimumSystemVersion,
    "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "ar"],
    "LSUIElement": true, "NSHighResolutionCapable": true, "NSPrincipalClass": "NSApplication",
    "LSApplicationCategoryType": "public.app-category.lifestyle",
    "SUFeedURL": "https://github.com/rayenfassatoui/Sukoon/releases/latest/download/appcast.xml",
    "SUPublicEDKey": updatePublicKey.encoded, "SUVerifyUpdateBeforeExtraction": true,
    "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false, "SUAllowsAutomaticUpdates": false,
    "SUEnableSystemProfiling": false, "SUShowReleaseNotes": false, "SUEnableJavaScript": false,
    "NSHumanReadableCopyright": "Quran dataset: Quran JSON by Risan, CC BY-SA 4.0. See Settings for source attribution."
]
let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
try plist.write(to: contents.appendingPathComponent("Info.plist"))
try signSparkleFramework(at: embeddedSparkle)
try signCode(at: app)
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
let archive = app.deletingLastPathComponent().appendingPathComponent(archiveName)
try createZIP(of: app, at: archive)
let checksum = try run("/usr/bin/shasum", ["-a", "256", archive.path], capture: true)
guard let digest = checksum.split(whereSeparator: { $0.isWhitespace }).first,
      digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else {
    throw buildError("Could not read the distribution ZIP's SHA-256 checksum.")
}
let checksums = stagingDirectory.appendingPathComponent("SHA256SUMS")
try "\(digest)  \(archiveName)\n".write(to: checksums, atomically: true, encoding: .utf8)
let appcast = stagingDirectory.appendingPathComponent("appcast.xml")
if let updateKeyFile {
    let signed = try signUpdate(at: archive, keyFile: updateKeyFile, publicKey: updatePublicKey.key)
    try createAppcast(at: appcast, signature: signed.signature, length: signed.length)
}

let outputApp = outputDirectory.appendingPathComponent("Sukoon.app", isDirectory: true)
let outputArchive = outputDirectory.appendingPathComponent(archiveName)
let outputChecksums = outputDirectory.appendingPathComponent("SHA256SUMS")
let outputAppcast = outputDirectory.appendingPathComponent("appcast.xml")
// Never leave an earlier feed referring to a ZIP replaced by an unsigned local build.
if manager.fileExists(atPath: outputAppcast.path) { try manager.removeItem(at: outputAppcast) }
try replaceGeneratedOutput(from: app, at: outputApp)
try replaceGeneratedOutput(from: archive, at: outputArchive)
try replaceGeneratedOutput(from: checksums, at: outputChecksums)
if updateKeyFile != nil { try replaceGeneratedOutput(from: appcast, at: outputAppcast) }
let distributionStatus = options.notarizationProfile != nil
    ? "Developer ID signed, notarized, stapled, and Gatekeeper assessed."
    : signingIdentity != nil ? "Developer ID signed, NOT notarized." : "Ad-hoc signed, NOT notarized (local use only)."
let updateStatus = updateKeyFile != nil
    ? "Appcast: \(outputAppcast.path) (ZIP Ed25519 signature verified against the pinned public key)."
    : "No signed appcast generated; any stale build/appcast.xml was removed."
print("\nBuilt \(outputApp.path)\n\(distributionStatus)\nZIP: \(outputArchive.path)\nChecksums: \(outputChecksums.path)\n\(updateStatus)\nLaunch: open build/Sukoon.app")
