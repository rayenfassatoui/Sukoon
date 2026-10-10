import AppKit
import Observation
import SwiftUI
import SukoonCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    let store: AppStore
    let navigation = AppNavigation()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var workspace: NSWindow?
    private var reminderPanel: ReminderPanel?
    private var timer: Timer?
    private var reminderDismissalTimer: Timer?
    private var popoverDismissalTimer: Timer?
    private var scheduledConfiguration: ScheduleConfiguration?
    private var nativeLanguage: AppLanguage?
    private var sleeping = false
    private var screenSleeping = false
    private var locked = false
    private var inactiveSession = false
    private var stopping = false

    init(store: AppStore) {
        self.store = store
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateAppearance()
        installStatusItem()
        updateStatus()
        updateLanguage()
        observeSession()
        observeStore()
        scheduleNextReminder()
        // Opening the workspace makes a first launch discoverable; closing it keeps Sukoon in the menu bar.
        if !UserDefaults.standard.bool(forKey: "hasOpenedSukoon") {
            openWorkspace()
            UserDefaults.standard.set(true, forKey: "hasOpenedSukoon")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWorkspace()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopping = true
        timer?.invalidate()
        reminderDismissalTimer?.invalidate()
        popoverDismissalTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private var sessionAvailable: Bool { !sleeping && !screenSleeping && !locked && !inactiveSession }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let l10n = AppLocalization(language: store.settings.language)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: l10n.text("Sukoon"))
            image?.isTemplate = true
            button.image = image
            button.toolTip = l10n.text("Sukoon — a moment of remembrance")
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityIdentifier("sukoon.menu")
        }
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 240)
        popover.contentViewController = NSHostingController(rootView:
            ThemeRoot(store: store) {
                MenuBarView(store: store, onOpen: { [weak self] section in
                    guard let self else { return }
                    if section == .quran,
                       let reference = (self.store.lastReminder ?? self.store.previewReminder())?.reference {
                        self.navigation.readerSurahID = reference.surahID
                    }
                    self.openWorkspace(section)
                }, onPreview: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.presentReminder(preview: true)
                }, onQuit: { NSApp.terminate(nil) })
            }
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popoverDismissalTimer?.invalidate()
            let timer = Timer(timeInterval: TimeInterval(store.settings.menuBarAutoCloseSeconds), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.popover.performClose(nil) }
            }
            RunLoop.main.add(timer, forMode: .common)
            popoverDismissalTimer = timer
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popoverDismissalTimer?.invalidate()
        popoverDismissalTimer = nil
    }

    func openWorkspace(_ section: AppSection? = nil) {
        if let section { navigation.section = section }
        popover.performClose(nil)
        if workspace == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = AppLocalization(language: store.settings.language).text("Sukoon")
            window.identifier = .init("sukoon.workspace")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 1040, height: 720)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("SukoonWorkspace")
            window.contentViewController = NSHostingController(rootView:
                ThemeRoot(store: store) {
                    WorkspaceView(store: store, navigation: navigation, onPreview: { [weak self] in
                        self?.presentReminder(preview: true)
                    })
                }
            )
            window.center()
            workspace = window
        }
        updateAppearance()
        workspace?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Replaces a single panel rather than stacking reminders. Preview never consumes progress.
    @discardableResult
    func presentReminder(preview: Bool) -> Bool {
        guard preview || (sessionAvailable && store.canScheduleReminder) else { return false }
        guard let content = preview ? store.previewReminder() : store.nextReminder() else { return false }
        if reminderPanel == nil {
            let panel = ReminderPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            reminderPanel = panel
        }
        guard let panel = reminderPanel else { return false }
        panel.contentViewController = NSHostingController(rootView:
            ThemeRoot(store: store) {
                ReminderView(store: store, content: content, isPreview: preview,
                             onDismiss: { [weak self] in self?.dismissReminder() },
                             onRead: { [weak self] in
                    guard let self else { return }
                    if !preview {
                        self.store.acknowledge(content)
                        self.scheduleNextReminder()
                    }
                    self.dismissReminder()
                }, onOpen: { [weak self] in
                    guard let self else { return }
                    if let reference = content.reference {
                        self.navigation.readerSurahID = reference.surahID
                        self.openWorkspace(.quran)
                    } else {
                        self.openWorkspace(.today)
                    }
                    self.dismissReminder()
                })
            }
        )
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.maxX - 424, y: frame.maxY - 304, width: 400, height: 280), display: false)
        }
        updateAppearance()
        panel.orderFrontRegardless()
        reminderDismissalTimer?.invalidate()
        reminderDismissalTimer = nil
        if panel.isVisible {
            let timer = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissReminder() }
            }
            RunLoop.main.add(timer, forMode: .common)
            reminderDismissalTimer = timer
        }
        if !preview && panel.isVisible && store.settings.autoAdvance {
            store.acknowledge(content)
        }
        return panel.isVisible
    }

    func dismissReminder() {
        reminderDismissalTimer?.invalidate()
        reminderDismissalTimer = nil
        reminderPanel?.orderOut(nil)
    }

    func scheduleNextReminder() {
        timer?.invalidate()
        timer = nil
        scheduledConfiguration = scheduleConfiguration
        guard !stopping, sessionAvailable, store.canScheduleReminder else { return }
        let interval = TimeInterval(max(30, store.settings.intervalSeconds))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.presentReminder(preview: false)
                self.scheduleNextReminder()
            }
        }
        timer.tolerance = min(2, interval / 20)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private struct ScheduleConfiguration: Equatable {
        let interval: Int
        let mode: ReminderMode
        let enabled: Bool
        let nextReference: VerseReference?
    }

    private var scheduleConfiguration: ScheduleConfiguration {
        let nextReference: VerseReference?
        if store.settings.mode == .automatic {
            nextReference = store.automaticNextReference
        } else if store.settings.mode == .surah, let surahID = store.selectedSurahID,
                  let verse = store.nextUnreadVerse(in: surahID) {
            nextReference = VerseReference(surahID: surahID, verseID: verse.id)
        } else {
            nextReference = nil
        }
        return ScheduleConfiguration(interval: store.settings.intervalSeconds, mode: store.settings.mode,
                                     enabled: store.settings.remindersEnabled, nextReference: nextReference)
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.settings
            _ = store.selectedSurahID
            _ = store.readVerseCount
            _ = store.automaticVerseOffset
            _ = store.celebration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.stopping else { return }
                self.updateAppearance()
                self.updateStatus()
                self.updateLanguage()
                if self.scheduledConfiguration != self.scheduleConfiguration { self.scheduleNextReminder() }
                if self.store.celebration != nil { self.openWorkspace(.journey) }
                self.observeStore()
            }
        }
    }

    private func updateStatus() {
        statusItem?.button?.image = NSImage(systemSymbolName: store.canScheduleReminder ? "moon.stars" : "moon.zzz",
                                            accessibilityDescription: AppLocalization(language: store.settings.language).text("Sukoon"))
        statusItem?.button?.image?.isTemplate = true
    }

    private func updateLanguage() {
        guard nativeLanguage != store.settings.language else { return }
        nativeLanguage = store.settings.language
        let l10n = AppLocalization(language: store.settings.language)
        statusItem?.button?.toolTip = l10n.text("Sukoon — a moment of remembrance")
        workspace?.title = l10n.text("Sukoon")
        NSApp.mainMenu = Self.makeMainMenu(language: store.settings.language)
    }

    private static func makeMainMenu(language: AppLanguage) -> NSMenu {
        let l10n = AppLocalization(language: language)
        let direction: NSUserInterfaceLayoutDirection = language == .arabic ? .rightToLeft : .leftToRight
        let menu = NSMenu()
        menu.userInterfaceLayoutDirection = direction
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: l10n.text("Sukoon"))
        appMenu.userInterfaceLayoutDirection = direction
        appMenu.addItem(withTitle: l10n.text("Hide Sukoon"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: l10n.text("Quit Sukoon"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: l10n.text("Edit"))
        editMenu.userInterfaceLayoutDirection = direction
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: l10n.text(title), action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: l10n.text("Window"))
        windowMenu.userInterfaceLayoutDirection = direction
        windowMenu.addItem(withTitle: l10n.text("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: l10n.text("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return menu
    }

    private func updateAppearance() {
        let appearance: NSAppearance?
        switch store.settings.theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        // AppKit owns appearance. SwiftUI reads the resulting scheme; it must not
        // write a competing preferredColorScheme back onto each hosting window.
        if NSApp.appearance?.name != appearance?.name {
            NSApp.appearance = appearance
        }
    }

    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func willSleep() { sleeping = true; suspendDelivery() }
    @objc private func didWake() { sleeping = false; scheduleNextReminder() }
    @objc private func screenDidSleep() { screenSleeping = true; suspendDelivery() }
    @objc private func screenDidWake() { screenSleeping = false; scheduleNextReminder() }
    @objc private func sessionDidResign() { inactiveSession = true; suspendDelivery() }
    @objc private func sessionDidBecomeActive() { inactiveSession = false; scheduleNextReminder() }
    @objc private func screenLocked() { locked = true; suspendDelivery() }
    @objc private func screenUnlocked() { locked = false; scheduleNextReminder() }

    private func suspendDelivery() {
        timer?.invalidate()
        timer = nil
        dismissReminder()
        popover.performClose(nil)
    }
}

@MainActor
private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
