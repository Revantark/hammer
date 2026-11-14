import Foundation

public struct ChecklistItem: Equatable, Sendable {
    public let path: String
    /// The path as shown, with "~" for the home folder.
    public let title: String
    public var isChecked: Bool
    /// Disk space; nil until measured.
    public var bytes: Int64?

    public init(path: String, title: String, isChecked: Bool = true, bytes: Int64? = nil) {
        self.path = path
        self.title = title
        self.isChecked = isChecked
        self.bytes = bytes
    }
}

/// A list the person reviews before a command acts on it (files to move to the Trash).
@MainActor public final class Checklist {
    public let title: String
    /// One line above the list (the app is running, it came from Homebrew).
    public let note: String?
    public let confirmLabel: String
    /// Shown while the confirm action runs.
    public let workingTitle: String
    public private(set) var items: [ChecklistItem]
    public private(set) var isWorking = false
    public var onChange: (() -> Void)?

    private let sizer: @Sendable (String) -> Int64
    private let perform: @MainActor ([ChecklistItem]) async -> CommandReport

    public init(title: String, note: String?, confirmLabel: String, workingTitle: String = "Working…", items: [ChecklistItem],
                sizer: @escaping @Sendable (String) -> Int64 = { DiskUsage.bytes(at: URL(fileURLWithPath: $0)) },
                perform: @escaping @MainActor ([ChecklistItem]) async -> CommandReport) {
        self.title = title
        self.workingTitle = workingTitle
        self.note = note
        self.confirmLabel = confirmLabel
        self.items = items
        self.sizer = sizer
        self.perform = perform
    }

    public var checkedItems: [ChecklistItem] { items.filter(\.isChecked) }
    public var checkedBytes: Int64 { checkedItems.reduce(0) { $0 + ($1.bytes ?? 0) } }

    public func toggle(at index: Int) {
        guard items.indices.contains(index), !isWorking else { return }
        items[index].isChecked.toggle()
        onChange?()
    }

    /// Measures each item off the main thread, updating as each finishes.
    public func loadSizes() async {
        for index in items.indices where items[index].bytes == nil {
            let path = items[index].path
            let bytes = await Task.detached(priority: .userInitiated) { [sizer] in sizer(path) }.value
            if Task.isCancelled { return }
            items[index].bytes = bytes
            onChange?()
        }
    }

    /// Runs the action and returns its report. Nil when nothing is ticked or it's already running.
    public func confirm() async -> CommandReport? {
        guard !isWorking, items.isEmpty || !checkedItems.isEmpty else { return nil }
        isWorking = true
        onChange?()
        let report = await perform(checkedItems)
        isWorking = false
        onChange?()
        return report
    }
}

public enum DiskUsage {
    /// Space a file or folder takes on disk, counting everything inside and not following symlinks. 0 if it's missing.
    public static func bytes(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        func size(_ u: URL) -> Int64 {
            Int64((try? u.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return size(url) }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let item = walker?.nextObject() as? URL { total += size(item) }
        return total
    }
}
