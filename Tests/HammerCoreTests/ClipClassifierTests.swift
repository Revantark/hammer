import Foundation
import Testing
@testable import HammerCore

@Suite struct ClipClassifierTests {
    let now = ManualClock().now()
    func classify(_ s: PasteboardSnapshot) -> ClipCandidate? { ClipClassifier.classify(s, id: UUID(), at: now) }

    @Test func plainTextIsText() throws {
        let c = try #require(classify(textSnapshot("hello")))
        #expect(c.entry.kind == .text)
        #expect(c.entry.snippet == "hello")
        #expect(c.entry.charCount == 5)
        #expect(c.entry.sourceApp == "Notes")
        #expect(c.entry.copiedAt == now)
    }

    @Test func fileURLIsSkipped() {
        let s = PasteboardSnapshot(representations: [rep(PasteboardType.fileURL, "file:///tmp/a.txt"),
                                                     Representation(type: PasteboardType.tiff, data: makePNG(width: 4, height: 4))], sourceApp: "Finder")
        #expect(classify(s) == nil)
    }

    @Test func pngIsImageWithDimensions() throws {
        let s = PasteboardSnapshot(representations: [Representation(type: PasteboardType.png, data: makePNG(width: 40, height: 20))], sourceApp: nil)
        let c = try #require(classify(s))
        #expect(c.entry.kind == .image)
        #expect(c.entry.pixelWidth == 40 && c.entry.pixelHeight == 20)
        #expect(c.entry.snippet == nil && c.entry.charCount == nil)
    }

    @Test func imageWithURLTextIsImage() throws {
        let s = PasteboardSnapshot(representations: [Representation(type: PasteboardType.tiff, data: makePNG(width: 4, height: 4)),
                                                     rep(PasteboardType.plainText, "https://example.com/a.png")], sourceApp: "Safari")
        #expect(try #require(classify(s)).entry.kind == .image)
    }

    @Test func richTextWithPreviewImageIsText() throws {
        let s = PasteboardSnapshot(representations: [rep(PasteboardType.plainText, "Hello world"), rep(PasteboardType.rtf, "{\\rtf1 Hello world}"),
                                                     Representation(type: PasteboardType.png, data: makePNG(width: 4, height: 4))], sourceApp: "Pages")
        let c = try #require(classify(s))
        #expect(c.entry.kind == .text)
        #expect(c.representations.map(\.type) == [PasteboardType.plainText, PasteboardType.rtf, PasteboardType.png])
    }

    @Test func unrecognizedTypesAreDroppedFromRepresentations() throws {
        let s = PasteboardSnapshot(representations: [rep(PasteboardType.plainText, "x"), rep("com.apple.private.junk", "y")], sourceApp: nil)
        #expect(try #require(classify(s)).representations.map(\.type) == [PasteboardType.plainText])
    }

    @Test func concealedIsStillRecorded() throws {
        let s = PasteboardSnapshot(representations: [rep(PasteboardType.plainText, "hunter2"), rep("org.nspasteboard.ConcealedType", "")], sourceApp: "1Password")
        #expect(try #require(classify(s)).entry.kind == .text)
    }

    @Test func unknownTypesOnlyIsNil() {
        #expect(classify(PasteboardSnapshot(representations: [rep("com.example.custom", "x")], sourceApp: nil)) == nil)
    }

    @Test func emptyTextIsNil() { #expect(classify(textSnapshot("")) == nil) }

    @Test func hugeTextIsSnippeted() throws {
        let c = try #require(classify(textSnapshot(String(repeating: "a", count: 5_000_000))))
        #expect(c.entry.snippet?.count == 2_000)
        #expect(c.entry.charCount == 5_000_000)
    }

    @Test func sameContentSameHash() throws {
        let a = try #require(classify(textSnapshot("same", source: "A")))
        let b = try #require(classify(textSnapshot("same", source: "B")))
        #expect(a.entry.contentHash == b.entry.contentHash)
        #expect(a.entry.id != b.entry.id)
    }

    @Test func differentContentDifferentHash() throws {
        #expect(try #require(classify(textSnapshot("a"))).entry.contentHash != (try #require(classify(textSnapshot("b")))).entry.contentHash)
    }
}
