import Foundation
import HammerCore

/// Moves files to the Trash. Items you can't move yourself (root-owned apps from the App Store or an installer)
/// go through Finder, which asks for your password.
@MainActor public final class WorkspaceTrash: Trashing {
    public init() {}

    public func moveToTrash(_ url: URL) async throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch where Self.needsFinder(error) {
            try await Self.finderDelete(url)
        }
    }

    nonisolated static func needsFinder(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteNoPermission.rawValue { return true }
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying?.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(underlying?.code ?? 0)
    }

    /// The path goes in as an argument, never into the script text.
    nonisolated static func finderArguments(path: String) -> [String] {
        ["-e", "on run argv", "-e", "tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)", "-e", "end run", path]
    }

    struct FinderFailed: Error {}

    private static func finderDelete(_ url: URL) async throws {
        let arguments = finderArguments(path: url.path)
        let status = await Task.detached { () -> Int32 in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        if status != 0 { throw FinderFailed() }
    }
}
