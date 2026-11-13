import AppKit
import HammerCore

/// `PasteboardAccess` backed by a real `NSPasteboard`. Reads only the types Hammer cares about.
@MainActor public final class SystemPasteboard: PasteboardAccess {
    private static let readTypes = PasteboardType.keptTypes.union([PasteboardType.fileURL])

    private let pasteboard: NSPasteboard
    private let frontmostAppName: () -> String?

    public init(pasteboard: NSPasteboard = .general,
                frontmostAppName: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.localizedName }) {
        self.pasteboard = pasteboard
        self.frontmostAppName = frontmostAppName
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func snapshot() -> PasteboardSnapshot {
        guard let item = pasteboard.pasteboardItems?.first else {
            return PasteboardSnapshot(representations: [], sourceApp: frontmostAppName())
        }
        let reps = item.types
            .filter { Self.readTypes.contains($0.rawValue) }
            .compactMap { type in item.data(forType: type).map { Representation(type: type.rawValue, data: $0) } }
        return PasteboardSnapshot(representations: reps, sourceApp: frontmostAppName())
    }

    @discardableResult
    public func write(_ reps: [Representation]) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for rep in reps { item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type)) }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}
