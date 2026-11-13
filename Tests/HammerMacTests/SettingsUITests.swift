import AppKit
import Testing
import HammerCore
@testable import HammerMac

@MainActor final class FakeHotkeyApplier: HotkeyApplying {
    var error: HotkeyRegistrationError?
    private(set) var applied: [(Hotkey, HotkeyRole)] = []
    func apply(_ hotkey: Hotkey, role: HotkeyRole) throws {
        if let error { throw error }
        applied.append((hotkey, role))
    }
}

@MainActor final class SettingsHarness {
    let dir = makeTempDir()
    let store: SettingsStore
    let applier = FakeHotkeyApplier()
    var loginCalls: [Bool] = []
    var loginError: Error?
    var changes: [Settings] = []
    var cleared = 0
    var confirmAnswer = true
    var confirmMessages: [String] = []
    lazy var controller = SettingsWindowController(
        settings: Settings(), store: store, hotkeys: applier,
        setLoginItem: { [unowned self] on in if let e = self.loginError { throw e }; self.loginCalls.append(on) },
        onChange: { [unowned self] in self.changes.append($0) },
        historyCount: { 25 },
        onClearHistory: { [unowned self] in self.cleared += 1 },
        confirm: { [unowned self] msg in self.confirmMessages.append(msg); return self.confirmAnswer })

    init() { store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json")) }
    deinit { try? FileManager.default.removeItem(at: dir) }
}

func keyEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, type: NSEvent.EventType = .keyDown) -> NSEvent {
    if type == .flagsChanged {
        return NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
    }
    return NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: keyCode)!
}

@MainActor @Suite struct HotkeyRecorderFieldTests {
    @Test func recorderBuildsHotkeyFromEvent() {
        #expect(HotkeyRecorderField.hotkey(from: keyEvent(9, .option)) == Hotkey(keyCode: 9, modifiers: .option))
        #expect(HotkeyRecorderField.hotkey(from: keyEvent(49, [.command, .shift])) == Hotkey(keyCode: 49, modifiers: [.command, .shift]))
    }

    @Test func recorderIgnoresModifierOnly() {
        #expect(HotkeyRecorderField.hotkey(from: keyEvent(58, .option, type: .flagsChanged)) == nil)
    }

    @Test func recordingCallsOnRecord() {
        let field = HotkeyRecorderField()
        var recorded: [Hotkey] = []
        field.onRecord = { recorded.append($0) }
        field.startRecording()
        field.keyDown(with: keyEvent(9, [.control, .option]))
        #expect(recorded == [Hotkey(keyCode: 9, modifiers: [.control, .option])])
        #expect(!field.isRecording)
    }

    @Test func escapeCancelsRecording() {
        let field = HotkeyRecorderField()
        var recorded = 0
        field.onRecord = { _ in recorded += 1 }
        field.startRecording()
        field.keyDown(with: keyEvent(53, []))
        #expect(recorded == 0 && !field.isRecording)
    }

    @Test func displaysHotkey() {
        let field = HotkeyRecorderField()
        field.hotkey = .defaultClipboard
        #expect(field.displayText == "⌥X")
        field.startRecording()
        #expect(field.displayText == "Press shortcut…")
    }
}

@MainActor @Suite struct SettingsWindowTests {
    let ctrlOptV = Hotkey(keyCode: 9, modifiers: [.control, .option])

    @Test func validHotkeySavedAndApplied() {
        let h = SettingsHarness()
        h.controller.record(ctrlOptV, for: .clipboard)
        #expect(h.applier.applied.count == 1)
        #expect(h.store.load().clipboardHotkey == ctrlOptV)
        #expect(h.changes.last?.clipboardHotkey == ctrlOptV)
        #expect(h.controller.errorMessage == "")
    }

    @Test func invalidHotkeyShowsMessageKeepsOld() {
        let h = SettingsHarness()
        h.controller.record(Hotkey(keyCode: 7, modifiers: .shift), for: .clipboard)
        #expect(h.controller.errorMessage == "Use at least one of ⌘, ⌥ or ⌃.")
        #expect(h.applier.applied.isEmpty)
        #expect(h.store.load().clipboardHotkey == .defaultClipboard)
        #expect(h.controller.recorder(for: .clipboard).hotkey == .defaultClipboard)
    }

    @Test func sameAsOtherMessage() {
        let h = SettingsHarness()
        h.controller.record(.defaultClipboard, for: .launcher)
        #expect(h.controller.errorMessage == "Already used by the other Hammer shortcut.")
    }

    @Test func registrationFailureShowsMessageKeepsOld() {
        let h = SettingsHarness()
        h.applier.error = .alreadyTaken
        h.controller.record(ctrlOptV, for: .clipboard)
        #expect(h.controller.errorMessage == "Another app is using this shortcut.")
        #expect(h.store.load().clipboardHotkey == .defaultClipboard)
        h.applier.error = .failed(-1)
        h.controller.record(ctrlOptV, for: .clipboard)
        #expect(h.controller.errorMessage == "Couldn't register this shortcut.")
    }

    @Test func loginToggleCallsSetter() {
        let h = SettingsHarness()
        h.controller.setLaunchAtLogin(false)
        #expect(h.loginCalls == [false])
        #expect(!h.store.load().launchAtLogin)
    }

    @Test func loginToggleFailureKeepsSetting() {
        struct Boom: Error {}
        let h = SettingsHarness()
        h.loginError = Boom()
        h.controller.setLaunchAtLogin(false)
        #expect(h.controller.errorMessage == "Couldn't change the login item.")
        #expect(h.store.load().launchAtLogin)
    }

    @Test func menuBarToggleSaves() {
        let h = SettingsHarness()
        h.controller.setShowMenuBarIcon(false)
        #expect(!h.store.load().showMenuBarIcon)
        #expect(h.changes.last?.showMenuBarIcon == false)
    }

    @Test func clearHistoryAsksThenClears() {
        let h = SettingsHarness()
        h.confirmAnswer = false
        h.controller.clearHistory()
        #expect(h.cleared == 0)
        #expect(h.confirmMessages == ["Clear all 25 items? This can't be undone."])
        h.confirmAnswer = true
        h.controller.clearHistory()
        #expect(h.cleared == 1)
    }
}

@MainActor @Suite struct StatusItemControllerTests {
    @Test func statusMenuTitles() {
        let c = StatusItemController(onSettings: {}, onQuit: {})
        defer { c.remove() }
        #expect(c.menuItemTitles == ["Settings…", "Quit Hammer"])
    }

    @Test func menuItemsCallHandlers() {
        var settings = 0, quit = 0
        let c = StatusItemController(onSettings: { settings += 1 }, onQuit: { quit += 1 })
        defer { c.remove() }
        c.menu.performActionForItem(at: 0)
        c.menu.performActionForItem(at: c.menu.items.count - 1)
        #expect(settings == 1 && quit == 1)
    }

    @Test func statusItemHides() {
        let c = StatusItemController(onSettings: {}, onQuit: {})
        defer { c.remove() }
        c.isVisible = false
        #expect(!c.isVisible)
    }
}
