import Foundation

/// How a query matched a candidate. Higher tiers always rank above lower ones.
public enum MatchTier: Int, Comparable, Sendable {
    case subsequence = 0, substring = 1, wordPrefix = 2, initials = 3, prefix = 4, exact = 5

    public static func < (lhs: MatchTier, rhs: MatchTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct FuzzyMatch: Equatable, Sendable {
    public let tier: MatchTier
    /// Fine-grained score within a tier (higher is better, never negative).
    public let score: Int

    public init(tier: MatchTier, score: Int) {
        self.tier = tier
        self.score = score
    }
}

public enum FuzzyMatcher {
    /// Matches `query` against `candidate`. Returns nil when there is no match.
    /// An empty or whitespace-only query matches everything with score 0.
    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let q = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if q.isEmpty { return FuzzyMatch(tier: .subsequence, score: 0) }

        let c = normalize(candidate)
        let qChars = Array(q)
        let cChars = Array(c)
        let base = max(0, 1000 - 10 * max(0, cChars.count - qChars.count))

        if c == q { return FuzzyMatch(tier: .exact, score: base) }
        if c.hasPrefix(q) { return FuzzyMatch(tier: .prefix, score: base) }

        let words = splitWords(candidate).map(normalize)
        let initials = String(words.compactMap(\.first))
        if qChars.count >= 2, initials.hasPrefix(q) { return FuzzyMatch(tier: .initials, score: base) }
        if words.contains(where: { $0.hasPrefix(q) }) || queryWordsPrefixWords(q, words) {
            return FuzzyMatch(tier: .wordPrefix, score: base)
        }
        if c.contains(q) { return FuzzyMatch(tier: .substring, score: base) }

        guard let gaps = subsequenceGaps(qChars, cChars) else { return nil }
        return FuzzyMatch(tier: .subsequence, score: max(0, base - 5 * gaps))
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Splits on whitespace, `-`, `_`, `.` and lower→upper camel-case boundaries.
    static func splitWords(_ s: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for ch in s {
            if ch.isWhitespace || ch == "-" || ch == "_" || ch == "." {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                if let p = previous, p.isLowercase, ch.isUppercase, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(ch)
            }
            previous = ch
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// "sys set" vs ["system", "settings"]: each query word prefixes a later candidate word, in order.
    private static func queryWordsPrefixWords(_ q: String, _ words: [String]) -> Bool {
        let qWords = q.split(whereSeparator: \.isWhitespace).map(String.init)
        guard qWords.count > 1 else { return false }
        var index = 0
        for qw in qWords {
            while index < words.count, !words[index].hasPrefix(qw) { index += 1 }
            if index == words.count { return false }
            index += 1
        }
        return true
    }

    /// Greedy in-order subsequence match; returns total gap length between matched characters.
    private static func subsequenceGaps(_ q: [Character], _ c: [Character]) -> Int? {
        var qi = 0
        var gaps = 0
        var lastMatch: Int?
        for (ci, ch) in c.enumerated() where qi < q.count {
            if ch == q[qi] {
                if let last = lastMatch { gaps += ci - last - 1 }
                lastMatch = ci
                qi += 1
            }
        }
        return qi == q.count ? gaps : nil
    }
}
