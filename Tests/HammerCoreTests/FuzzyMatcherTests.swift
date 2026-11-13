import Testing
@testable import HammerCore

@Suite struct FuzzyMatcherTests {
    @Test func exactMatch() { #expect(FuzzyMatcher.match("safari", in: "Safari")?.tier == .exact) }
    @Test func prefix() { #expect(FuzzyMatcher.match("saf", in: "Safari")?.tier == .prefix) }
    @Test func initials() { #expect(FuzzyMatcher.match("vsc", in: "Visual Studio Code")?.tier == .initials) }
    @Test func initialsCamelCase() { #expect(FuzzyMatcher.match("tp", in: "TablePlus")?.tier == .initials) }
    @Test func wordPrefix() { #expect(FuzzyMatcher.match("stud", in: "Visual Studio Code")?.tier == .wordPrefix) }
    @Test func multiWordQueryMatchesWordPrefixes() { #expect(FuzzyMatcher.match("sys set", in: "System Settings")?.tier == .wordPrefix) }
    @Test func substring() { #expect(FuzzyMatcher.match("fari", in: "Safari")?.tier == .substring) }
    @Test func subsequence() { #expect(FuzzyMatcher.match("sfri", in: "Safari")?.tier == .subsequence) }
    @Test func noMatch() { #expect(FuzzyMatcher.match("zz", in: "Safari") == nil) }
    @Test func caseAndDiacritics() { #expect(FuzzyMatcher.match("cafe", in: "Café Menu")?.tier == .prefix) }
    @Test func trimsWhitespace() {
        #expect(FuzzyMatcher.match("  saf ", in: "Safari")?.tier == .prefix)
        #expect(FuzzyMatcher.match("   ", in: "Safari") == FuzzyMatch(tier: .subsequence, score: 0))
    }
    @Test func emptyQuery() { #expect(FuzzyMatcher.match("", in: "Safari") == FuzzyMatch(tier: .subsequence, score: 0)) }
    @Test func specialCharacters() {
        #expect(FuzzyMatcher.match("c++", in: "C++ Builder")?.tier == .prefix)
        #expect(FuzzyMatcher.match("🙂", in: "Safari") == nil)
    }
    @Test func tighterSubsequenceScoresHigher() {
        let tight = FuzzyMatcher.match("sfr", in: "Sfxr")!
        let loose = FuzzyMatcher.match("sfr", in: "Sxfxr")!
        #expect(tight.tier == .subsequence && loose.tier == .subsequence)
        #expect(tight.score > loose.score)
    }
    @Test func shorterCandidateScoresHigherWithinTier() {
        #expect(FuzzyMatcher.match("term", in: "Terminal")!.score > FuzzyMatcher.match("term", in: "Terminal Helper Utility")!.score)
    }
    @Test func scoreNeverNegative() {
        let long = String(repeating: "x ", count: 400) + "a"
        #expect(FuzzyMatcher.match("a", in: long)!.score >= 0)
    }
}
