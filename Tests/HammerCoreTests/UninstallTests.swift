import Foundation
import Testing
@testable import HammerCore

/// Creates `relative` (a folder, or a file when it has an extension other than a bundle's) under `root`.
@discardableResult func touch(_ relative: String, in root: URL, bytes: Int = 10) -> URL {
    let url = root.appendingPathComponent(relative)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if ["plist", "binarycookies", "json", "txt"].contains(url.pathExtension) {
        try! Data(repeating: 1, count: bytes).write(to: url)
    } else {
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try! Data(repeating: 1, count: bytes).write(to: url.appendingPathComponent("data.txt"))
    }
    return url
}

@Suite struct LeftoverScannerTests {
    let id = "dev.zed.Zed"

    @Test func findsFilesNamedExactlyForTheApp() {
        let lib = makeTempDir(); defer { removeTempDir(lib) }
        let expected = [
            "Application Scripts/dev.zed.Zed",
            "Application Support/Zed",
            "Application Support/dev.zed.Zed",
            "Caches/Zed",
            "Caches/dev.zed.Zed",
            "Containers/dev.zed.Zed",
            "Cookies/dev.zed.Zed.binarycookies",
            "Group Containers/ABCDE12345.dev.zed.Zed",
            "Group Containers/group.dev.zed.Zed",
            "HTTPStorages/dev.zed.Zed",
            "HTTPStorages/dev.zed.Zed.binarycookies",
            "LaunchAgents/dev.zed.Zed.plist",
            "Logs/Zed",
            "Logs/dev.zed.Zed",
            "Preferences/ByHost/dev.zed.Zed.0F1E2D3C-AAAA-BBBB-CCCC-123456789ABC.plist",
            "Preferences/dev.zed.Zed.plist",
            "Saved Application State/dev.zed.Zed.savedState",
            "WebKit/dev.zed.Zed",
        ]
        expected.forEach { touch($0, in: lib) }
        let found = LeftoverScanner.leftovers(bundleID: id, appName: "Zed", library: lib)
        #expect(found.map { String($0.path.dropFirst(lib.path.count + 1)) }.sorted() == expected.sorted())
    }

    @Test func ignoresLookalikesAndOtherApps() {
        let lib = makeTempDir(); defer { removeTempDir(lib) }
        [
            "Application Support/Zed Preview",          // another app's name
            "Application Support/dev.zed.Zed-Preview",
            "Caches/dev.zed.ZedPreview",
            "Caches/dev.zed",                           // a prefix of the id
            "Preferences/dev.zed.Zed.helper.plist",     // looks like a sibling app's id
            "Preferences/ByHost/dev.zed.Zed.helper.0F1E2D3C.plist",
            "LaunchAgents/dev.zed.Zed.updater.plist",
            "Group Containers/ABCDE12345.dev.zed.Zed.shared",
            "Application Support/zed",                  // folder names are matched exactly, case included
        ].forEach { touch($0, in: lib) }
        #expect(LeftoverScanner.leftovers(bundleID: id, appName: "Zed", library: lib).isEmpty)
    }

    @Test func appWithoutBundleIDOnlyMatchesItsName() {
        let lib = makeTempDir(); defer { removeTempDir(lib) }
        touch("Application Support/Tool", in: lib)
        touch("Caches/Tool", in: lib)
        let found = LeftoverScanner.leftovers(bundleID: nil, appName: "Tool", library: lib)
        #expect(found.map(\.lastPathComponent) == ["Tool", "Tool"])
    }

    @Test(arguments: ["", ".", "..", "a/b"])
    func unsafeNamesMatchNothing(name: String) {
        let lib = makeTempDir(); defer { removeTempDir(lib) }
        touch("Application Support/x", in: lib)
        #expect(LeftoverScanner.leftovers(bundleID: name.isEmpty ? nil : name, appName: name, library: lib).isEmpty)
    }
}

@Suite struct HomebrewCasksTests {
    func receipt(_ token: String, apps: String, in caskroom: URL) {
        let json = #"{"installed_on_request": true, "uninstall_artifacts": [{"app": [\#(apps)]}, {"zap": [{"trash": ["~/x"]}]}]}"#
        let url = caskroom.appendingPathComponent("\(token)/.metadata/INSTALL_RECEIPT.json")
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(json.utf8).write(to: url)
    }

