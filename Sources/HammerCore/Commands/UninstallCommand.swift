import Foundation

/// Moves files to the Trash.
@MainActor public protocol Trashing: AnyObject {
    func moveToTrash(_ url: URL) async throws
}

/// `/uninstall <app>`: shows the app and the files it left in ~/Library, then moves the ticked ones to the Trash.
@MainActor public final class UninstallCommand: HammerCommand {
    public let name = "uninstall"
    public let summary = "Uninstall an app"
    public let argument = CommandArgumentKind.option
    public let optionsTitle = "Applications"
    public let actionLabel = "Uninstall"

    private let catalog: AppCatalog
    private let runningApps: RunningAppControlling
    private let trash: Trashing
    private let pasteboard: PasteboardAccess
    private let library: URL
    private let caskrooms: [URL]
    private let ownBundleID: String?

    public init(catalog: AppCatalog, runningApps: RunningAppControlling, trash: Trashing, pasteboard: PasteboardAccess,
                library: URL, caskrooms: [URL], ownBundleID: String?) {
        self.catalog = catalog
        self.runningApps = runningApps
        self.trash = trash
        self.pasteboard = pasteboard
        self.library = library
        self.caskrooms = caskrooms
        self.ownBundleID = ownBundleID
    }

    /// Not apps on the protected system volume (Safari's /Applications entry is a link there) and not Hammer.
    /// Apple apps you installed yourself (Xcode, Pages) are listed.
    public func options() -> [CommandOption] {
        catalog.apps.filter { app in
            !URL(fileURLWithPath: app.path).resolvingSymlinksInPath().path.hasPrefix("/System/")
                && (app.bundleID == nil || app.bundleID != ownBundleID)
        }.map { CommandOption(id: $0.path, title: $0.name, iconPath: $0.path) }
    }

    public func run(_ argument: CommandArgument) -> CommandOutcome {
        guard case .option(let option) = argument, let app = catalog.apps.first(where: { $0.path == option.id }) else { return .done }
        if let token = HomebrewCasks.token(forApp: app.path, caskrooms: caskrooms) {
            let command = HomebrewCasks.uninstallCommand(token: token)
            return .confirm(Checklist(title: "Uninstall \(app.name)", note: "\(app.name) was installed with Homebrew. Uninstall it with: \(command)",
                                      confirmLabel: "Copy Command", items: []) { [pasteboard] _ in
                _ = pasteboard.write([Representation(type: PasteboardType.plainText, data: Data(command.utf8))])
                return CommandReport(succeeded: true, title: "Copied the Homebrew command",
                                     lines: [command, "Paste it into a terminal to uninstall \(app.name)."])
            })
        }
        let home = library.deletingLastPathComponent().path
        let paths = [app.path] + LeftoverScanner.leftovers(bundleID: app.bundleID, appName: app.name, library: library).map(\.path)
        let items = paths.map { ChecklistItem(path: $0, title: $0.hasPrefix(home + "/") ? "~" + $0.dropFirst(home.count) : $0) }
        let isRunning = runningApps.runningApps().contains { $0.path == app.path }
        return .confirm(Checklist(title: "Uninstall \(app.name)", note: isRunning ? "\(app.name) is running. Hammer will ask it to quit first." : nil,
                                  confirmLabel: "Move to Trash", workingTitle: "Moving to the Trash…", items: items) { checked in
            await self.uninstall(app, items: checked)   // strong: the list must work even if the command goes away; no cycle
        })
    }

    private func uninstall(_ app: AppEntry, items: [ChecklistItem]) async -> CommandReport {
        // Quit first even when only leftovers are ticked: an app rewrites its files while it runs.
        for running in runningApps.runningApps() where running.path == app.path {
            runningApps.quit(pid: running.pid)
            guard await runningApps.waitForExit(pid: running.pid, timeout: .seconds(5)) else {
                return CommandReport(succeeded: false, title: "\(app.name) is still running", lines: ["Quit it, then try again."])
            }
        }
        var moved: [ChecklistItem] = []
        var failed: [ChecklistItem] = []
        for item in items {
            do {
                try await trash.moveToTrash(URL(fileURLWithPath: item.path))
                moved.append(item)
            } catch {
                failed.append(item)
            }
        }
        if moved.contains(where: { $0.path == app.path }) { catalog.reload() }   // drop it from the list now, not when FSEvents notices
        return Self.report(appName: app.name, appPath: app.path, moved: moved, failed: failed)
    }

