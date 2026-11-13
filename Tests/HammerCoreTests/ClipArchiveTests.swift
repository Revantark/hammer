import Foundation
import Testing
@testable import HammerCore

private let now = Date(timeIntervalSince1970: 1_794_571_200)
private let oneDay: TimeInterval = 86_400

@Suite struct ClipArchiveTests {
    @Test func keepsOrderAndDropsOlderCopiesOfSameContent() {
        let newer = textEntry("same"), other = textEntry("other"), older = textEntry("same")
        let r = ClipArchive.retain([newer, other, older], now: now)
        #expect(r.kept.map(\.id) == [newer.id, other.id])
        #expect(r.dropped == [older.id])
    }

    @Test func dropsEntriesOlderThanFourDays() {
        let fresh = textEntry("fresh", at: now.addingTimeInterval(-oneDay))
        let edge = textEntry("edge", at: now.addingTimeInterval(-4 * oneDay + 60))
        let stale = textEntry("stale", at: now.addingTimeInterval(-4 * oneDay - 60))
        let r = ClipArchive.retain([fresh, edge, stale], now: now)
        #expect(r.kept.map(\.snippet) == ["fresh", "edge"])
        #expect(r.dropped == [stale.id])
    }

    @Test func keepsNewestThousand() {
        let entries = (0...1000).map { textEntry("e\($0)", at: now.addingTimeInterval(-Double($0))) }
        let r = ClipArchive.retain(entries, now: now)
        #expect(r.kept.count == 1000)
        #expect(r.kept.first?.id == entries[0].id)
        #expect(r.dropped == [entries[1000].id])
    }

    @Test func excludedEntriesLeaveWithoutBeingDropped() {
        let x = textEntry("x"), y = textEntry("y")
        let r = ClipArchive.retain([x, y], now: now, excluding: [y.id])
        #expect(r.kept.map(\.id) == [x.id])
        #expect(r.dropped.isEmpty)
    }
}

@Suite struct ClipSearchIndexTests {
    @Test func blankQueryReturnsAllInOrder() {
        let entries = [textEntry("a"), textEntry("b")]
        #expect(ClipSearchIndex(entries).search("  ").map(\.id) == entries.map(\.id))
    }

    @Test func matchesAcrossSnippetAppAndImageWord() {
        let text = textEntry("Crème brûlée recipe", source: "Notes")
        let fromZed = textEntry("let x = 1", source: "Zed")
        let image = imageEntry()
        let index = ClipSearchIndex([text, fromZed, image])
        #expect(index.search("BRULEE").map(\.id) == [text.id])
        #expect(index.search("zed").map(\.id) == [fromZed.id])
        #expect(index.search("imag").map(\.id) == [image.id])
        #expect(index.search("nothing here").isEmpty)
    }

    @Test func queryDoesNotMatchAcrossFields() {
        let entry = textEntry("abc", source: "Zed")
        #expect(ClipSearchIndex([entry]).search("abczed").isEmpty)
    }
}