    @Test func findsTheCaskThatInstalledTheApp() {
        let room = makeTempDir(); defer { removeTempDir(room) }
        receipt("ghostty", apps: #""Ghostty.app""#, in: room)
        receipt("wezterm", apps: #""WezTerm-macos-2024/WezTerm.app""#, in: room)
        receipt("renamed", apps: #""Source.app", {"target": "Pretty Name.app"}"#, in: room)
        #expect(HomebrewCasks.token(forApp: "/Applications/Ghostty.app", caskrooms: [room]) == "ghostty")
        #expect(HomebrewCasks.token(forApp: "/Applications/WezTerm.app", caskrooms: [room]) == "wezterm")
        #expect(HomebrewCasks.token(forApp: "/Applications/Pretty Name.app", caskrooms: [room]) == "renamed")
        #expect(HomebrewCasks.token(forApp: "/Applications/Zed.app", caskrooms: [room]) == nil)
    }

    @Test func missingOrBrokenCaskroomsFindNothing() {
        let room = makeTempDir(); defer { removeTempDir(room) }
        let url = room.appendingPathComponent("broken/.metadata/INSTALL_RECEIPT.json")
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data("not json".utf8).write(to: url)
        #expect(HomebrewCasks.token(forApp: "/Applications/Broken.app", caskrooms: [room, URL(fileURLWithPath: "/nonexistent")]) == nil)
    }

    @Test func commandZapsTheCask() {
        #expect(HomebrewCasks.uninstallCommand(token: "ghostty") == "brew uninstall --cask --zap ghostty")
    }
}

@Suite struct DiskUsageTests {
    @Test func addsUpEverythingInsideAFolder() {
        let root = makeTempDir(); defer { removeTempDir(root) }
        touch("a/one.txt", in: root, bytes: 5_000)
        touch("a/b/two.txt", in: root, bytes: 9_000)
        #expect(DiskUsage.bytes(at: root.appendingPathComponent("a")) >= 14_000)
        #expect(DiskUsage.bytes(at: root.appendingPathComponent("a/one.txt")) >= 5_000)
        #expect(DiskUsage.bytes(at: root.appendingPathComponent("missing")) == 0)
    }

    @Test func doesNotFollowSymlinks() throws {
        let root = makeTempDir(); defer { removeTempDir(root) }
        touch("big/blob.txt", in: root, bytes: 200_000)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("a/link"), withDestinationURL: root.appendingPathComponent("big"))
        #expect(DiskUsage.bytes(at: root.appendingPathComponent("a")) < 100_000)
    }
}

@MainActor final class FakeTrash: Trashing {
    private(set) var trashed: [String] = []
    var failing: Set<String> = []
    func moveToTrash(_ url: URL) async throws {
        if failing.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
        trashed.append(url.path)
    }
}

@MainActor @Suite struct UninstallCommandTests {
    let root = makeTempDir()
    var library: URL { root.appendingPathComponent("Library") }
    var caskroom: URL { root.appendingPathComponent("Caskroom") }
    var zedPath: String { root.appendingPathComponent("Applications/Zed.app").path }
    let trash = FakeTrash()
    let pasteboard = FakePasteboard()
    let running = FakeRunningApps([])

    func make(_ apps: [AppEntry]? = nil) -> UninstallCommand {
        touch("Applications/Zed.app", in: root, bytes: 50_000)
        let catalog = AppCatalog(scanner: FakeScanner(apps ?? [AppEntry(name: "Zed", path: zedPath, bundleID: "dev.zed.Zed")]))
        return UninstallCommand(catalog: catalog, runningApps: running, trash: trash, pasteboard: pasteboard,
                                library: library, caskrooms: [caskroom], ownBundleID: "dev.hammer.Hammer")
    }

    func checklist(_ command: UninstallCommand, _ title: String = "Zed") throws -> Checklist {
        let option = try #require(command.options().first { $0.title == title })
        guard case .confirm(let checklist) = command.run(.option(option)) else { throw CancellationError() }
        return checklist
    }

    @Test func listsAppsYouCanRemove() throws {
        defer { removeTempDir(root) }
        // Safari sits in /Applications but is a link into the protected system volume.
        let safari = root.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: safari, withDestinationURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        let c = make([AppEntry(name: "Zed", path: "/Applications/Zed.app", bundleID: "dev.zed.Zed"),
                      AppEntry(name: "Script", path: "/Applications/Script.app", bundleID: nil),
                      AppEntry(name: "Xcode", path: "/Applications/Xcode.app", bundleID: "com.apple.dt.Xcode"),
                      AppEntry(name: "Safari", path: safari.path, bundleID: "com.apple.Safari"),
                      AppEntry(name: "Notes", path: "/System/Applications/Notes.app", bundleID: "com.apple.Notes"),
                      AppEntry(name: "Thing", path: "/System/Applications/Thing.app", bundleID: "com.other.thing"),
                      AppEntry(name: "Hammer", path: "/Applications/Hammer.app", bundleID: "dev.hammer.Hammer")])
        #expect(c.name == "uninstall")
        #expect(c.options().map(\.title) == ["Script", "Xcode", "Zed"])
        #expect(c.options().last == CommandOption(id: "/Applications/Zed.app", title: "Zed", iconPath: "/Applications/Zed.app"))
    }

    @Test func choosingAnAppListsItAndItsLeftoversAllTicked() throws {
        defer { removeTempDir(root) }
        touch("Caches/dev.zed.Zed", in: library)
        touch("Application Support/Zed", in: library)
        let list = try checklist(make())
        #expect(list.title == "Uninstall Zed")
        #expect(list.confirmLabel == "Move to Trash")
        #expect(list.note == nil)
        // The test's root stands in for the home folder, so paths under it show with "~".
        #expect(list.items.map(\.title) == ["~/Applications/Zed.app", "~/Library/Application Support/Zed", "~/Library/Caches/dev.zed.Zed"])
        #expect(list.items.map(\.path) == [zedPath, library.appendingPathComponent("Application Support/Zed").path,
                                           library.appendingPathComponent("Caches/dev.zed.Zed").path])
        #expect(list.items.allSatisfy { $0.isChecked })
    }

