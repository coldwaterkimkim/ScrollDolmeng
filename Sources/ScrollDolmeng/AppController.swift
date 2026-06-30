import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum PersistMode {
        case immediate
        case debounced
    }

    private let scrollController = TrackpadScrollController()
    private let settingsStore = SettingsStore()
    private let settingsSaveDebounceInterval = 0.2

    private var statusItem: NSStatusItem?
    private var preferencesWindowController: PreferencesWindowController?
    private var showMenuBarIcon = ScrollSettings.defaults.showMenuBarIcon
    private var pendingSettingsSave: DispatchWorkItem?

    private lazy var statusItemButton: NSStatusBarButton? = statusItem?.button
    private lazy var menu = NSMenu()
    private lazy var statusMenuItem = makeDisabledMenuItem("")
    private lazy var detailMenuItem = makeDisabledMenuItem("")
    private lazy var preferencesItem = NSMenuItem(
        title: "Open Preferences\u{2026}",
        action: #selector(openPreferences),
        keyEquivalent: ","
    )
    private lazy var enabledItem = NSMenuItem(
        title: "One-Finger Scroll Active",
        action: #selector(toggleEnabled),
        keyEquivalent: ""
    )
    private lazy var retryItem = NSMenuItem(
        title: "Reconnect Input Hook",
        action: #selector(retryHook),
        keyEquivalent: ""
    )
    private lazy var openAccessibilityItem = NSMenuItem(
        title: "Open Accessibility Settings",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )
    private lazy var openInputMonitoringItem = NSMenuItem(
        title: "Open Input Monitoring Settings",
        action: #selector(openInputMonitoringSettings),
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = settingsStore.load()
        apply(settings)
        buildMenuBarUI()
        applyMenuBarVisibility(show: settings.showMenuBarIcon)
        promptForAccessibilityIfNeeded()
        _ = scrollController.start()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushPendingSettingsSave()
        scrollController.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPreferences()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    private func buildMenuBarUI() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "UltraDolmengOneFingerScroll.StatusItem"
        statusItem?.isVisible = true
        statusItemButton?.title = "\u{2722}"
        statusItemButton?.toolTip = "울트라돌멩의원핑거스크롤"

        menu.delegate = self

        [preferencesItem, enabledItem, retryItem, openAccessibilityItem, openInputMonitoringItem].forEach {
            $0.target = self
        }

        menu.addItem(statusMenuItem)
        menu.addItem(detailMenuItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(enabledItem)
        menu.addItem(retryItem)
        menu.addItem(.separator())
        menu.addItem(openAccessibilityItem)
        menu.addItem(openInputMonitoringItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func applyMenuBarVisibility(show: Bool) {
        statusItem?.isVisible = show
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeDisabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func promptForAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func refreshUI() {
        refreshUI(refreshPreferences: true)
    }

    private func refreshUI(refreshPreferences: Bool) {
        refreshMenu()
        if refreshPreferences {
            refreshPreferencesWindow()
        }
    }

    private func refreshMenu() {
        let settings = currentSettings()
        let statusTitle = SettingsPresentation.statusTitle(
            hasTap: scrollController.hasTap,
            hasTrackpadDevices: scrollController.hasTrackpadDevices,
            isEnabled: settings.isEnabled
        )
        statusMenuItem.title = "Status: \(statusTitle)"
        detailMenuItem.title = menuDetailLine(for: settings)

        enabledItem.title = settings.isEnabled ? "One-Finger Scroll Active" : "One-Finger Scroll Paused"
        enabledItem.state = settings.isEnabled ? .on : .off
        enabledItem.isEnabled = scrollController.hasTap && scrollController.hasTrackpadDevices
        retryItem.isHidden = scrollController.hasTap && scrollController.hasTrackpadDevices
    }

    private func refreshPreferencesWindow() {
        guard let preferencesWindowController,
              preferencesWindowController.window?.isVisible == true else { return }

        preferencesWindowController.apply(
            settings: currentSettings(),
            hasTap: scrollController.hasTap,
            hasTrackpadDevices: scrollController.hasTrackpadDevices
        )
    }

    private func menuDetailLine(for settings: ScrollSettings) -> String {
        if !scrollController.hasTap {
            return "Grant permissions, then reconnect the input hook."
        }
        if !scrollController.hasTrackpadDevices {
            return "No Apple multitouch trackpad detected."
        }

        let axisSummary = SettingsPresentation.axisSummary(
            flipHorizontal: settings.flipHorizontal,
            flipVertical: settings.flipVertical
        )

        return [
            "Key: \(TrackpadScrollController.fixedModifierKey.title)",
            "Direction: \(axisSummary)",
            "Speed: \(SettingsPresentation.selectedSpeedPresetName(for: settings.scrollMultiplier))"
        ].joined(separator: "  \u{00B7}  ")
    }

    private func openSystemSettingsPane(_ location: String) {
        guard let url = URL(string: location) else { return }
        NSWorkspace.shared.open(url)
    }

    private func makePreferencesWindowController() -> PreferencesWindowController {
        let controller = PreferencesWindowController()

        controller.onEnabledChanged = { [weak self] enabled in
            self?.setEnabled(enabled, refreshPreferences: false)
        }
        controller.onSpeedPresetChanged = { [weak self] value in
            self?.setScrollMultiplier(value, refreshPreferences: false, persistMode: .immediate)
        }
        controller.onSpeedValueChanged = { [weak self] value in
            self?.setScrollMultiplier(value, refreshPreferences: false, persistMode: .debounced)
        }
        controller.onFlipHorizontalChanged = { [weak self] enabled in
            self?.setFlipHorizontal(enabled, refreshPreferences: false)
        }
        controller.onFlipVerticalChanged = { [weak self] enabled in
            self?.setFlipVertical(enabled, refreshPreferences: false)
        }
        controller.onShowMenuBarIconChanged = { [weak self] show in
            self?.setShowMenuBarIcon(show, refreshPreferences: false)
        }
        controller.onOpenAccessibility = { [weak self] in
            self?.openAccessibilitySettings()
        }
        controller.onOpenInputMonitoring = { [weak self] in
            self?.openInputMonitoringSettings()
        }
        controller.onReconnectInputHook = { [weak self] in
            self?.retryHook()
        }
        controller.onDidClose = { [weak self] in
            self?.preferencesWindowController = nil
        }

        return controller
    }

    private func currentSettings() -> ScrollSettings {
        ScrollSettings(
            isEnabled: scrollController.isEnabled,
            scrollMultiplier: scrollController.scrollMultiplier,
            flipHorizontal: scrollController.flipHorizontal,
            flipVertical: scrollController.flipVertical,
            showMenuBarIcon: showMenuBarIcon
        )
    }

    private func apply(_ settings: ScrollSettings) {
        scrollController.isEnabled = settings.isEnabled
        scrollController.scrollMultiplier = settings.scrollMultiplier
        scrollController.flipHorizontal = settings.flipHorizontal
        scrollController.flipVertical = settings.flipVertical
        showMenuBarIcon = settings.showMenuBarIcon
    }

    private func persistSettings() {
        pendingSettingsSave?.cancel()
        pendingSettingsSave = nil
        settingsStore.save(currentSettings())
    }

    private func schedulePersistSettings() {
        pendingSettingsSave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settingsStore.save(self.currentSettings())
            self.pendingSettingsSave = nil
        }

        pendingSettingsSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsSaveDebounceInterval, execute: workItem)
    }

    private func flushPendingSettingsSave() {
        guard let pendingSettingsSave else { return }
        self.pendingSettingsSave = nil
        pendingSettingsSave.cancel()
        settingsStore.save(currentSettings())
    }

    private func persistSettingsAndRefresh(
        persistMode: PersistMode = .immediate,
        refreshPreferences: Bool = true
    ) {
        switch persistMode {
        case .immediate:
            persistSettings()
        case .debounced:
            schedulePersistSettings()
        }

        refreshUI(refreshPreferences: refreshPreferences)
    }

    private func setEnabled(_ enabled: Bool, refreshPreferences: Bool = true) {
        scrollController.isEnabled = enabled
        persistSettingsAndRefresh(refreshPreferences: refreshPreferences)
    }

    private func setScrollMultiplier(_ value: Double, refreshPreferences: Bool = true, persistMode: PersistMode = .debounced) {
        scrollController.scrollMultiplier = value
        persistSettingsAndRefresh(persistMode: persistMode, refreshPreferences: refreshPreferences)
    }

    private func setFlipHorizontal(_ enabled: Bool, refreshPreferences: Bool = true) {
        scrollController.flipHorizontal = enabled
        persistSettingsAndRefresh(refreshPreferences: refreshPreferences)
    }

    private func setFlipVertical(_ enabled: Bool, refreshPreferences: Bool = true) {
        scrollController.flipVertical = enabled
        persistSettingsAndRefresh(refreshPreferences: refreshPreferences)
    }

    private func setShowMenuBarIcon(_ show: Bool, refreshPreferences: Bool = true) {
        showMenuBarIcon = show
        applyMenuBarVisibility(show: show)
        persistSettingsAndRefresh(refreshPreferences: refreshPreferences)
    }

    @objc
    private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = makePreferencesWindowController()
        }
        refreshPreferencesWindow()
        preferencesWindowController?.present()
    }

    @objc
    private func toggleEnabled() {
        setEnabled(!scrollController.isEnabled)
    }

    @objc
    private func retryHook() {
        _ = scrollController.restart()
        refreshUI()
    }

    @objc
    private func openAccessibilitySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc
    private func openInputMonitoringSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
