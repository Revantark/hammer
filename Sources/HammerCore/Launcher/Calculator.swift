import Foundation

/// Inline arithmetic for the launcher: `8/32`, `10 % 3`, `8(5+3*2+(4*2 + 5 - 10)/2)`.
///
/// Operators, loosest first: `+ -`, then `* × / ÷ %` and implicit multiplication (`2(3)`, `(1+2)(3+4)`, `2pi`),
/// then unary `-`, then `^` (right-associative, so `-2^2` = -4 and `2^3^2` = 512).
/// `%` between two operands is the remainder (sign follows the left side); `%` after a number with nothing after
/// it, or before `+ - ) ^`, means percent (`50%` = 0.5, `200*10%` = 20).
/// Also: `sqrt(x)`, `√x`, `pi`/`π`, `e`. Parentheses left open at the end close themselves.
public enum Calculator {
    public static let section = "Calculator"

    /// A launcher row for `query` when it's a calculation (not a plain number) with a finite result.
    public static func result(for query: String) -> LauncherResult? {
        guard let (value, operations) = parse(query), operations > 0 else { return nil }
        let text = format(value)
        return LauncherResult(id: "calculator", title: text, typeLabel: "Copy", section: section,
                              match: FuzzyMatch(tier: .exact, score: 0), action: .copyText(text))
    }

    public static func evaluate(_ expression: String) -> Double? {
        parse(expression)?.value
    }

    /// Whole numbers below 10^15 in full; everything else to 12 significant digits (0.1 + 0.2 shows 0.3).
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.12g", value)
    }

    private static func parse(_ expression: String) -> (value: Double, operations: Int)? {
        var parser = Parser(tokens: tokenize(expression) ?? [])
        guard !parser.tokens.isEmpty, let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return (value, parser.operations)
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case name(String)
        case op(Character)
        case open, close
    }

    static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace {
                i = s.index(after: i)
            } else if c.isASCII && (c.isNumber || c == ".") {
                var j = i
                while j < s.endIndex, s[j].isASCII, s[j].isNumber || s[j] == "." { j = s.index(after: j) }
                guard let n = Double(s[i..<j]) else { return nil }   // "2..3"
                tokens.append(.number(n))
                i = j
            } else if c.isLetter {
                var j = i
                while j < s.endIndex, s[j].isLetter { j = s.index(after: j) }
                tokens.append(.name(s[i..<j].lowercased()))
                i = j
            } else if c == "(" {
                tokens.append(.open); i = s.index(after: i)
            } else if c == ")" {
                tokens.append(.close); i = s.index(after: i)
            } else if "+-*/%^×÷√".contains(c) {
                tokens.append(.op(c == "×" ? "*" : c == "÷" ? "/" : c)); i = s.index(after: i)
            } else {
                return nil
            }
        }
        return tokens
    }

    // MARK: Parser (recursive descent)

    struct Parser {
        let tokens: [Token]
        var position = 0
        /// Binary operators, implicit multiplications, percents and functions seen; a plain number (even `(5)`) has 0.
        var operations = 0

        var atEnd: Bool { position == tokens.count }
        var current: Token? { position < tokens.count ? tokens[position] : nil }
        var next: Token? { position + 1 < tokens.count ? tokens[position + 1] : nil }

        /// expression := term (("+" | "-") term)*
        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while case .op(let c) = current, c == "+" || c == "-" {
                position += 1
                guard let rhs = term() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
                operations += 1
            }
            return value
        }

        /// term := unary (("*" | "/" | "%") unary | implicit-multiplication unary)*
        mutating func term() -> Double? {
            guard var value = unary() else { return nil }
            while true {
                if case .op(let c) = current, c == "*" || c == "/" || c == "%" {
                    position += 1
                    guard let rhs = unary() else { return nil }
                    switch c {
                    case "*": value *= rhs
                    case "/": guard rhs != 0 else { return nil }; value /= rhs
                    default: guard rhs != 0 else { return nil }; value = fmod(value, rhs)
                    }
                    operations += 1
                } else if startsImplicitFactor(after: tokens[position - 1]) {
                    guard let rhs = unary() else { return nil }
                    value *= rhs
                    operations += 1
                } else {
                    return value
                }
            }
        }

        /// `2(`, `)(`, `2pi`, `2√`, `)2`.
        func startsImplicitFactor(after previous: Token) -> Bool {
            switch (previous, current) {
            case (_, .open), (_, .name), (_, .op("√")): return true
            case (.close, .number): return true
            default: return false
            }
        }

        /// unary := ("-" | "+") unary | power
        mutating func unary() -> Double? {
            if case .op(let c) = current, c == "-" || c == "+" {
                position += 1
                guard let value = unary() else { return nil }
                return c == "-" ? -value : value
            }
            return power()
        }

        /// power := percent ("^" unary)?
        mutating func power() -> Double? {
            guard let base = percent() else { return nil }
            guard case .op("^") = current else { return base }
            position += 1
            guard let exponent = unary() else { return nil }
            operations += 1
            return pow(base, exponent)
        }

        /// percent := primary "%"*, where "%" counts as percent only when no operand follows it.
        mutating func percent() -> Double? {
            guard var value = primary() else { return nil }
            while case .op("%") = current, !operandFollowsPercent {
                position += 1
                value /= 100
                operations += 1
            }
            return value
        }

        var operandFollowsPercent: Bool {
            switch next {
            case .number, .name, .open, .op("√"): return true
            default: return false
            }
        }

        /// primary := number | "(" expression ")"? | "√" percent | name ["(" expression ")"?]
        mutating func primary() -> Double? {
            guard let token = current else { return nil }
            position += 1
            switch token {
            case .number(let n):
                return n
            case .open:
                return parenthesized()
            case .op("√"):
                guard let x = power(), x >= 0 else { return nil }
                operations += 1
                return x.squareRoot()
            case .name(let name):
                switch name {
                case "pi", "π": return .pi
                case "e": return M_E
                case "sqrt":
                    guard case .open = current else { return nil }
                    position += 1
                    guard let x = parenthesized(), x >= 0 else { return nil }
                    operations += 1
                    return x.squareRoot()
                default: return nil
                }
            default:
                return nil
            }
        }

        /// After "(": the expression, then ")" (optional at the very end, so a half-typed `2*(3+4` still works).
        mutating func parenthesized() -> Double? {
            guard let value = expression() else { return nil }
            if case .close = current { position += 1; return value }
            return atEnd ? value : nil
        }
    }
}