    @Test func confirmMovesOnlyTickedItemsToTheTrash() async throws {
        defer { removeTempDir(root) }
        touch("Caches/dev.zed.Zed", in: library)
        touch("Application Support/Zed", in: library)
        let list = try checklist(make())
        list.toggle(at: 1)
        #expect(!list.items[1].isChecked)
        let message = await list.confirm()
        #expect(trash.trashed == [zedPath, library.appendingPathComponent("Caches/dev.zed.Zed").path])
        #expect(message?.hasPrefix("Moved 2 items to the Trash") == true)
    }

    @Test func nothingTickedDoesNothing() async throws {
        defer { removeTempDir(root) }
        let list = try checklist(make())
        list.toggle(at: 0)
        #expect(await list.confirm() == nil)
        #expect(trash.trashed.isEmpty)
    }

    @Test func runningAppIsAskedToQuitFirst() async throws {
        defer { removeTempDir(root) }
        running.apps = [RunningApp(pid: 7, name: "Zed", path: zedPath)]
        let list = try checklist(make())
        #expect(list.note == "Zed is running. Hammer will ask it to quit first.")
        _ = await list.confirm()
        #expect(running.quit == [7])
        #expect(running.forceQuit.isEmpty)
        #expect(trash.trashed == [zedPath])
    }

    @Test func appThatWontQuitIsLeftAlone() async throws {
        defer { removeTempDir(root) }
        running.apps = [RunningApp(pid: 7, name: "Zed", path: zedPath)]
        running.exitsWhenAsked = false
        let list = try checklist(make())
        #expect(await list.confirm() == "Zed is still running. Quit it, then try again.")
        #expect(running.forceQuit.isEmpty)
        #expect(trash.trashed.isEmpty)
    }

    @Test func itemsThatCantBeTrashedAreReported() async throws {
        defer { removeTempDir(root) }
        touch("Caches/dev.zed.Zed", in: library)
        trash.failing = ["Zed.app"]
        let list = try checklist(make())
        let message = try #require(await list.confirm())
        #expect(message == "Moved 1 item to the Trash. Couldn't move Zed.app.")
    }

    @Test func homebrewAppsGetTheBrewCommandInstead() async throws {
        defer { removeTempDir(root) }
        let url = caskroom.appendingPathComponent("zed/.metadata/INSTALL_RECEIPT.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"uninstall_artifacts": [{"app": ["Zed.app"]}]}"#.utf8).write(to: url)
        touch("Caches/dev.zed.Zed", in: library)
        let list = try checklist(make())
        #expect(list.items.isEmpty)
        #expect(list.confirmLabel == "Copy Command")
        #expect(list.note == "Zed was installed with Homebrew. Uninstall it with: brew uninstall --cask --zap zed")
        #expect(await list.confirm() == "Copied. Paste it into a terminal.")
        #expect(pasteboard.written.last == [Representation(type: PasteboardType.plainText, data: Data("brew uninstall --cask --zap zed".utf8))])
        #expect(trash.trashed.isEmpty)
    }

    @Test func sizesLoadInTheBackground() async throws {
        defer { removeTempDir(root) }
        touch("Caches/dev.zed.Zed", in: library, bytes: 30_000)
        let list = try checklist(make())
        #expect(list.items.allSatisfy { $0.bytes == nil })
        var changes = 0
        list.onChange = { changes += 1 }
        await list.loadSizes()
        #expect(list.items[0].bytes ?? 0 >= 50_000)
        #expect(list.items[1].bytes ?? 0 >= 30_000)
        #expect(list.checkedBytes >= 80_000)
        #expect(changes > 0)
        list.toggle(at: 0)
        #expect(list.checkedBytes < 80_000)
    }
}
