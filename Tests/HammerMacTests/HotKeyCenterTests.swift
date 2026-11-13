import AppKit
import Carbon
import Testing
import HammerCore
@testable import HammerMac

@MainActor @Suite(.serialized) struct HotKeyCenterTests {
    let hyperF19 = Hotkey(keyCode: 80, modifiers: [.command, .option, .control, .shift])
    let hyperF18 = Hotkey(keyCode: 79, modifiers: [.command, .option, .control, .shift])

    @Test func carbonModifierMapping() {
        #expect(HotKeyCenter.carbonModifiers(.command) == UInt32(cmdKey))
        #expect(HotKeyCenter.carbonModifiers(.option) == UInt32(optionKey))
        #expect(HotKeyCenter.carbonModifiers(.control) == UInt32(controlKey))
        #expect(HotKeyCenter.carbonModifiers(.shift) == UInt32(shiftKey))
        #expect(HotKeyCenter.carbonModifiers([.command, .shift]) == UInt32(cmdKey | shiftKey))
    }

    @Test func registerAndUnregisterUnusualCombo() throws {
        let center = HotKeyCenter()
        try center.register(hyperF19, role: .launcher)
        center.unregister(role: .launcher)
        try center.register(hyperF19, role: .launcher)
        center.unregister(role: .launcher)
    }

    @Test func reRegisteringSameComboForSameRoleIsNoOp() throws {
        let center = HotKeyCenter()
        defer { center.unregister(role: .launcher) }
        try center.register(hyperF19, role: .launcher)
        try center.register(hyperF19, role: .launcher)
    }

    @Test func duplicateInProcessIsAlreadyTaken() throws {
        let center = HotKeyCenter()
        defer { center.unregister(role: .launcher); center.unregister(role: .clipboard) }
        try center.register(hyperF18, role: .launcher)
        #expect(throws: HotkeyRegistrationError.alreadyTaken) { try center.register(hyperF18, role: .clipboard) }
    }

    @Test func failedReplacementKeepsOldRegistration() throws {
        let center = HotKeyCenter()
        defer { center.unregister(role: .launcher); center.unregister(role: .clipboard) }
        try center.register(hyperF18, role: .clipboard)
        try center.register(hyperF19, role: .launcher)
        #expect(throws: HotkeyRegistrationError.alreadyTaken) { try center.register(hyperF18, role: .launcher) }
        #expect(center.registeredHotkey(for: .launcher) == hyperF19)
    }
}

@Suite struct SpotlightShortcutTests {
    @Test func absentEntryMeansSpotlightOwnsCmdSpace() {
        #expect(SpotlightShortcut.conflicts(with: .defaultLauncher, symbolicHotkeys: nil))
        #expect(SpotlightShortcut.conflicts(with: .defaultLauncher, symbolicHotkeys: [:]))
    }
    @Test func disabledEntryNoConflict() {
        let dict: [String: Any] = ["64": ["enabled": false, "value": ["parameters": [32, 49, 1_048_576]]]]
        #expect(!SpotlightShortcut.conflicts(with: .defaultLauncher, symbolicHotkeys: dict))
    }
    @Test func enabledEntryConflictsWhenSameCombo() {
        let dict: [String: Any] = ["64": ["enabled": true, "value": ["parameters": [32, 49, 1_048_576]]]]
        #expect(SpotlightShortcut.conflicts(with: .defaultLauncher, symbolicHotkeys: dict))
        #expect(!SpotlightShortcut.conflicts(with: Hotkey(keyCode: 49, modifiers: .option), symbolicHotkeys: dict))
    }
    @Test func spotlightRebound() {
        let dict: [String: Any] = ["64": ["enabled": 1, "value": ["parameters": [32, 49, 1_572_864]]]]  // ⌘⌥Space
        #expect(!SpotlightShortcut.conflicts(with: .defaultLauncher, symbolicHotkeys: dict))
        #expect(SpotlightShortcut.conflicts(with: Hotkey(keyCode: 49, modifiers: [.command, .option]), symbolicHotkeys: dict))
    }
}

@MainActor @Suite struct IconProviderTests {
    func bigImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 512, height: 512).fill(); image.unlockFocus()
        return image
    }

    @Test func iconIsResized() {
        let icon = IconProvider(load: { _ in self.bigImage() }).icon(forPath: "/Applications/A.app")
        #expect(icon.size == NSSize(width: 24, height: 24))
        #expect(icon.representations.count == 1)
        #expect(icon.representations[0].pixelsWide == 48)
    }

    @Test func iconCachedLoaderCalledOnce() {
        var calls = 0
        let p = IconProvider(load: { _ in calls += 1; return self.bigImage() })
        _ = p.icon(forPath: "/a"); _ = p.icon(forPath: "/a")
        #expect(calls == 1)
    }

    @Test func iconCacheBounded() {
        var calls = 0
        let p = IconProvider(capacity: 2, load: { _ in calls += 1; return self.bigImage() })
        _ = p.icon(forPath: "/a"); _ = p.icon(forPath: "/b"); _ = p.icon(forPath: "/c"); _ = p.icon(forPath: "/a")
        #expect(calls == 4)
    }

    @Test func clearEmptiesCache() {
        var calls = 0
        let p = IconProvider(load: { _ in calls += 1; return self.bigImage() })
        _ = p.icon(forPath: "/a"); p.clear(); _ = p.icon(forPath: "/a")
        #expect(calls == 2)
    }
}
