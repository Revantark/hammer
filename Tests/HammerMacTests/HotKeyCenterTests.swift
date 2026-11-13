import os
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

/// Records how often (and on which thread) an icon loader ran. Safe to use from any thread.
final class LoadLog: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (calls: 0, onMain: 0))
    var calls: Int { state.withLock { $0.calls } }
    var onMain: Int { state.withLock { $0.onMain } }
    func record() { state.withLock { $0.calls += 1; if Thread.isMainThread { $0.onMain += 1 } } }
}

@MainActor @Suite struct IconProviderTests {
    func provider(capacity: Int = 160, log: LoadLog = LoadLog()) -> IconProvider {
        IconProvider(capacity: capacity, load: { _ in log.record(); return solidIcon(size: 512) })
    }

    @Test func iconIsResized() async throws {
        let icon = try #require(await provider().icon(forPath: "/Applications/A.app"))
        #expect(icon.size == NSSize(width: 28, height: 28))
        #expect(icon.representations.count == 1)
        #expect(icon.representations[0].pixelsWide == 56)
    }

    /// macOS 26 app icons keep ~10% empty margin; rendering trims it so the artwork fills the row's icon box.
    @Test func renderTrimsTheBuiltInMargin() throws {
        let padded = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.red.setFill(); rect.insetBy(dx: 10, dy: 10).fill(); return true  // art spans 10%...90%
        }
        let image = try #require(IconProvider.render(padded, pointSize: 28))
        let rep = NSBitmapImageRep(cgImage: image)
        #expect(rep.pixelsWide == 56)
        #expect((rep.colorAt(x: 2, y: 2)?.alphaComponent ?? 0) > 0.9)
        #expect((rep.colorAt(x: 28, y: 28)?.alphaComponent ?? 0) > 0.9)
    }

    @Test func loadsOffTheMainThread() async {
        let log = LoadLog()
        _ = await provider(log: log).icon(forPath: "/a")
        #expect(log.calls == 1)
        #expect(log.onMain == 0)
    }

    @Test func notCachedUntilLoaded() async {
        let p = provider()
        #expect(p.cachedIcon(forPath: "/a") == nil)
        let icon = await p.icon(forPath: "/a")
        #expect(p.cachedIcon(forPath: "/a") === icon)
    }

    @Test func iconCachedLoaderCalledOnce() async {
        let log = LoadLog()
        let p = provider(log: log)
        _ = await p.icon(forPath: "/a"); _ = await p.icon(forPath: "/a")
        #expect(log.calls == 1)
    }

    @Test func concurrentRequestsShareOneLoad() async {
        let log = LoadLog()
        let p = provider(log: log)
        async let first = p.icon(forPath: "/a")
        async let second = p.icon(forPath: "/a")
        let (a, b) = await (first, second)
        #expect(log.calls == 1)
        #expect(a != nil && a === b)
    }

    @Test func iconCacheBounded() async {
        let log = LoadLog()
        let p = provider(capacity: 2, log: log)
        for path in ["/a", "/b", "/c", "/a"] { _ = await p.icon(forPath: path) }
        #expect(log.calls == 4)
    }

    @Test func clearEmptiesCache() async {
        let log = LoadLog()
        let p = provider(log: log)
        _ = await p.icon(forPath: "/a"); p.clear(); _ = await p.icon(forPath: "/a")
        #expect(log.calls == 2)
    }

    @Test func defaultCapacityHoldsATypicalAppsFolder() async {
        let log = LoadLog()
        let p = IconProvider(load: { _ in log.record(); return solidIcon() })
        let paths = (0..<150).map { "/Applications/App\($0).app" }
        for path in paths { _ = await p.icon(forPath: path) }
        for path in paths { _ = await p.icon(forPath: path) }
        #expect(log.calls == 150)
    }
}
