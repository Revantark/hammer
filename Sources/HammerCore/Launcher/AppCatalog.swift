import Foundation

public struct AppEntry: Equatable, Hashable, Sendable {
    public let name: String
    public let path: String
    public let bundleID: String?

    public init(name: String, path: String, bundleID: String?) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
    }
}

public protocol AppScanning: Sendable {
    var roots: [URL] { get }
    func scan() -> [AppEntry]
}

@MainActor public protocol DirectoryWatching: AnyObject {
    func start(paths: [URL], onChange: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor public final class AppCatalog {
    private let scanner: AppScanning
    private var watcher: DirectoryWatching?
    public private(set) var apps: [AppEntry] = []
    public var onChange: (() -> Void)?

    public init(scanner: AppScanning) {
        self.scanner = scanner
        apps = Self.normalize(scanner.scan())
    }

    public func reload() {
        apps = Self.normalize(scanner.scan())
        onChange?()
    }

    public func startWatching(_ watcher: DirectoryWatching) {
        self.watcher = watcher
        watcher.start(paths: scanner.roots) { [weak self] in self?.reload() }
    }

    /// Dedupes by bundle ID (preferring /Applications, then /System/Applications) and sorts by name.
    static func normalize(_ entries: [AppEntry]) -> [AppEntry] {
        var byBundle: [String: AppEntry] = [:]
        var unbundled: [AppEntry] = []
        for entry in entries {
            guard let id = entry.bundleID else { unbundled.append(entry); continue }
            if let existing = byBundle[id], priority(existing.path) <= priority(entry.path) { continue }
            byBundle[id] = entry
        }
        return (Array(byBundle.values) + unbundled).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    private static func priority(_ path: String) -> Int {
        if path.hasPrefix("/Applications/") { return 0 }
        if path.hasPrefix("/System/Applications/") { return 1 }
        return 2
    }
}

@MainActor public final class AppsSource: ResultSource {
    public static let typeLabel = "Application"
    public static let section = "Applications"

    private let catalog: AppCatalog

    public init(catalog: AppCatalog) {
        self.catalog = catalog
    }

    public func results(for query: String) -> [LauncherResult] {
        catalog.apps.compactMap { app in
            FuzzyMatcher.match(query, in: app.name).map {
                LauncherResult(id: app.path, title: app.name, typeLabel: Self.typeLabel, section: Self.section,
                               match: $0, action: .openApp(path: app.path))
            }
        }
    }
}
