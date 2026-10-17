import Foundation
import Sparkle

enum UpdateInstallationState: Equatable {
    case checking, downloading, extracting, installing, waitingForRelaunch, installed
    case cancelled
    case failed(String)
}

/// AppServices owns discovery and must retain this adapter through the installation.
/// Only call start after the user accepts downloading, installation and relaunch.
@MainActor
final class UpdateInstaller {
    private let updater: SPUUpdater
    private let driver: UpdateInstallationDriver
    private var updaterStarted = false

    init(hostBundle: Bundle = .main,
         onStateChange: @escaping @MainActor (UpdateInstallationState) -> Void) {
        let driver = UpdateInstallationDriver(onStateChange: onStateChange)
        self.driver = driver
        updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle,
                             userDriver: driver, delegate: driver)
    }

    /// Both URLs come from the validated GitHub release selected by AppServices.
    func start(version: String, archiveURL: URL, feedURL: URL) throws {
        guard !driver.isRunning, !updater.sessionInProgress else {
            throw installationError("An update installation is already in progress.")
        }

        // The delegate must provide the release-specific feed before Sparkle starts.
        driver.begin(version: version, archiveURL: archiveURL, feedURL: feedURL)
        do {
            guard !version.isEmpty else {
                throw installationError("The selected release does not contain a version number.")
            }
            if !updaterStarted {
                try updater.start()
                updaterStarted = true
            }
            guard updater.canCheckForUpdates, !updater.sessionInProgress else {
                throw installationError("Sparkle cannot begin an update installation right now.")
            }
            // Start in this run-loop turn, before Sparkle's initial scheduled cycle.
            updater.checkForUpdates()
        } catch {
            driver.failedToStart(error)
            throw error
        }
    }

    /// Cancellation is supported while checking/downloading, not after extraction starts.
    /// A cancelled state is delivered only after Sparkle confirms its session has ended.
    func cancel() {
        driver.cancel()
    }

    func retryRelaunch() {
        driver.retryRelaunch()
    }
}

