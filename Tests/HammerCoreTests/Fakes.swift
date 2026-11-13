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

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makePNG(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = ctx.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

func rep(_ type: String, _ text: String) -> Representation { Representation(type: type, data: Data(text.utf8)) }
func textSnapshot(_ text: String, source: String? = "Notes") -> PasteboardSnapshot {
    PasteboardSnapshot(representations: [rep(PasteboardType.plainText, text)], sourceApp: source)
}
