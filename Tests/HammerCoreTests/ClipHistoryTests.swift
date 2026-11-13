import Foundation
import Testing
@testable import HammerCore

func textEntry(_ text: String, at date: Date = Date(timeIntervalSince1970: 1_794_571_200), source: String? = "Notes", id: UUID = UUID()) -> ClipEntry {
    ClipClassifier.classify(textSnapshot(text, source: source), id: id, at: date)!.entry
}

func imageEntry(at date: Date = Date(timeIntervalSince1970: 1_794_571_200), source: String? = "Screenshot") -> ClipEntry {
    ClipClassifier.classify(PasteboardSnapshot(representations: [Representation(type: PasteboardType.png, data: makePNG(width: 4, height: 4))], sourceApp: source),
                            id: UUID(), at: date)!.entry
}

@Suite struct ClipHistoryTests {
    @Test func newestFirst() {
        var h = ClipHistory()
        _ = h.insert(textEntry("a")); _ = h.insert(textEntry("b"))
        #expect(h.entries.map(\.snippet) == ["b", "a"])
    }

    @Test func capacityEvictsOldest() {
        var h = ClipHistory()
        let first = textEntry("0")
        _ = h.insert(first)
        for i in 1..<25 { _ = h.insert(textEntry("\(i)")) }
        #expect(h.entries.count == 25)
        #expect(h.insert(textEntry("25")) == .added(evicted: [first.id]))
        #expect(h.entries.count == 25)
        #expect(h.entries.first?.snippet == "25")
    }

    @Test func duplicateMovesToTop() {
        var h = ClipHistory()
        let a = textEntry("A"), b = textEntry("B")
        _ = h.insert(a); _ = h.insert(b)
        let again = textEntry("A", at: a.copiedAt.addingTimeInterval(60))
        #expect(h.insert(again) == .movedToTop(existingID: a.id))
        #expect(h.entries.map(\.id) == [a.id, b.id])
        #expect(h.entries[0].copiedAt == again.copiedAt)
    }

    @Test func moveToTop() {
        var h = ClipHistory()
        let a = textEntry("A"); _ = h.insert(a); _ = h.insert(textEntry("B"))
        let later = a.copiedAt.addingTimeInterval(5)
        h.moveToTop(id: a.id, at: later)
        #expect(h.entries[0].id == a.id && h.entries[0].copiedAt == later)
    }

    @Test func moveToTopUnknownIDNoChange() {
        var h = ClipHistory(); _ = h.insert(textEntry("A"))
        let before = h
        h.moveToTop(id: UUID(), at: Date())
        #expect(h == before)
    }

    @Test func removeAllReturnsIDs() {
        var h = ClipHistory()
        let a = textEntry("A"), b = textEntry("B")
        _ = h.insert(a); _ = h.insert(b)
        #expect(Set(h.removeAll()) == [a.id, b.id])
        #expect(h.entries.isEmpty)
    }

    @Test func searchCaseAndDiacriticInsensitive() {
        var h = ClipHistory(); _ = h.insert(textEntry("café au lait")); _ = h.insert(textEntry("tea"))
        #expect(h.search("CAFE").map(\.snippet) == ["café au lait"])
    }

    @Test func searchMatchesImageWord() {
        var h = ClipHistory(); _ = h.insert(imageEntry()); _ = h.insert(textEntry("tea"))
        #expect(h.search("imag").map(\.kind) == [.image])
    }

    @Test func searchMatchesSourceApp() {
        var h = ClipHistory(); _ = h.insert(textEntry("x", source: "Xcode")); _ = h.insert(textEntry("y", source: "Notes"))
        #expect(h.search("xco").map(\.snippet) == ["x"])
    }

    @Test func emptySearchReturnsAll() {
        var h = ClipHistory(); _ = h.insert(textEntry("a")); _ = h.insert(textEntry("b"))
        #expect(h.search("  ").count == 2)
    }

    @Test func sectionsTodayYesterdayAndDate() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_794_571_200)  // 2026-11-13 12:00 UTC
        let entries = [textEntry("a", at: now.addingTimeInterval(-3 * 3600)),
                       textEntry("b", at: now.addingTimeInterval(-16 * 3600)),
                       textEntry("c", at: now.addingTimeInterval(-3 * day))]
        let sections = ClipHistory.sections(entries, now: now, calendar: cal, locale: Locale(identifier: "en_US_POSIX"))
        #expect(sections.map(\.title) == ["Today", "Yesterday", "Nov 10"])
        #expect(sections.map { $0.entries.count } == [1, 1, 1])
    }

    @Test func codableRoundTrip() throws {
        var h = ClipHistory(); _ = h.insert(textEntry("a")); _ = h.insert(imageEntry())
        let data = try JSONEncoder().encode(h)
        #expect(try JSONDecoder().decode(ClipHistory.self, from: data) == h)
    }
}
