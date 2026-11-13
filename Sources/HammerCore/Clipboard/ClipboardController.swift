import Foundation
import os

@MainActor public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    /// Replaces the pasteboard contents; returns the new change count.
    @discardableResult func write(_ reps: [Representation]) -> Int
}

@MainActor public protocol PasteSending: AnyObject {
    var isTrusted: Bool { get }
    func sendPaste()
    func requestTrust()
}

public enum PasteOutcome: Equatable, Sendable {
    case pasted
    /// No Accessibility permission: the entry is on the clipboard, the user presses ⌘V.
    case copiedOnly
}

@MainActor public final class ClipboardController {
    public static let pollInterval: TimeInterval = 0.25
    private static let log = Logger(subsystem: "dev.hammer", category: "clipboard")

    private let pasteboard: PasteboardAccess
    private let store: ClipStore
    private let clock: HammerClock
    private let makeID: () -> UUID
    private var lastSeenChangeCount: Int

    public private(set) var history: ClipHistory
    public var onChange: (() -> Void)?

    public init(pasteboard: PasteboardAccess, store: ClipStore, clock: HammerClock, makeID: @escaping () -> UUID = UUID.init) {
        self.pasteboard = pasteboard
        self.store = store
        self.clock = clock
        self.makeID = makeID
        history = store.loadHistory()
        store.pruneOrphans(keeping: Set(history.entries.map(\.id)))
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// Called on a timer. Captures a new copy if the pasteboard changed since the last poll.
    public func poll() {
        let count = pasteboard.changeCount
        guard count != lastSeenChangeCount else { return }
        lastSeenChangeCount = count
        guard let candidate = ClipClassifier.classify(pasteboard.snapshot(), id: makeID(), at: clock.now()) else { return }

        switch history.insert(candidate.entry) {
        case .added(let evicted):
            do {
                try store.writePayload(candidate.representations, id: candidate.entry.id)
            } catch {
                Self.log.error("Writing clipboard payload failed: \(error.localizedDescription, privacy: .public)")
            }
            store.deletePayloads(evicted)
        case .movedToTop:
            break
        }
        save()
        onChange?()
    }

    /// Puts the entry back on the pasteboard, moves it to the top, then pastes (or asks for permission).
    public func paste(id: UUID, sender: PasteSending, beforePaste: () -> Void) -> PasteOutcome? {
        guard history.entries.contains(where: { $0.id == id }), let reps = payload(id: id) else { return nil }
        lastSeenChangeCount = pasteboard.write(reps)
        history.moveToTop(id: id, at: clock.now())
        save()
        beforePaste()
        guard sender.isTrusted else {
            sender.requestTrust()
            return .copiedOnly
        }
        sender.sendPaste()
        return .pasted
    }

    public func payload(id: UUID) -> [Representation]? {
        try? store.readPayload(id: id)
    }

    public func clearAll() {
        store.deletePayloads(history.removeAll())
        store.pruneOrphans(keeping: [])
        save()
        onChange?()
    }

    private func save() {
        do {
            try store.saveHistory(history)
        } catch {
            Self.log.error("Saving clipboard history failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
