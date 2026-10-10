#!/usr/bin/env swift
import AppKit
import Foundation

// Run from the package root: swift Tools/Bundle.swift [--debug]
let manager = FileManager.default
let root = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
let configuration = CommandLine.arguments.contains("--debug") ? "debug" : "release"
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

_ = try run("/usr/bin/xcrun", ["swift", "build", "-c", configuration])
let binaryPath = try run("/usr/bin/xcrun", ["swift", "build", "-c", configuration, "--show-bin-path"], capture: true)
let products = URL(fileURLWithPath: binaryPath, isDirectory: true)
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
    "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1", "LSMinimumSystemVersion": "26.0",
    "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "ar"],
    "LSUIElement": true, "NSHighResolutionCapable": true, "NSPrincipalClass": "NSApplication",
    "LSApplicationCategoryType": "public.app-category.lifestyle",
    "NSHumanReadableCopyright": "Quran dataset: Quran JSON by Risan, CC BY-SA 4.0. See Settings for source attribution."
]
let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
try plist.write(to: contents.appendingPathComponent("Info.plist"))
_ = try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
print("\nBuilt \(app.path)\nLaunch: open build/Sukoon.app")
