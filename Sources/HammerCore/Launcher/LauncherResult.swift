import Foundation

/// What happens when a launcher result is chosen. Future sources add cases.
public enum LauncherAction: Equatable, Sendable {
    case openApp(path: String)
}

public struct LauncherResult: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let typeLabel: String
    public let section: String
    public let match: FuzzyMatch
    public let action: LauncherAction

    public init(id: String, title: String, typeLabel: String, section: String, match: FuzzyMatch, action: LauncherAction) {
        self.id = id
        self.title = title
        self.typeLabel = typeLabel
        self.section = section
        self.match = match
        self.action = action
    }
}

/// A provider of launcher results (apps today; files, calculator, conversions later).
@MainActor public protocol ResultSource: AnyObject {
    func results(for query: String) -> [LauncherResult]
}