    nonisolated static func report(appName: String, appPath: String, moved: [ChecklistItem], failed: [ChecklistItem]) -> CommandReport {
        let title: String
        if failed.contains(where: { $0.path == appPath }) {
            title = "Couldn't move \(appName) to the Trash"
        } else if moved.contains(where: { $0.path == appPath }) {
            title = "\(appName) moved to the Trash"
        } else if moved.isEmpty {
            title = "Couldn't move \(appName)'s files to the Trash"
        } else {
            title = "\(appName)'s files moved to the Trash"
        }
        var lines: [String] = []
        if !moved.isEmpty {
            let bytes = moved.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            var line = "\(moved.count) \(moved.count == 1 ? "item" : "items")" + (failed.isEmpty ? "" : " moved")
            if bytes > 0 { line += " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
            lines.append(line)
        }
        let shown = 3
        lines += failed.prefix(shown).map { "Couldn't move \($0.title)" }
        if failed.count > shown { lines.append("Couldn't move \(failed.count - shown) more") }
        return CommandReport(succeeded: failed.isEmpty, title: title, lines: lines)
    }
}

/// Finds what an app left in ~/Library. Only names that are exactly the app's bundle ID or name count, so other apps' files never match.
public enum LeftoverScanner {
    /// Existing leftovers, sorted by path.
    public static func leftovers(bundleID: String?, appName: String, library: URL) -> [URL] {
        let id = bundleID.flatMap { isSafe($0) ? $0 : nil }
        let name = isSafe(appName) ? appName : nil
        var rules: [(folder: String, matches: (String) -> Bool)] = []
        if let id {
            for folder in ["Application Scripts", "Containers", "HTTPStorages", "WebKit"] {
                rules.append((folder, { $0 == id }))
            }
            rules.append(("Preferences", { $0 == id + ".plist" }))
            rules.append(("Preferences/ByHost", { file in   // <id>.<hardware UUID>.plist
                guard file.hasPrefix(id + "."), file.hasSuffix(".plist") else { return false }
                let middle = file.dropFirst(id.count + 1).dropLast(".plist".count)
                return !middle.isEmpty && !middle.contains(".")
            }))
            rules.append(("Saved Application State", { $0 == id + ".savedState" }))
            rules.append(("Cookies", { $0 == id + ".binarycookies" }))
            rules.append(("HTTPStorages", { $0 == id + ".binarycookies" }))
            rules.append(("LaunchAgents", { $0 == id + ".plist" }))
            rules.append(("Group Containers", { $0 == "group." + id || ($0.hasSuffix("." + id) && !$0.dropLast(id.count + 1).contains(".")) }))
        }
        for folder in ["Application Support", "Caches", "Logs"] {
            rules.append((folder, { $0 == id || $0 == name }))
        }
        var found = Set<String>()
        for rule in rules {
            let dir = library.appendingPathComponent(rule.folder)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in names where rule.matches(file) { found.insert(dir.appendingPathComponent(file).path) }
        }
        return found.sorted().map { URL(fileURLWithPath: $0) }
    }

    private static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }
}

/// Apps installed with Homebrew casks, found from each cask's install receipt.
public enum HomebrewCasks {
    public static let defaultCaskrooms = [URL(fileURLWithPath: "/opt/homebrew/Caskroom"), URL(fileURLWithPath: "/usr/local/Caskroom")]

    /// The cask that installed the app at `appPath`, if any.
    public static func token(forApp appPath: String, caskrooms: [URL]) -> String? {
        let bundleName = URL(fileURLWithPath: appPath).lastPathComponent
        for room in caskrooms {
            guard let tokens = try? FileManager.default.contentsOfDirectory(atPath: room.path) else { continue }
            for token in tokens.sorted() {
                let receipt = room.appendingPathComponent("\(token)/.metadata/INSTALL_RECEIPT.json")
                guard let data = try? Data(contentsOf: receipt),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let artifacts = json["uninstall_artifacts"] as? [[String: Any]] else { continue }
                for artifact in artifacts {
                    for entry in artifact["app"] as? [Any] ?? [] {
                        // "Zed.app", "Folder/Zed.app", or {"target": "Renamed.app"} after the source name.
                        let path = (entry as? String) ?? ((entry as? [String: Any])?["target"] as? String)
                        if let path, URL(fileURLWithPath: path).lastPathComponent == bundleName { return token }
                    }
                }
            }
        }
        return nil
    }

    public static func uninstallCommand(token: String) -> String {
        "brew uninstall --cask --zap \(token)"
    }
}
