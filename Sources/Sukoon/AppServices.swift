import AppKit
import Foundation
import Observation
import ServiceManagement
import SukoonCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppServices {
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(UpdateFailure)
    }

    enum UpdateFailure: Equatable {
        case missingCurrentVersion
        case invalidCurrentVersion(String)
        case unexpectedResponse
        case httpStatus(Int)
        case invalidRelease
        case requestFailed(String)
        case couldNotOpenRelease

        func localizedMessage(_ localization: AppLocalization) -> String {
            switch self {
            case .missingCurrentVersion:
                localization.text("This app bundle does not contain a version number.")
            case let .invalidCurrentVersion(version):
                localization.format("The app version could not be compared: %@", version)
            case .unexpectedResponse:
                localization.text("GitHub returned an unexpected response.")
            case let .httpStatus(status):
                localization.format("GitHub could not provide the latest release (HTTP %@).", localization.number(status))
            case .invalidRelease:
                localization.text("GitHub returned an invalid release version or release link.")
            case let .requestFailed(reason):
                localization.format("The update check failed: %@", reason)
            case .couldNotOpenRelease:
                localization.text("The release page could not be opened.")
            }
        }
    }

    enum ReadingTransferState: Equatable {
        case idle
        case exported
        case imported
        case cancelled
        case failed(String)
    }

    private(set) var startupStatus: SMAppService.Status
    private(set) var startupError: String?
    private(set) var updateState: UpdateState = .idle
    private(set) var readingTransferState: ReadingTransferState = .idle
    let currentVersion: String?

    init() {
        startupStatus = SMAppService.mainApp.status
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Approval-pending registration is still a registered request, not an enabled login item.
    var launchAtLoginEnabled: Bool {
        startupStatus == .enabled || startupStatus == .requiresApproval
    }

    var requiresStartupApproval: Bool { startupStatus == .requiresApproval }

    func refreshStartupStatus() {
        startupStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        startupError = nil
        refreshStartupStatus()
        do {
            if enabled {
                if !launchAtLoginEnabled { try SMAppService.mainApp.register() }
            } else if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            startupError = error.localizedDescription
        }
        // Never optimistically save a Boolean: registration may require approval or fail.
        refreshStartupStatus()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// This is the sole network entry point; initialization and status refresh stay offline.
    func checkForUpdates() async {
        guard updateState != .checking else { return }
        updateState = .checking
        guard let currentVersion, !currentVersion.isEmpty else {
            updateState = .failed(.missingCurrentVersion)
            return
        }
        guard let installed = SemanticVersion(currentVersion, allowsShortVersion: true) else {
            updateState = .failed(.invalidCurrentVersion(currentVersion))
            return
        }

        let endpoint = URL(string: "https://api.github.com/repos/rayenfassatoui/Sukoon/releases/latest")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Sukoon/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.url == endpoint else {
                updateState = .failed(.unexpectedResponse)
                return
            }
            guard response.statusCode == 200 else {
                updateState = .failed(.httpStatus(response.statusCode))
                return
            }
            guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                  !release.draft, !release.prerelease,
                  let latest = SemanticVersion(release.tagName, allowsTagPrefix: true),
                  let releaseURL = Self.validatedReleaseURL(release.htmlURL, tag: release.tagName) else {
                updateState = .failed(.invalidRelease)
                return
            }
            if installed < latest {
                let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                updateState = .updateAvailable(version: version, url: releaseURL)
            } else {
                updateState = .upToDate
            }
        } catch {
            updateState = .failed(.requestFailed(error.localizedDescription))
        }
    }

    func openRelease() {
        guard case let .updateAvailable(_, url) = updateState else { return }
        // Only a URL validated from the public release response can enter this state.
        if !NSWorkspace.shared.open(url) {
            updateState = .failed(.couldNotOpenRelease)
        }
    }

    func exportReadingProgress(from store: AppStore, localization: AppLocalization) {
        let panel = NSSavePanel()
        panel.title = localization.text("Export reading progress")
        panel.message = localization.text("Save your read verses, reading position and bookmarks as a JSON backup.")
        panel.prompt = localization.text("Export")
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Sukoon-reading-progress.json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else {
            readingTransferState = .cancelled
            return
        }
        guard let url = panel.url else {
            reportTransferFailure(localization.text("The selected file could not be accessed."),
                                  title: "Reading progress could not be exported", localization: localization)
            return
        }
        do {
            let data = try store.exportReadingBackup()
            try data.write(to: url, options: .atomic)
            readingTransferState = .exported
        } catch {
            reportTransferFailure(error.localizedDescription,
                                  title: "Reading progress could not be exported", localization: localization)
        }
    }

    func importReadingProgress(into store: AppStore, localization: AppLocalization) {
        let panel = NSOpenPanel()
        panel.title = localization.text("Import reading progress")
        panel.message = localization.text("Choose a Sukoon reading-progress JSON backup.")
        panel.prompt = localization.text("Import")
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else {
            readingTransferState = .cancelled
            return
        }
        guard let url = panel.url else {
            reportTransferFailure(localization.text("The selected file could not be accessed."),
                                  title: "Reading progress could not be imported", localization: localization)
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = localization.text("Replace reading progress?")
            alert.informativeText = localization.text("This replaces your read verses, reading position and bookmarks with the backup. Your language, appearance and reminder settings will not change.")
            alert.addButton(withTitle: localization.text("Replace progress"))
            alert.addButton(withTitle: localization.text("Cancel"))
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            guard alert.runModal() == .alertFirstButtonReturn else {
                readingTransferState = .cancelled
                return
            }
            try store.importReadingBackup(data)
            readingTransferState = .imported
        } catch {
            reportTransferFailure(error.localizedDescription,
                                  title: "Reading progress could not be imported", localization: localization)
        }
    }

    private func reportTransferFailure(_ reason: String, title: String, localization: AppLocalization) {
        readingTransferState = .failed(reason)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localization.text(title)
        alert.informativeText = reason
        alert.addButton(withTitle: localization.text("OK"))
        alert.runModal()
    }

    private static func validatedReleaseURL(_ value: String, tag: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme == "https", components.host == "github.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.path == "/rayenfassatoui/Sukoon/releases/tag/\(tag)" else { return nil }
        return components.url
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }
}

