import Foundation
import Testing
@testable import HammerCore

@Suite struct HotkeyTests {
    @Test func defaultsDisplay() {
        #expect(Hotkey.defaultLauncher.displayString == "⌘Space")
        #expect(Hotkey.defaultClipboard.displayString == "⌥X")
    }
    @Test func modifierOrder() {
        #expect(Hotkey(keyCode: 80, modifiers: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘F19")
    }
    @Test func codableRoundTrip() throws {
        let k = Hotkey(keyCode: 9, modifiers: [.control, .option])
        #expect(try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(k)) == k)
    }
    @Test func unknownKeyHasNoName() { #expect(Hotkey.keyName(for: 999) == nil) }
}

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = Settings()
        #expect(s.launcherHotkey == .defaultLauncher && s.clipboardHotkey == .defaultClipboard)
        #expect(s.launchAtLogin && s.showMenuBarIcon && !s.didShowSpotlightNotice)
    }
    @Test func validateNeedsModifier() {
        #expect(Settings().validate(Hotkey(keyCode: 7, modifiers: .shift), for: .clipboard) == .needsModifier)
        #expect(Settings().validate(Hotkey(keyCode: 7, modifiers: []), for: .clipboard) == .needsModifier)
    }
    @Test func validateSameAsOther() {
        #expect(Settings().validate(.defaultClipboard, for: .launcher) == .sameAsOther)
    }
    @Test func validateUnknownKey() {
        #expect(Settings().validate(Hotkey(keyCode: 999, modifiers: .command), for: .launcher) == .unknownKey)
    }
    @Test func validateOK() {
        #expect(Settings().validate(Hotkey(keyCode: 9, modifiers: [.control, .option]), for: .clipboard) == nil)
        #expect(Settings().validate(.defaultLauncher, for: .launcher) == nil)
    }
    @Test func storeRoundTrip() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        var s = Settings(); s.clipboardHotkey = Hotkey(keyCode: 9, modifiers: [.control, .option]); s.launchAtLogin = false
        try store.save(s)
        #expect(store.load() == s)
    }
    @Test func storeMissingKeysUseDefaults() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"showMenuBarIcon":false}"#.utf8).write(to: url)
        let s = SettingsStore(fileURL: url).load()
        #expect(!s.showMenuBarIcon && s.launchAtLogin && s.launcherHotkey == .defaultLauncher)
    }
    @Test func storeCorruptGivesDefaults() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data("][".utf8).write(to: url)
        #expect(SettingsStore(fileURL: url).load() == Settings())
    }
    @Test func storeMissingFileGivesDefaults() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        #expect(SettingsStore(fileURL: dir.appendingPathComponent("none.json")).load() == Settings())
    }
}

@MainActor @Suite struct PanelModelTests {
    @Test func openLauncherFromHidden() {
        let m = PanelModel(); m.hotkey(.launcher)
        #expect(m.isVisible && m.mode == .launcher && m.query == "" && m.selectedIndex == 0)
    }
    @Test func sameHotkeyHides() {
        let m = PanelModel(); m.hotkey(.clipboard); m.hotkey(.clipboard)
        #expect(!m.isVisible)
    }
    @Test func otherHotkeySwitchesModeAndResets() {
        let m = PanelModel(); m.hotkey(.launcher); m.setQuery("abc"); m.moveSelection(by: 1, count: 3)
        m.hotkey(.clipboard)
        #expect(m.isVisible && m.mode == .clipboard && m.query == "" && m.selectedIndex == 0)
    }
    @Test func hideResetsOnNextOpen() {
        let m = PanelModel(); m.hotkey(.launcher); m.setQuery("x"); m.moveSelection(by: 2, count: 5); m.hide()
        m.hotkey(.launcher)
        #expect(m.query == "" && m.selectedIndex == 0)
    }
    @Test func moveSelectionClamps() {
        let m = PanelModel(); m.hotkey(.launcher)
        m.moveSelection(by: -1, count: 3); #expect(m.selectedIndex == 0)
        m.moveSelection(by: 5, count: 3); #expect(m.selectedIndex == 2)
        m.moveSelection(by: 1, count: 0); #expect(m.selectedIndex == 0)
    }
    @Test func setQueryResetsSelection() {
        let m = PanelModel(); m.hotkey(.launcher); m.moveSelection(by: 2, count: 3); m.setQuery("s")
        #expect(m.selectedIndex == 0 && m.query == "s")
    }
    @Test func selectionFollowsIDWhenItemsChange() {
        let m = PanelModel(); m.hotkey(.clipboard); m.moveSelection(by: 1, count: 2)
        m.itemsChanged(newIDs: ["new", "a", "b"], oldIDs: ["a", "b"])
        #expect(m.selectedIndex == 2)
    }
    @Test func selectionResetsWhenIDGone() {
        let m = PanelModel(); m.hotkey(.clipboard); m.moveSelection(by: 1, count: 2)
        m.itemsChanged(newIDs: ["x", "a"], oldIDs: ["a", "b"])
        #expect(m.selectedIndex == 0)
    }
    @Test func onChangeCalledPerMutation() {
        let m = PanelModel(); var n = 0; m.onChange = { n += 1 }
        m.hotkey(.launcher); m.setQuery("a"); m.moveSelection(by: 1, count: 3); m.hide()
        #expect(n == 4)
    }
    @Test func hideWhenHiddenIsNoOp() {
        let m = PanelModel(); var n = 0; m.onChange = { n += 1 }
        m.hide()
        #expect(n == 0)
    }
}

@Suite struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    @Test func centeredHorizontally() {
        #expect(PanelPlacement.frame(size: CGSize(width: 620, height: 400), in: screen).minX == 410)
    }
    @Test func topAtFraction() {
        #expect(abs(PanelPlacement.frame(size: CGSize(width: 620, height: 400), in: screen).maxY - 702) < 0.001)
    }
    @Test func clampedOnSmallScreen() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        let f = PanelPlacement.frame(size: CGSize(width: 620, height: 480), in: small)
        #expect(small.contains(f))
    }
    @Test func respectsScreenOrigin() {
        #expect(PanelPlacement.frame(size: CGSize(width: 620, height: 400), in: CGRect(x: 1440, y: 0, width: 1440, height: 900)).minX == 1850)
    }
}

@Suite struct LRUCacheTests {
    @Test func evictsLeastRecentlyUsed() {
        var c = LRUCache<String, Int>(capacity: 2)
        c.insert(1, for: "a"); c.insert(2, for: "b"); _ = c.value(for: "a"); c.insert(3, for: "c")
        #expect(c.value(for: "b") == nil && c.value(for: "a") == 1 && c.value(for: "c") == 3)
    }
    @Test func countNeverExceedsCapacity() {
        var c = LRUCache<Int, Int>(capacity: 3)
        for i in 0..<10 { c.insert(i, for: i) }
        #expect(c.count == 3)
    }
    @Test func reinsertUpdatesValue() {
        var c = LRUCache<String, Int>(capacity: 2)
        c.insert(1, for: "a"); c.insert(9, for: "a")
        #expect(c.value(for: "a") == 9 && c.count == 1)
    }
    @Test func removeAllEmpties() {
        var c = LRUCache<String, Int>(capacity: 2)
        c.insert(1, for: "a"); c.removeAll()
        #expect(c.count == 0)
    }
}
