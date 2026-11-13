import Foundation
@testable import HammerCore

final class ManualClock: HammerClock, @unchecked Sendable {
    var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_794_571_200)) { current = start }  // 2026-11-13 12:00 UTC
    func now() -> Date { current }
    func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hammer-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTempDir(_ url: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    try? FileManager.default.removeItem(at: url)
}

let day: TimeInterval = 86_400

final class FakeScanner: AppScanning, @unchecked Sendable {
    var apps: [AppEntry]
    let roots: [URL] = [URL(fileURLWithPath: "/Applications")]
    init(_ apps: [AppEntry]) { self.apps = apps }
    func scan() -> [AppEntry] { apps }
}

@MainActor final class FakeWatcher: DirectoryWatching {
    private(set) var startedPaths: [URL] = []
    private var handler: (@MainActor () -> Void)?
    func start(paths: [URL], onChange: @escaping @MainActor () -> Void) { startedPaths = paths; handler = onChange }
    func stop() { handler = nil }
    func fire() { handler?() }
}

func app(_ name: String, _ path: String? = nil, bundleID: String? = nil) -> AppEntry {
    AppEntry(name: name, path: path ?? "/Applications/\(name).app", bundleID: bundleID ?? "com.test.\(name.lowercased())")
}

@MainActor final class FakeAppLauncher: AppLaunching {
    private(set) var opened: [String] = []
    func openApp(at path: String) { opened.append(path) }
}
