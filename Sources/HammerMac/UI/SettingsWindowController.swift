import AppKit
import HammerCore

@MainActor public protocol HotkeyApplying: AnyObject {
    func apply(_ hotkey: Hotkey, role: HotkeyRole) throws
}

extension HotKeyCenter: HotkeyApplying {
    public func apply(_ hotkey: Hotkey, role: HotkeyRole) throws {
        try register(hotkey, role: role)
    }
}

/// Plain AppKit settings window, created on demand.
@MainActor public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var settings: Settings
    private let store: SettingsStore
    private let hotkeys: HotkeyApplying
    private let setLoginItem: (Bool) throws -> Void
    private let onChange: (Settings) -> Void
    private let historyCount: () -> Int
    private let onClearHistory: () -> Void
    private let confirm: @MainActor (String) -> Bool
    public var onClose: (() -> Void)?

    private let launcherRecorder = HotkeyRecorderField()
    private let clipboardRecorder = HotkeyRecorderField()
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let menuBarCheckbox = NSButton(checkboxWithTitle: "Show menu bar icon", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")

    public var errorMessage: String { errorLabel.stringValue }

    public init(settings: Settings, store: SettingsStore, hotkeys: HotkeyApplying,
                setLoginItem: @escaping (Bool) throws -> Void, onChange: @escaping (Settings) -> Void,
                historyCount: @escaping () -> Int, onClearHistory: @escaping () -> Void,
                confirm: @escaping @MainActor (String) -> Bool = { SettingsWindowController.runConfirmAlert($0) }) {
        self.settings = settings
        self.store = store
        self.hotkeys = hotkeys
        self.setLoginItem = setLoginItem
        self.onChange = onChange
        self.historyCount = historyCount
        self.onClearHistory = onClearHistory
        self.confirm = confirm
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 250), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.title = "Hammer Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func recorder(for role: HotkeyRole) -> HotkeyRecorderField { role == .launcher ? launcherRecorder : clipboardRecorder }

    private func buildContent() {
        launcherRecorder.hotkey = settings.launcherHotkey
        clipboardRecorder.hotkey = settings.clipboardHotkey
        launcherRecorder.onRecord = { [weak self] in self?.record($0, for: .launcher) }
        clipboardRecorder.onRecord = { [weak self] in self?.record($0, for: .clipboard) }
        loginCheckbox.state = settings.launchAtLogin ? .on : .off
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginToggled)
        menuBarCheckbox.state = settings.showMenuBarIcon ? .on : .off
        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(menuBarToggled)
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        let clearButton = NSButton(title: "Clear Clipboard History…", target: self, action: #selector(clearClicked))

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Launcher shortcut:"), launcherRecorder],
            [NSTextField(labelWithString: "Clipboard shortcut:"), clipboardRecorder],
            [NSGridCell.emptyContentView, loginCheckbox],
            [NSGridCell.emptyContentView, menuBarCheckbox],
            [NSGridCell.emptyContentView, clearButton],
            [NSGridCell.emptyContentView, errorLabel],
        ])
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        launcherRecorder.widthAnchor.constraint(equalToConstant: 160).isActive = true
        clipboardRecorder.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window?.contentView = content
    }

    // MARK: Actions (also the test surface)

    func record(_ hotkey: Hotkey, for role: HotkeyRole) {
        if let error = settings.validate(hotkey, for: role) {
            show(Self.message(for: error))
            recorder(for: role).hotkey = settings.hotkey(for: role)
            return
        }
        do {
            try hotkeys.apply(hotkey, role: role)
        } catch let error as HotkeyRegistrationError {
            show(error == .alreadyTaken ? "Another app is using this shortcut." : "Couldn't register this shortcut.")
            recorder(for: role).hotkey = settings.hotkey(for: role)
            return
        } catch {
            show("Couldn't register this shortcut.")
            return
        }
        settings.setHotkey(hotkey, for: role)
        recorder(for: role).hotkey = hotkey
        commit()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try setLoginItem(on)
        } catch {
            show("Couldn't change the login item.")
            loginCheckbox.state = settings.launchAtLogin ? .on : .off
            return
        }
        settings.launchAtLogin = on
        commit()
    }

    func setShowMenuBarIcon(_ on: Bool) {
        settings.showMenuBarIcon = on
        commit()
    }

    func clearHistory() {
        let n = historyCount()
        guard confirm("Clear all \(n) \(n == 1 ? "item" : "items")? This can't be undone.") else { return }
        onClearHistory()
    }

    @objc private func loginToggled() { setLaunchAtLogin(loginCheckbox.state == .on) }
    @objc private func menuBarToggled() { setShowMenuBarIcon(menuBarCheckbox.state == .on) }
    @objc private func clearClicked() { clearHistory() }

    private func commit() {
        show("")
        try? store.save(settings)
        onChange(settings)
    }

    private func show(_ message: String) { errorLabel.stringValue = message }

    static func message(for error: HotkeyValidationError) -> String {
        switch error {
        case .needsModifier: return "Use at least one of ⌘, ⌥ or ⌃."
        case .sameAsOther: return "Already used by the other Hammer shortcut."
        case .unknownKey: return "That key can't be used."
        }
    }

    public static func runConfirmAlert(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    public func windowWillClose(_ notification: Notification) { onClose?() }
}
