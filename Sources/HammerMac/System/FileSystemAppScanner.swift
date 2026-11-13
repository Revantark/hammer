import Foundation
import HammerCore

/// Finds `.app` bundles under the given roots (recursively, never inside bundles).
public struct FileSystemAppScanner: AppScanning {
    public static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
    ]

    public let roots: [URL]

    public init(roots: [URL] = defaultRoots) {
        self.roots = roots
    }

    public func scan() -> [AppEntry] {
        let fm = FileManager.default
        var apps: [AppEntry] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                enumerator.skipDescendants()
                apps.append(AppEntry(name: Self.displayName(url), path: url.path, bundleID: Self.bundleID(url)))
            }
        }
        return apps
    }

    static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Reads CFBundleIdentifier without creating (globally cached) `Bundle` objects.
    static func bundleID(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }
}