private func installationError(_ message: String) -> NSError {
    NSError(domain: "Sukoon.UpdateInstaller", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
}

/// Sparkle annotates both protocols and all their callbacks with MainActor.
/// This separate driver never retains its owning adapter or updater. In particular,
/// passing the adapter itself as userDriver would create an updater retain cycle.
@MainActor
private final class UpdateInstallationDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    private struct ExpectedUpdate {
        let version: String
        let archiveURL: URL
        let feedURL: URL
    }

    private let onStateChange: @MainActor (UpdateInstallationState) -> Void
    private var expectedUpdate: ExpectedUpdate?
    private var state: UpdateInstallationState?
    private var cancellation: (() -> Void)?
    private var relaunchHandler: (() -> Void)?
    private var cancellationRequested = false
    private var failureMessage: String?
    private var validatedUpdate = false
    private var installationCompleted = false
    private(set) var isRunning = false

    init(onStateChange: @escaping @MainActor (UpdateInstallationState) -> Void) {
        self.onStateChange = onStateChange
        super.init()
    }

    func begin(version: String, archiveURL: URL, feedURL: URL) {
        expectedUpdate = ExpectedUpdate(version: version, archiveURL: archiveURL, feedURL: feedURL)
        cancellation = nil
        relaunchHandler = nil
        cancellationRequested = false
        failureMessage = nil
        validatedUpdate = false
        installationCompleted = false
        isRunning = true
        publish(.checking)
    }

    func failedToStart(_ error: any Error) {
        cancellation = nil
        relaunchHandler = nil
        isRunning = false
        recordFailure(error)
    }

    func cancel() {
        guard isRunning, failureMessage == nil, !cancellationRequested,
              state == .checking || state == .downloading else { return }
        cancellationRequested = true
        // Before Sparkle supplies a callback, keep the request pending. Its delegate
        // or next cancellable callback will reject/cancel the operation instead.
        invokeCancellation()
    }

    func retryRelaunch() {
        guard isRunning, state == .waitingForRelaunch, !cancellationRequested,
              failureMessage == nil else { return }
        relaunchHandler?()
    }

    private func invokeCancellation() {
        let handler = cancellation
        cancellation = nil
        handler?()
    }

    private func publish(_ newState: UpdateInstallationState) {
        guard state != newState else { return }
        state = newState
        onStateChange(newState)
    }

    private func advance(to newState: UpdateInstallationState) {
        guard isRunning, failureMessage == nil, !cancellationRequested,
              !installationCompleted else { return }
        publish(newState)
    }

    private func recordFailure(_ error: any Error) {
        guard failureMessage == nil else { return }
        relaunchHandler = nil
        let message = Self.description(of: error)
        failureMessage = message
        publish(.failed(message))
    }

    private static func description(of error: any Error) -> String {
        let error = error as NSError
        var description = error.localizedDescription
        if let reason = error.localizedFailureReason, !description.contains(reason) {
            description += "\n" + reason
        }
        if let suggestion = error.localizedRecoverySuggestion, !description.contains(suggestion) {
            description += "\n" + suggestion
        }
        return description
    }

    private func receive(_ error: any Error) {
        let error = error as NSError
        let cancelledByUser = (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
            || (error.domain == SUSparkleErrorDomain
                && error.code == Int(SUError.installationCanceledError.rawValue))
        let cancelledRequest = cancellationRequested && error.domain == NSURLErrorDomain
            && error.code == NSURLErrorCancelled
        if cancelledByUser || cancelledRequest {
            cancellationRequested = true
        } else {
            recordFailure(error)
        }
    }

    private func validate(_ item: SUAppcastItem) throws {
        guard isRunning, let expectedUpdate else {
            throw installationError("No release was selected for installation.")
        }
        guard !item.isInformationOnlyUpdate else {
            throw installationError("This release only provides update information. Download it from the GitHub release page instead.")
        }
        guard item.displayVersionString == expectedUpdate.version else {
            throw installationError("The update feed version does not match the selected release (\(expectedUpdate.version)).")
        }
        guard let archiveURL = item.fileURL else {
            throw installationError("The update feed does not provide an archive for the selected release.")
        }
        guard archiveURL.absoluteString == expectedUpdate.archiveURL.absoluteString else {
            throw installationError("The update feed does not point to the selected GitHub release archive.")
        }
        guard !item.isDeltaUpdate, item.installationType == "application" else {
            throw installationError("The selected release is not a full application update.")
        }
        // Sparkle, not this adapter, verifies the archive's Ed25519 signature using
        // SUPublicEDKey and SUVerifyUpdateBeforeExtraction from the host Info.plist.
    }

    // MARK: Sparkle updater delegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        expectedUpdate?.feedURL.absoluteString
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard isRunning, expectedUpdate != nil, updateCheck == .updates else {
            throw installationError("An in-app installation must be started with Download & Install.")
        }
        if cancellationRequested {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "The update installation was cancelled."])
        }
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        // The check cancellation callback expires as soon as the appcast is loaded.
        cancellation = nil
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        do {
            try self.updater(updater, mayPerform: updateCheck)
            try validate(updateItem)
        } catch {
            receive(error)
            throw error
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard isRunning else { return }
        receive(error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: (any Error)?) {
        guard isRunning else { return }
        cancellation = nil
        relaunchHandler = nil
        if let error { receive(error) }
        isRunning = false

        if let failureMessage {
            publish(.failed(failureMessage))
        } else if installationCompleted {
            publish(.installed)
        } else if cancellationRequested {
            publish(.cancelled)
        } else {
            // A dismissed/deferred session is not proof of a successful replacement.
            recordFailure(installationError("The update ended before Sparkle confirmed installation. Download the release from GitHub instead."))
        }
    }

    // MARK: Sparkle user driver

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // AppServices owns discovery. Never opt into Sparkle scheduling or profiling.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false,
                                         automaticUpdateDownloading: NSNumber(value: false),
                                         sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        if cancellationRequested || failureMessage != nil {
            invokeCancellation()
        } else {
            advance(to: .checking)
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        // Dismissing an already-installing update leaves install-on-quit enabled.
        // Reject it with skip instead, so an unvalidated update cannot install later.
        var choice: SPUUserUpdateChoice = state.stage == .installing ? .skip : .dismiss
        defer { reply(choice) }
        guard !cancellationRequested, failureMessage == nil else { return }

        do {
            try validate(appcastItem) // Also covers resumed updates, which skip shouldProceed.
            guard state.userInitiated else {
                throw installationError("Sparkle offered an update without an explicit installation request.")
            }
        } catch {
            recordFailure(error)
            return
        }

        let nextState: UpdateInstallationState
        switch state.stage {
        case .notDownloaded: nextState = .downloading
        case .downloaded: nextState = .extracting
        case .installing: nextState = .installing
        @unknown default:
            recordFailure(installationError("Sparkle reported an unsupported update stage."))
            return
        }
        validatedUpdate = true
        advance(to: nextState)
        // The state callback can synchronously request cancellation before download.
        guard !cancellationRequested, failureMessage == nil else { return }
        choice = .install
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        recordFailure(installationError("Sparkle unexpectedly requested release notes during installation."))
        invokeCancellation()
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        recordFailure(error)
        invokeCancellation()
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        defer { acknowledgement() }
        let version = expectedUpdate?.version ?? "the selected release"
        recordFailure(installationError("No compatible in-app update for Sukoon \(version) was found.\n" + Self.description(of: error)))
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        defer { acknowledgement() }
        cancellation = nil
        receive(error)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        if cancellationRequested || failureMessage != nil {
            invokeCancellation()
        } else {
            advance(to: .downloading)
        }
    }

    // The parent API exposes phases, not byte counts or fractional progress.
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        advance(to: .downloading)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        advance(to: .downloading)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil // Sparkle no longer permits download cancellation here.
        advance(to: .extracting)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        advance(to: .extracting)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        var choice: SPUUserUpdateChoice = .skip
        defer { reply(choice) }
        guard !cancellationRequested, failureMessage == nil else { return }
        guard isRunning, validatedUpdate else {
            recordFailure(installationError("Sparkle attempted to install an update that was not validated against the selected release."))
            return
        }
        advance(to: .installing)
        choice = .install // The original Download & Install action also authorized relaunch.
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        cancellation = nil
        guard isRunning, failureMessage == nil, !cancellationRequested else { return }
        if applicationTerminated {
            relaunchHandler = nil
            advance(to: .installing)
        } else {
            // Sparkle already sent the first quit event. Let the user retry only
            // if an open modal or termination handler delays that request.
            relaunchHandler = retryTerminatingApplication
            advance(to: .waitingForRelaunch)
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        defer { acknowledgement() }
        cancellation = nil
        relaunchHandler = nil
        guard validatedUpdate else {
            recordFailure(installationError("Sparkle reported installation of an update that was not validated against the selected release."))
            return
        }
        installationCompleted = true
        // relaunched can be false when the target already exited. This callback,
        // unlike a completed check or dismissal, confirms actual installation.
        if failureMessage == nil { publish(.installed) }
    }

    func dismissUpdateInstallation() {
        cancellation = nil
        relaunchHandler = nil
        // Teardown is not success or cancellation. Keep a visible failure intact;
        // the delegate's finished-cycle callback supplies the terminal outcome.
    }
}
