import AppKit
import HammerCore
@testable import HammerMac

final class ManualClock: HammerClock, @unchecked Sendable {
    var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_794_571_200)) { current = start }
    func now() -> Date { current }
}

final class FakeScanner: AppScanning, @unchecked Sendable {
    var apps: [AppEntry]
    let roots: [URL] = []
    init(_ apps: [AppEntry]) { self.apps = apps }
    func scan() -> [AppEntry] { apps }
}

@MainActor final class FakeAppLauncher: AppLaunching {
    private(set) var opened: [String] = []
    func openApp(at path: String) { opened.append(path) }
}

@MainActor final class FakePasteboard: PasteboardAccess {
    var changeCount = 100
    var current = PasteboardSnapshot(representations: [], sourceApp: nil)
    private(set) var written: [[Representation]] = []
    func copy(_ s: PasteboardSnapshot) { current = s; changeCount += 1 }
    func copyText(_ text: String, source: String = "Notes") {
        copy(PasteboardSnapshot(representations: [Representation(type: PasteboardType.plainText, data: Data(text.utf8))], sourceApp: source))
    }
    func snapshot() -> PasteboardSnapshot { current }
    func write(_ reps: [Representation]) -> Int { written.append(reps); changeCount += 1; return changeCount }
}

@MainActor final class FakePasteSender: PasteSending {
    var isTrusted = true
    private(set) var pasteCount = 0
    func sendPaste() { pasteCount += 1 }
    func requestTrust() {}
}

@MainActor final class StubThumbnails: ThumbnailSource {
    func listThumbnail(for id: UUID) -> CGImage? { nil }
    func preview(for id: UUID) async -> CGImage? { nil }
    func clear() {}
}

func app(_ name: String) -> AppEntry {
    AppEntry(name: name, path: "/Applications/\(name).app", bundleID: "com.test.\(name.lowercased())")
}

/// A plain square icon. Built with a drawing handler, so it is safe to make off the main thread.
func solidIcon(size: CGFloat = 64) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSColor.blue.setFill(); rect.fill(); return true
    }
}

/// Everything a PanelViewController needs, wired with fakes.
@MainActor final class PanelHarness {
    let dir = makeTempDir()
    let model = PanelModel()
    let appLauncher = FakeAppLauncher()
    let pasteboard = FakePasteboard()
    let sender = FakePasteSender()
    let clock = ManualClock()
    var settings = Settings()
    let iconLoads = LoadLog()
    let launcher: LauncherController
    let clipboard: ClipboardController
    lazy var controller: PanelViewController = {
        let vc = PanelViewController(model: model, launcher: launcher, clipboard: clipboard, pasteSender: sender,
                                     icons: IconProvider(load: { [iconLoads] _ in iconLoads.record(); return solidIcon() }),
                                     thumbnails: thumbnails,
                                     clock: clock, settings: { [unowned self] in self.settings })
        _ = vc.view
        return vc
    }()
    var thumbnails: ThumbnailSource = StubThumbnails()

    init(apps: [AppEntry] = [app("Safari"), app("Notes"), app("Slack")]) {
        let search = LauncherSearch(sources: [AppsSource(catalog: AppCatalog(scanner: FakeScanner(apps)))])
        launcher = LauncherController(search: search, store: FrecencyStore(fileURL: dir.appendingPathComponent("f.json")),
                                      launcher: appLauncher, clock: clock)
        clipboard = ClipboardController(pasteboard: pasteboard, store: ClipStore(directory: dir), clock: clock)
    }

    /// Call after setting `thumbnails`/`settings` overrides; creates the controller so it observes the model.
    @discardableResult func start() -> PanelHarness { _ = controller; return self }

    func type(_ text: String) {
        controller.searchField.stringValue = text
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
    }

    deinit { try? FileManager.default.removeItem(at: dir) }
}

@MainActor final class FakeWatcher: DirectoryWatching {
    private(set) var started = false
    func start(paths: [URL], onChange: @escaping @MainActor () -> Void) { started = true }
    func stop() { started = false }
}
