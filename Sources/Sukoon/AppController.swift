import AppKit
import Observation
import SwiftUI
import SukoonCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    let store: AppStore
    let navigation = AppNavigation()
    let reminderClock = ReminderClock()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var workspace: NSWindow?
    private var reminderPanel: ReminderPanel?
    private var successPanel: NSPanel?
    private var successDismissalTimer: Timer?
    private var handledCelebration: Celebration?
    private var timer: Timer?
    private var reminderDismissalTimer: Timer?
    private var availabilityTimer: Timer?
    private var displayedReminderID: UUID?
    private var displayedReminderIsPreview = false
    private var displayedReminder: ReminderContent?
    private var reminderMeasurement: (key: ReminderMeasurementKey, height: CGFloat)?
    private var resizingReminder = false
    private var applyingReminderFrame = false
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
        _ = QuranFonts.shared
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
        // Existing installations keep their launch behavior; only new users see setup.
        navigation.showsOnboarding = store.needsOnboarding
        if store.needsOnboarding || !UserDefaults.standard.bool(forKey: "hasOpenedSukoon") {
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
        successDismissalTimer?.invalidate()
        popoverDismissalTimer?.invalidate()
        availabilityTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
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
        let controller = NSHostingController(rootView:
            ThemeRoot(store: store) {
                MenuBarView(store: store, reminderClock: reminderClock, onOpen: { [weak self] section in
                    guard let self else { return }
                    if section == .quran,
                       let reference = (self.store.lastReminder ?? self.store.previewReminder())?.reference {
                        self.navigation.readerSurahID = reference.surahID
                        self.navigation.readerReference = reference
                    }
                    self.openWorkspace(section)
                }, onPreview: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.presentReminder(preview: true)
                }, onQuit: { NSApp.terminate(nil) })
            }
        )
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
    }

    @objc private func togglePopover() {
        reminderClock.now = Date()
        updateReminderAvailability()
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = AppLocalization(language: store.settings.language).text("Sukoon")
            window.identifier = .init("sukoon.workspace")
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let controller = NSHostingController(rootView:
                ThemeRoot(store: store) {
                    WorkspaceView(store: store, navigation: navigation, reminderClock: reminderClock, onPreview: { [weak self] in
                        self?.presentReminder(preview: true)
                    })
                }
            )
            controller.sizingOptions = [.minSize]
            window.contentViewController = controller
            // Keep AppKit restoration and the hosting view's minimum in agreement.
            let minimumContentSize = WorkspaceView.minimumContentSize
            window.contentMinSize = minimumContentSize
            if !window.setFrameUsingName("SukoonWorkspace") {
                window.setContentSize(NSSize(width: 900, height: 680))
                window.center()
            }
            let restoredContent = window.contentLayoutRect.size
            if restoredContent.width < minimumContentSize.width
                || restoredContent.height < minimumContentSize.height {
                window.setContentSize(NSSize(
                    width: max(restoredContent.width, minimumContentSize.width),
                    height: max(restoredContent.height, minimumContentSize.height)
                ))
            }
            window.setFrameAutosaveName("SukoonWorkspace")
            workspace = window
        }
        updateAppearance()
        workspace?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A single panel is reused. Scheduled delivery never replaces a visible panel or consumes preview progress.
    @discardableResult
    func presentReminder(preview: Bool) -> Bool {
        let now = Date()
        guard preview || (sessionAvailable && store.canDeliverReminder(at: now)) else { return false }
        guard preview || reminderPanel?.isVisible != true else { return false }
        guard let content = preview ? store.previewReminder() : store.nextReminder() else { return false }
        if reminderPanel == nil {
            let panel = ReminderPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
                                      styleMask: [.borderless, .resizable, .nonactivatingPanel],
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
            panel.delegate = self
            panel.minSize = NSSize(width: 280, height: 148)
            reminderPanel = panel
        }
        guard let panel = reminderPanel else { return false }
        applyingReminderFrame = true
        defer { applyingReminderFrame = false }
        displayedReminderID = content.id
        displayedReminderIsPreview = preview
        displayedReminder = content
        let controller = NSHostingController(rootView:
            ThemeRoot(store: store) {
                ReminderView(store: store, content: content, isPreview: preview,
                             onDismiss: { [weak self] in self?.dismissReminder() },
                             onRead: { [weak self] in
                    guard let self else { return }
                    guard self.displayedReminderID == content.id, self.reminderPanel?.isVisible == true else { return }
                    if !preview, self.sessionAvailable, self.store.canDeliverReminder(at: Date()) {
                        self.store.acknowledge(content)
                        self.scheduleNextReminder()
                    }
                    self.dismissReminder()
                }, onOpen: { [weak self] in
                    guard let self else { return }
                    if let reference = content.reference {
                        self.navigation.readerSurahID = reference.surahID
                        self.navigation.readerReference = reference
                        self.openWorkspace(.quran)
                    } else {
                        self.openWorkspace(.today)
                    }
                    self.dismissReminder()
                })
            }
        )
        controller.sizingOptions = []
        panel.contentViewController = controller
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = reminderPanelSize(for: content, on: frame)
            panel.maxSize = NSSize(width: frame.width - 32, height: frame.height - 32)
            panel.setFrame(NSRect(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 24,
                                  width: size.width, height: size.height), display: false)
        }
        updateAppearance()
        panel.orderFrontRegardless()
        reminderDismissalTimer?.invalidate()
        reminderDismissalTimer = nil
        if panel.isVisible {
            let timer = Timer(timeInterval: TimeInterval(store.settings.reminderAutoCloseSeconds), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissReminder() }
            }
            RunLoop.main.add(timer, forMode: .common)
            reminderDismissalTimer = timer
        }
        if !preview && !store.canDeliverReminder(at: Date()) {
            dismissReminder()
            return false
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
        displayedReminderID = nil
        displayedReminderIsPreview = false
        displayedReminder = nil
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === reminderPanel else { return }
        resizingReminder = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === reminderPanel else { return }
        resizingReminder = false
        saveReminderSize(panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard !resizingReminder, !applyingReminderFrame,
              let panel = notification.object as? NSWindow, panel === reminderPanel else { return }
        saveReminderSize(panel)
    }

    private func saveReminderSize(_ panel: NSWindow) {
        let width = Double(panel.frame.width)
        let height = Double(panel.frame.height)
        guard store.settings.reminderPanelWidth != width || store.settings.reminderPanelHeight != height else { return }
        var settings = store.settings
        settings.reminderPanelWidth = width
        settings.reminderPanelHeight = height
        store.settings = settings
    }

    private struct ReminderMeasurementKey: Equatable {
        let id: UUID
        let width: CGFloat
        let fontName: String
        let pointSize: Double
    }

    private func reminderPanelSize(for content: ReminderContent, on screen: NSRect) -> NSSize {
        let maximumWidth = max(280, screen.width - 32)
        let maximumHeight = max(148, screen.height - 32)
        let width = min(max(CGFloat(store.settings.reminderPanelWidth ?? 380), 280), maximumWidth)
        if let height = store.settings.reminderPanelHeight {
            return NSSize(width: width, height: min(max(CGFloat(height), 148), maximumHeight))
        }
        let fontName = QuranFonts.shared.resolvedFontName(store.settings.quranFontName)
        let key = ReminderMeasurementKey(
            id: content.id, width: width, fontName: fontName, pointSize: store.settings.arabicFontSize
        )
        let textHeight: CGFloat
        if let measurement = reminderMeasurement, measurement.key == key {
            textHeight = measurement.height
        } else {
            let pointSize = CGFloat(store.settings.arabicFontSize)
            let font = NSFont(name: fontName, size: pointSize) ?? .systemFont(ofSize: pointSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.baseWritingDirection = .rightToLeft
            paragraph.lineSpacing = max(8, pointSize * 0.42)
            let text = NSAttributedString(string: content.arabic, attributes: [
                .font: font, .paragraphStyle: paragraph
            ])
            textHeight = ceil(text.boundingRect(
                with: NSSize(width: width - 40, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
            reminderMeasurement = (key, textHeight)
        }
        return NSSize(width: width, height: min(max(textHeight + 145, 148), min(640, maximumHeight)))
    }

    private func resizeVisibleReminder() {
        guard let panel = reminderPanel, panel.isVisible, !resizingReminder, !applyingReminderFrame,
              let content = displayedReminder, let screen = panel.screen?.visibleFrame else { return }
        let size = reminderPanelSize(for: content, on: screen)
        guard panel.frame.size != size else { return }
        let x = min(max(panel.frame.maxX - size.width, screen.minX + 16), screen.maxX - size.width - 16)
        let y = min(max(panel.frame.maxY - size.height, screen.minY + 16), screen.maxY - size.height - 16)
        applyingReminderFrame = true
        defer { applyingReminderFrame = false }
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    private func handleCelebration() {
        let celebration = store.celebration
        guard celebration != handledCelebration else { return }
        handledCelebration = celebration
        switch celebration {
        case let .some(.surah(id)):
            presentSurahSuccess(id)
        case .some(.khatm):
            successPanel?.orderOut(nil)
            openWorkspace(.journey)
        case .none:
            break
        }
    }

    private func presentSurahSuccess(_ id: Int) {
        guard let surah = store.library.surah(id) else { return }
        let nextSurah: Surah?
        if store.settings.mode == .surah, let selected = store.activeSurah, selected.id != id {
            nextSurah = selected
        } else if store.settings.mode == .automatic, let automatic = store.automaticSurah, automatic.id > id {
            nextSurah = automatic
        } else {
            nextSurah = store.library.surahs.first { $0.id > id && store.nextUnreadVerse(in: $0.id) != nil }
                ?? store.library.surahs.first { $0.id < id && store.nextUnreadVerse(in: $0.id) != nil }
        }
        if navigation.readerSurahID == id, let nextSurah {
            navigation.readerSurahID = nextSurah.id
            if store.settings.mode == .automatic,
               let reference = store.automaticNextReference, reference.surahID == nextSurah.id {
                navigation.readerReference = reference
            } else if let verse = store.nextUnreadVerse(in: nextSurah.id) {
                navigation.readerReference = VerseReference(surahID: nextSurah.id, verseID: verse.id)
            }
        }
        successDismissalTimer?.invalidate()
        if successPanel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            successPanel = panel
        }
        guard let panel = successPanel,
              let screen = reminderPanel?.screen ?? workspace?.screen ?? NSScreen.main else { return }
        let controller = NSHostingController(rootView: ThemeRoot(store: store) {
            SurahSuccessView(surah: surah, nextSurah: nextSurah)
        })
        controller.sizingOptions = []
        let available = screen.visibleFrame
        let width = min(340, available.width - 32)
        let size = controller.sizeThatFits(in: NSSize(width: width, height: 180))
        panel.contentViewController = controller
        var y = available.maxY - size.height - 24
        if let reminder = reminderPanel, reminder.isVisible {
            y = max(available.minY + 16, reminder.frame.minY - size.height - 10)
        }
        panel.setFrame(NSRect(x: available.maxX - width - 24, y: y,
                              width: width, height: size.height), display: false)
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.successPanel?.orderOut(nil)
                if self.store.celebration == .surah(id) { self.store.celebration = nil }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        successDismissalTimer = timer
    }

    func scheduleNextReminder() {
        timer?.invalidate()
        timer = nil
        scheduledConfiguration = scheduleConfiguration
        let now = Date()
        reminderClock.now = now
        updateReminderAvailability()
        scheduleAvailabilityChange(after: now)
        guard !stopping, sessionAvailable, let date = store.nextReminderDate(after: now) else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopping else { return }
                self.presentReminder(preview: false)
                self.scheduleNextReminder()
            }
        }
        timer.tolerance = min(2, date.timeIntervalSince(now) / 20)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateReminderAvailability() {
        if !displayedReminderIsPreview,
           !store.settings.remindersEnabled || store.reminderSuspensionEnd(at: reminderClock.now) != nil {
            dismissReminder()
        }
        updateStatus()
    }

    /// One-shot boundary events keep visible panels and status in sync without polling or resetting a due reminder.
    private func scheduleAvailabilityChange(after now: Date) {
        availabilityTimer?.invalidate()
        availabilityTimer = nil
        guard !stopping, sessionAvailable else { return }
        var nextChange = store.snoozedUntil.flatMap { $0 > now ? $0 : nil }
        if store.settings.quietHoursEnabled,
           store.settings.quietHoursStartMinute != store.settings.quietHoursEndMinute {
            let calendar = Calendar.current
            for minute in [store.settings.quietHoursStartMinute, store.settings.quietHoursEndMinute] {
                let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
                for policy in [Calendar.RepeatedTimePolicy.first, .last] {
                    if let date = calendar.nextDate(after: now, matching: components,
                                                    matchingPolicy: .nextTime, repeatedTimePolicy: policy),
                       nextChange == nil || date < nextChange! {
                        nextChange = date
                    }
                }
            }
            if let date = calendar.timeZone.nextDaylightSavingTimeTransition(after: now),
               nextChange == nil || date < nextChange! {
                nextChange = date
            }
        }
        guard let date = nextChange else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopping else { return }
                let now = Date()
                self.reminderClock.now = now
                self.updateReminderAvailability()
                self.scheduleAvailabilityChange(after: now)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        availabilityTimer = timer
    }

    private struct ScheduleConfiguration: Equatable {
        let interval: Int
        let mode: ReminderMode
        let enabled: Bool
        let nextReference: VerseReference?
        let quietHoursEnabled: Bool
        let quietHoursStartMinute: Int
        let quietHoursEndMinute: Int
        let snoozedUntil: Date?
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
                                     enabled: store.settings.remindersEnabled, nextReference: nextReference,
                                     quietHoursEnabled: store.settings.quietHoursEnabled,
                                     quietHoursStartMinute: store.settings.quietHoursStartMinute,
                                     quietHoursEndMinute: store.settings.quietHoursEndMinute,
                                     snoozedUntil: store.snoozedUntil)
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.settings
            _ = store.selectedSurahID
            _ = store.readVerseCount
            _ = store.automaticVerseOffset
            _ = store.celebration
            _ = store.snoozedUntil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.stopping else { return }
                self.updateAppearance()
                self.updateStatus()
                self.updateLanguage()
                if self.scheduledConfiguration != self.scheduleConfiguration { self.scheduleNextReminder() }
                self.resizeVisibleReminder()
                self.handleCelebration()
                self.observeStore()
            }
        }
    }

    private func updateStatus() {
        let now = reminderClock.now
        let l10n = AppLocalization(language: store.settings.language)
        statusItem?.button?.image = NSImage(systemSymbolName: store.canDeliverReminder(at: now) ? "moon.stars" : "moon.zzz",
                                            accessibilityDescription: l10n.text("Sukoon"))
        statusItem?.button?.image?.isTemplate = true
        let suspension = ReminderSuspensionStatus(store: store, now: now)
        statusItem?.button?.toolTip = suspension.map {
            "\(l10n.text("Sukoon — a moment of remembrance"))\n\($0.title(l10n: l10n))\n\($0.detail(l10n: l10n))"
        } ?? l10n.text("Sukoon — a moment of remembrance")
    }

    private func updateLanguage() {
        guard nativeLanguage != store.settings.language else { return }
        nativeLanguage = store.settings.language
        let l10n = AppLocalization(language: store.settings.language)
        workspace?.title = l10n.text("Sukoon")
        NSApp.mainMenu = makeMainMenu(language: store.settings.language)
    }

    @objc private func showSettings() { openWorkspace(.settings) }

    @objc private func showSection(_ sender: NSMenuItem) {
        guard AppSection.allCases.indices.contains(sender.tag) else { return }
        openWorkspace(AppSection.allCases[sender.tag])
    }

    @objc private func showPreview() { presentReminder(preview: true) }

    private func makeMainMenu(language: AppLanguage) -> NSMenu {
        let l10n = AppLocalization(language: language)
        let direction: NSUserInterfaceLayoutDirection = language == .arabic ? .rightToLeft : .leftToRight
        let menu = NSMenu()
        menu.userInterfaceLayoutDirection = direction
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: l10n.text("Sukoon"))
        appMenu.userInterfaceLayoutDirection = direction
        let settingsItem = appMenu.addItem(withTitle: l10n.text("Settings") + "…",
                                          action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
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
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: l10n.text("View"))
        viewMenu.userInterfaceLayoutDirection = direction
        for (index, section) in AppSection.allCases.enumerated() {
            let item = viewMenu.addItem(withTitle: l10n.text(section.title),
                                       action: #selector(showSection(_:)),
                                       keyEquivalent: section == .settings ? "" : String(index + 1))
            item.tag = index
            item.target = self
        }
        viewMenu.addItem(.separator())
        let popoverItem = viewMenu.addItem(withTitle: l10n.text("Show menu bar"),
                                          action: #selector(togglePopover), keyEquivalent: "")
        popoverItem.target = self
        let previewItem = viewMenu.addItem(withTitle: l10n.text("Preview reminder"),
                                          action: #selector(showPreview), keyEquivalent: "")
        previewItem.target = self
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
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
        let clockCenter = NotificationCenter.default
        clockCenter.addObserver(self, selector: #selector(wallClockDidChange), name: .NSSystemClockDidChange, object: nil)
        clockCenter.addObserver(self, selector: #selector(wallClockDidChange), name: .NSSystemTimeZoneDidChange, object: nil)
    }

    @objc private func willSleep() { sleeping = true; suspendDelivery() }
    @objc private func didWake() { sleeping = false; scheduleNextReminder() }
    @objc private func screenDidSleep() { screenSleeping = true; suspendDelivery() }
    @objc private func screenDidWake() { screenSleeping = false; scheduleNextReminder() }
    @objc private func sessionDidResign() { inactiveSession = true; suspendDelivery() }
    @objc private func sessionDidBecomeActive() { inactiveSession = false; scheduleNextReminder() }
    @objc private func screenLocked() { locked = true; suspendDelivery() }
    @objc private func screenUnlocked() { locked = false; scheduleNextReminder() }
    @objc private func wallClockDidChange() { scheduleNextReminder() }

    private func suspendDelivery() {
        timer?.invalidate()
        timer = nil
        availabilityTimer?.invalidate()
        availabilityTimer = nil
        dismissReminder()
        successPanel?.orderOut(nil)
        popover.performClose(nil)
    }
}

@MainActor
@Observable
final class ReminderClock {
    var now = Date()
}

@MainActor
private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct SurahSuccessView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let surah: Surah
    let nextSurah: Surah?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(palette.success)
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.format("%@ complete", l10n.surahName(surah), table: "Workspace"))
                    .font(.headline)
                if let nextSurah {
                    Text(l10n.format("Continuing with %@", l10n.surahName(nextSurah), table: "Workspace"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(palette.hairline, lineWidth: 1)
        }
    }
}
