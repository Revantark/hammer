import Foundation

/// Source of "now". Injected everywhere so tests can control time.
public protocol HammerClock: Sendable {
    func now() -> Date
}

public struct SystemClock: HammerClock {
    public init() {}
    public func now() -> Date { Date() }
}
