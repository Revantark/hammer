import Foundation
import HammerCore

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hammer-mac-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTempDir(_ url: URL) { try? FileManager.default.removeItem(at: url) }

/// Creates a fake `.app` bundle with an Info.plist.
@discardableResult
func makeFakeApp(_ name: String, in dir: URL, bundleID: String? = nil) -> URL {
    let app = dir.appendingPathComponent("\(name).app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleName": name, "CFBundlePackageType": "APPL"]
    if let bundleID { plist["CFBundleIdentifier"] = bundleID }
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try! data.write(to: contents.appendingPathComponent("Info.plist"))
    return app
}

/// Waits for the first value from `stream`, or returns false after `timeout`. Returns as soon as a value arrives.
func firstEvent(_ stream: AsyncStream<Void>, timeout: Duration = .seconds(10)) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask { for await _ in stream { return true }; return false }
        group.addTask { try? await Task.sleep(for: timeout); return false }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