/// SemVer precedence, including numeric prerelease identifiers; build metadata is ignored.
/// Bundle marketing versions may omit minor/patch components, which are treated as zero.
private struct SemanticVersion: Comparable {
    private let core: [String]
    private let prerelease: [String]

    init?(_ value: String, allowsShortVersion: Bool = false, allowsTagPrefix: Bool = false) {
        let version = allowsTagPrefix && value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard !version.isEmpty else { return nil }
        let metadataParts = version.split(separator: "+", omittingEmptySubsequences: false)
        guard metadataParts.count <= 2 else { return nil }
        if metadataParts.count == 2 {
            guard Self.validIdentifiers(metadataParts[1], numericLeadingZerosAllowed: true) else { return nil }
        }
        let versionParts = metadataParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (allowsShortVersion ? (1...3).contains(numbers.count) : numbers.count == 3),
              numbers.allSatisfy({ Self.isNumeric($0) && ($0.count == 1 || !$0.hasPrefix("0")) }) else { return nil }
        var normalizedCore = numbers.map(String.init)
        while normalizedCore.count < 3 { normalizedCore.append("0") }
        core = normalizedCore
        if versionParts.count == 2 {
            guard Self.validIdentifiers(versionParts[1], numericLeadingZerosAllowed: false) else { return nil }
            prerelease = versionParts[1].split(separator: ".").map(String.init)
        } else {
            prerelease = []
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.core == rhs.core && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.core, rhs.core) where left != right {
            return numericLess(left, right)
        }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = isNumeric(left)
            let rightNumeric = isNumeric(right)
            if leftNumeric && rightNumeric { return numericLess(left, right) }
            if leftNumeric != rightNumeric { return leftNumeric }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func numericLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    private static func isNumeric<S: StringProtocol>(_ value: S) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validIdentifiers(_ value: Substring, numericLeadingZerosAllowed: Bool) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else {
                return false
            }
            return numericLeadingZerosAllowed || !isNumeric(identifier) || identifier.count == 1 || !identifier.hasPrefix("0")
        }
    }
}
