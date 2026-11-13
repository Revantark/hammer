import AppKit
import HammerCore
import HammerMac
import os

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.hammer", category: "app")
    private var composition: AppComposition!
    private let hotKeyCenter = HotKeyCenter()
    private let icons = IconProvider()
    private var thumbnails: ClipThumbnails!
    private var panel: HammerPanel?
    private var panelController: PanelViewController?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var pollTimer: Timer?
    private var debugHooks: DebugHooks?
    /// Script-driven runs (memory/latency checks): no global hotkeys, no login item, no alerts, private pasteboard.
    private let testMode = ProcessInfo.processInfo.environment["HAMMER_DEBUG_SIGNALS"] == "1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dataDirectory: URL
        do {
            dataDirectory = try DataDirectory.resolve()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Hammer can't create its data folder."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let pasteboard = testMode ? SystemPasteboard(pasteboard: NSPasteboard(name: .init("dev.hammer.debug"))) : SystemPasteboard()
        composition = AppComposition(dataDirectory: dataDirectory, pasteboard: pasteboard,
                                     scanner: FileSystemAppScanner(), watcher: FSEventsWatcher(),
                                     appLauncher: WorkspaceAppLauncher(), pasteSender: CGEventPasteSender(),
                                     hotkeys: hotKeyCenter, clock: SystemClock())
        thumbnails = ClipThumbnails(clipboard: composition.clipboard)
        hotKeyCenter.onPress = { [weak self] role in self?.hotkeyPressed(role) }

        let failures = composition.start(registerHotkeys: !testMode)
        for (role, error) in failures {
            log.error("Hotkey for \(String(describing: role), privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }

        updateStatusItem()
        startPolling()
        if !testMode { applyLoginItemDefault() }
        debugHooks = DebugHooks(show: { [weak self] role in self?.hotkeyPressed(role) },
                                hide: { [weak self] in self?.composition.model.hide() },
                                search: { [weak self] in self?.composition.model.setQuery($0) })

        if !testMode, composition.needsSpotlightNotice { showSpotlightNotice() }
        if !failures.isEmpty { showHotkeyFailureNotice(failures) }
    }

    // MARK: Panel

    private func hotkeyPressed(_ role: HotkeyRole) {
        debugHooks?.markShowRequested()
        ensurePanel()
        composition.handleHotkey(role)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let controller = PanelViewController(model: composition.model, launcher: composition.launcher,
                                             clipboard: composition.clipboard, pasteSender: composition.pasteSender,
                                             icons: icons, thumbnails: thumbnails, clock: composition.clock,
                                             settings: { [unowned self] in self.composition.settings })
        let panel = HammerPanel(contentViewController: controller)
        controller.onVisibilityChanged = { [weak self] visible in visible ? self?.showPanel() : self?.hidePanel() }
        controller.onSizeChanged = { [weak self] size in self?.resizePanel(to: size) }
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        panel.onResignKey = { [weak self] in self?.composition.model.hide() }
        panel.onKeyEquivalent = { [weak controller] event in
            guard let command = PanelKeyCommand.from(event) else { return false }
            controller?.handleKey(command)
            return true
        }
        self.panel = panel
        panelController = controller
    }

    private func showPanel() {
        guard let panel, let controller = panelController else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = PanelPlacement.frame(size: controller.preferredPanelSize, in: screen?.visibleFrame ?? .zero)
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(controller.searchField)
        panel.invalidateShadow()
        if debugHooks?.isEnabled == true {
            panel.displayIfNeeded()
            debugHooks?.markShown()
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func resizePanel(to size: NSSize) {
        guard let panel, panel.isVisible else { return }
        let old = panel.frame
        panel.setFrame(NSRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height),
                       display: true)
        panel.invalidateShadow()
    }

    // MARK: Clipboard polling

    private func startPolling() {
        let timer = Timer(timeInterval: ClipboardController.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.composition.clipboard.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: Settings, menu bar, login item

    private func openSettings() {
        composition.model.hide()
        if settingsWindow == nil {
            let window = SettingsWindowController(
                settings: composition.settings, store: composition.settingsStore, hotkeys: hotKeyCenter,
                setLoginItem: { try LoginItem.setEnabled($0) },
                onChange: { [weak self] in self?.composition.updateSettings($0); self?.updateStatusItem() },
                historyCount: { [weak self] in self?.composition.clipboard.history.entries.count ?? 0 },
                onClearHistory: { [weak self] in self?.composition.clipboard.clearAll() })
            window.onClose = { [weak self] in self?.settingsWindow = nil }
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.window?.center()
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func updateStatusItem() {
        if composition.settings.showMenuBarIcon {
            if statusItem == nil {
                statusItem = StatusItemController(onSettings: { [weak self] in self?.openSettings() },
                                                  onQuit: { NSApp.terminate(nil) })
            }
        } else {
            statusItem?.remove()
            statusItem = nil
        }
    }

    /// Launch at login is on by default; only meaningful when running from the .app bundle.
    private func applyLoginItemDefault() {
        guard Bundle.main.bundleURL.pathExtension == "app", composition.settings.launchAtLogin, !LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(true)
        } catch {
            log.error("Enabling launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Notices

    private func showSpotlightNotice() {
        composition.markSpotlightNoticeShown()
        let alert = NSAlert()
        alert.messageText = "⌘Space is used by Spotlight"
        alert.informativeText = "To use it for Hammer, open System Settings → Keyboard → Keyboard Shortcuts → Spotlight and turn off “Show Spotlight search”, then reopen Hammer."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showHotkeyFailureNotice(_ failures: [HotkeyRole: HotkeyRegistrationError]) {
        let names = failures.keys.sorted { $0 == .launcher && $1 == .clipboard }
            .map { composition.settings.hotkey(for: $0).displayString }
        let alert = NSAlert()
        alert.messageText = "Hammer couldn't register \(names.joined(separator: " and "))"
        alert.informativeText = "Another app may be using it. You can pick a different shortcut in Hammer Settings."
        NSApp.activate()
        alert.runModal()
    }
}
