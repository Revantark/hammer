import Foundation

/// What a command takes after its name.
public enum CommandArgumentKind: Equatable, Sendable {
    /// Nothing: Enter runs the command.
    case none
    /// One of a list the command knows (installed apps, running apps). Typing filters the list.
    case option
    /// Any text. Enter runs the command with exactly what was typed.
    case text
}

/// One choice in an `.option` command's list.
public struct CommandOption: Equatable, Sendable {
    public let id: String
    public let title: String
    /// File whose icon the row shows (an app bundle), if any.
    public let iconPath: String?

    public init(id: String, title: String, iconPath: String?) {
        self.id = id
        self.title = title
        self.iconPath = iconPath
    }
}

/// The argument a command runs with.
public enum CommandArgument: Equatable, Sendable {
    case none
    case option(CommandOption)
    case text(String)
}

/// What a command did, shown on the panel's result screen.
public struct CommandReport: Equatable, Sendable {
    public let succeeded: Bool
    /// "Zed moved to the Trash".
    public let title: String
    /// Details under the title: sizes, what failed, what to do next.
    public let lines: [String]

    public init(succeeded: Bool, title: String, lines: [String]) {
        self.succeeded = succeeded
        self.title = title
        self.lines = lines
    }
}

/// What the panel does after a command ran.
public enum CommandOutcome {
    /// Nothing to show: the panel closes.
    case done
    /// Show this list for the person to review; Enter confirms it.
    case confirm(Checklist)
    /// Show `title` while `work` runs, then its report. `keepsPanelOpen`: stay up even if another window
    /// (a password prompt) takes focus meanwhile.
    case working(title: String, keepsPanelOpen: Bool, work: @MainActor () async -> CommandReport)
}

/// A `/name` command in the launcher.
@MainActor public protocol HammerCommand: AnyObject {
    /// Typed after "/", lowercase, no spaces.
    var name: String { get }
    /// One line shown next to the command.
    var summary: String { get }
    var argument: CommandArgumentKind { get }
    /// Section header above the options.
    var optionsTitle: String { get }
    /// What Enter does to an option ("Force Quit"); shown on each option row and in the footer.
    var actionLabel: String { get }
    /// The full list for `.option` commands, in any order. Called on every keystroke, so keep it cheap.
    func options() -> [CommandOption]
    func run(_ argument: CommandArgument) -> CommandOutcome
}

/// A launcher query that starts with "/".
public enum CommandQuery: Equatable, Sendable {
    /// Choosing a command: "/" or "/unin".
    case commands(filter: String)
    /// A command's name was typed in full: "/uninstall" or "/uninstall ze".
    case argument(name: String, text: String)

    /// Nil unless the query starts with "/". A full command name (with or without a space after it) switches to its argument.
    public static func parse(_ query: String, commandNames: [String]) -> CommandQuery? {
        guard query.first == "/" else { return nil }
        let body = query.dropFirst()
        let head = String(body.prefix { $0 != " " }).lowercased()
        if commandNames.contains(head) {
            return .argument(name: head, text: body.dropFirst(head.count).trimmingCharacters(in: .whitespaces))
        }
        return .commands(filter: body.lowercased())
    }
}

/// Every command, and the launcher rows for a "/" query.
@MainActor public final class CommandRegistry {
    public static let section = "Commands"

    private let commands: [HammerCommand]

    public init(_ commands: [HammerCommand]) {
        self.commands = commands.sorted { $0.name < $1.name }
    }

    public func command(named name: String) -> HammerCommand? {
        commands.first { $0.name == name }
    }

    /// Nil when the query isn't a command query, so other sources answer it.
    public func results(for query: String) -> [LauncherResult]? {
        switch CommandQuery.parse(query, commandNames: commands.map(\.name)) {
        case nil:
            return nil
        case .commands(let filter):
            return commands
                .compactMap { c in FuzzyMatcher.match(filter, in: c.name).map { (command: c, match: $0) } }
                .sorted { a, b in
                    if a.match.tier != b.match.tier { return a.match.tier > b.match.tier }
                    if a.match.score != b.match.score { return a.match.score > b.match.score }
                    return a.command.name < b.command.name
                }
                .map { Self.row(for: $0.command, match: $0.match) }
        case .argument(let name, let text):
            guard let command = command(named: name) else { return [] }
            switch command.argument {
            case .none:
                return [Self.row(for: command, match: FuzzyMatch(tier: .exact, score: 0))]
            case .text:
                guard !text.isEmpty else { return [] }
                return [LauncherResult(id: "command:\(name):text", title: text, typeLabel: command.actionLabel, section: command.summary,
                                       match: FuzzyMatch(tier: .exact, score: 0), action: .runCommand(name: name, argument: .text(text)))]
            case .option:
                return command.options()
                    .compactMap { o in FuzzyMatcher.match(text, in: o.title).map { (option: o, match: $0) } }
                    .sorted { a, b in
                        if a.match.tier != b.match.tier { return a.match.tier > b.match.tier }
                        if a.match.score != b.match.score { return a.match.score > b.match.score }
                        return a.option.title.localizedStandardCompare(b.option.title) == .orderedAscending
                    }
                    .map { LauncherResult(id: "command:\(name):\($0.option.id)", title: $0.option.title, typeLabel: command.actionLabel,
                                          section: command.optionsTitle, match: $0.match,
                                          action: .runCommand(name: name, argument: .option($0.option))) }
            }
        }
    }

    /// Nil when no command has that name.
    public func run(name: String, argument: CommandArgument) -> CommandOutcome? {
        command(named: name)?.run(argument)
    }

    private static func row(for command: HammerCommand, match: FuzzyMatch) -> LauncherResult {
        LauncherResult(id: "command:\(command.name)", title: "/\(command.name)", typeLabel: command.summary, section: section, match: match,
                       action: command.argument == .none ? .runCommand(name: command.name, argument: .none) : .completeCommand(command.name))
    }
}
