import AppKit
import Testing
import HammerCore
@testable import HammerMac

func pngData(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

@MainActor @Suite struct ClipboardUITests {
    func harness(_ texts: [String] = []) -> PanelHarness {
        let h = PanelHarness()
        h.thumbnails = ClipThumbnails(clipboard: h.clipboard)
        h.start()
        for t in texts { h.pasteboard.copyText(t); h.clipboard.poll() }
        return h
    }

    func copyImage(_ h: PanelHarness, width: Int = 40, height: Int = 20) {
        h.pasteboard.copy(PasteboardSnapshot(representations: [Representation(type: PasteboardType.png, data: pngData(width: width, height: height))],
                                             sourceApp: "Screenshot"))
        h.clipboard.poll()
    }

    @Test func clipboardModeListsEntriesWithSections() {
        let h = harness()
        let now = h.clock.current
        h.clock.current = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        h.pasteboard.copyText("old"); h.clipboard.poll()
        h.clock.current = now
        h.pasteboard.copyText("a"); h.clipboard.poll()
        h.pasteboard.copyText("b"); h.clipboard.poll()
        h.model.hotkey(.clipboard)
        #expect(h.controller.displayedHeaders == ["Today", "Yesterday"])
        #expect(h.controller.displayedRowCount == 3)
    }

    @Test func footerShowsCount() {
        let h = harness(["a", "b", "c"]); h.model.hotkey(.clipboard)
        #expect(h.controller.footerLeftText == "Clipboard · 3 items")
        #expect(h.controller.footerRightText.contains("Paste ↵"))
        #expect(h.controller.footerRightText.contains("Launcher ⌘Space"))
    }

    @Test func footerSingularItem() {
        let h = harness(["a"]); h.model.hotkey(.clipboard)
        #expect(h.controller.footerLeftText == "Clipboard · 1 item")
    }

    @Test func clipboardPanelIsWideAndFixedHeight() {
        let h = harness(["a"]); h.model.hotkey(.clipboard)
        #expect(h.controller.preferredPanelSize.width == Theme.clipboardWidth)
        #expect(h.controller.preferredPanelSize.height == Theme.searchHeight + 1 + Theme.clipboardBodyHeight + Theme.footerHeight)
    }

    @Test func searchFiltersClipboard() {
        let h = harness(["apple pie", "banana", "cherry"]); h.model.hotkey(.clipboard)
        h.type("ban")
        #expect(h.controller.displayedRowCount == 1)
    }

    @Test func enterPastesSelected() {
        let h = harness(["first", "second"]); h.model.hotkey(.clipboard)
        h.controller.handleKey(.down)
        h.controller.handleKey(.enter)
        #expect(h.sender.pasteCount == 1)
        #expect(h.pasteboard.written.last == [Representation(type: PasteboardType.plainText, data: Data("first".utf8))])
        #expect(!h.model.isVisible)
        #expect(h.clipboard.history.entries.first?.snippet == "first")
    }

    @Test func imagePreviewMetadata() async {
        let h = harness(); copyImage(h); h.model.hotkey(.clipboard)
        await h.controller.previewTask?.value
        let lines = h.controller.preview.metadataLines
        #expect(lines.map(\.label) == ["Source", "Dimensions", "Copied"])
        #expect(lines[0].value == "Screenshot")
        #expect(lines[1].value == "40 × 20")
        #expect(h.controller.preview.displayedImage != nil)
        #expect(h.controller.preview.displayedText == nil)
    }

    @Test func textPreviewMetadata() {
        let h = harness(["Hello world"]); h.model.hotkey(.clipboard)
        let lines = h.controller.preview.metadataLines
        #expect(lines.map(\.label) == ["Source", "Characters", "Copied"])
        #expect(lines[1].value == "11")
        #expect(lines[2].value == "Just now")
        #expect(h.controller.preview.displayedText == "Hello world")
    }

    @Test func previewCapsText() {
        let h = harness([String(repeating: "x", count: 5_000_000)]); h.model.hotkey(.clipboard)
        #expect(h.controller.preview.displayedText?.count == ClipboardPreviewView.textPreviewLimit)
    }

    @Test func stalePreviewIgnoredAfterSelectionMoves() async throws {
        let h = harness(); copyImage(h); h.pasteboard.copyText("text"); h.clipboard.poll()
        let imageID = h.clipboard.history.entries[1].id   // saved before previews existed → full decode path
        try FileManager.default.removeItem(at: h.dir.appendingPathComponent("clipboard/previews/\(imageID.uuidString).img"))
        h.model.hotkey(.clipboard)            // "text" selected
        h.controller.handleKey(.down)         // image selected → preview loading
        let task = try #require(h.controller.previewTask)
        h.controller.handleKey(.up)           // back to text before the image arrives
        await task.value
        #expect(h.controller.preview.displayedImage == nil)
        #expect(h.controller.preview.displayedText == "text")
    }

    @Test func arrowingOntoImageShowsItWithoutWaiting() {
        let h = harness(); copyImage(h, width: 2560, height: 1600); h.pasteboard.copyText("text"); h.clipboard.poll()
        h.model.hotkey(.clipboard)            // "text" selected
        h.controller.handleKey(.down)         // image: shown in this same step, no blank frame
        #expect(h.controller.previewTask == nil)
        #expect(h.controller.preview.displayedImage?.width == 840)
    }

    @Test func previewFollowsSelection() {
        let h = harness(["one", "two"]); h.model.hotkey(.clipboard)
        #expect(h.controller.preview.displayedText == "two")
        h.controller.handleKey(.down)
        #expect(h.controller.preview.displayedText == "one")
    }

    @Test func emptyHistoryShowsNoPreview() {
        let h = harness(); h.model.hotkey(.clipboard)
        #expect(h.controller.displayedRowCount == 0)
        #expect(h.controller.preview.displayedText == nil && h.controller.preview.displayedImage == nil)
    }

    @Test func newCopyWhileOpenKeepsSelection() {
        let h = harness(["a", "b"]); h.model.hotkey(.clipboard)
        h.controller.handleKey(.down)
        let selected = h.clipboard.history.entries[1].id
        h.pasteboard.copyText("c"); h.clipboard.poll()
        #expect(h.controller.displayedRowCount == 3)
        #expect(h.controller.selectedClipID == selected)
    }

    @Test func monospaceHeuristic() {
        #expect(ClipboardPreviewView.looksLikeCode("let x = 1;"))
        #expect(ClipboardPreviewView.looksLikeCode("func a() {\n  b()\n  c()\n}"))
        #expect(!ClipboardPreviewView.looksLikeCode("Meeting moved to 3pm, same link"))
    }
}

@MainActor @Suite struct ClipThumbnailsTests {
    func harnessWithImages(_ count: Int) -> PanelHarness {
        let h = PanelHarness()
        for i in 0..<count {
            h.pasteboard.copy(PasteboardSnapshot(representations: [Representation(type: PasteboardType.png, data: pngData(width: 2560 + i, height: 1600))], sourceApp: nil))
            h.clipboard.poll()
        }
        return h
    }

    @Test func previewIsDownscaledAndCached() async throws {
        let h = harnessWithImages(1)
        let thumbs = ClipThumbnails(clipboard: h.clipboard)
        let id = h.clipboard.history.entries[0].id
        let image = try #require(await thumbs.preview(for: id))
        #expect(image.width == 840 && image.height == 525)
        #expect(await thumbs.preview(for: id) === image)
    }

    @Test func previewCacheHoldsOnlyOne() async {
        let h = harnessWithImages(2)
        let thumbs = ClipThumbnails(clipboard: h.clipboard)
        _ = await thumbs.preview(for: h.clipboard.history.entries[0].id)
        _ = await thumbs.preview(for: h.clipboard.history.entries[1].id)
        #expect(thumbs.cachedPreviewCount == 1)
    }

    @Test func listThumbnailDoesNotTouchFullPayload() throws {
        let h = harnessWithImages(1)
        let id = h.clipboard.history.entries[0].id
        // Remove the full payload: the list thumbnail must still load (proves no full-image decode on open).
        try FileManager.default.removeItem(at: h.dir.appendingPathComponent("clipboard/blobs/\(id.uuidString).plist"))
        let thumb = try #require(ClipThumbnails(clipboard: h.clipboard).listThumbnail(for: id))
        #expect(max(thumb.width, thumb.height) == ClipboardController.listThumbnailPixels)
    }

    @Test func clearDropsPreviewKeepsListThumbnails() async {
        let h = harnessWithImages(1)
        let thumbs = ClipThumbnails(clipboard: h.clipboard)
        let id = h.clipboard.history.entries[0].id
        let list = thumbs.listThumbnail(for: id)
        _ = await thumbs.preview(for: id)
        thumbs.clear()
        #expect(thumbs.cachedPreviewCount == 0)
        #expect(thumbs.listThumbnail(for: id) === list)
    }

    @Test func quickPreviewUsesSavedPreviewNotFullImage() throws {
        let h = harnessWithImages(1)
        let id = h.clipboard.history.entries[0].id
        try FileManager.default.removeItem(at: h.dir.appendingPathComponent("clipboard/blobs/\(id.uuidString).plist"))
        let image = try #require(ClipThumbnails(clipboard: h.clipboard).quickPreview(for: id))
        #expect(image.width == 840 && image.height == 525)
    }

    @Test func quickPreviewNilForEntriesSavedBeforePreviews() throws {
        let h = harnessWithImages(1)
        let id = h.clipboard.history.entries[0].id
        try FileManager.default.removeItem(at: h.dir.appendingPathComponent("clipboard/previews/\(id.uuidString).img"))
        #expect(ClipThumbnails(clipboard: h.clipboard).quickPreview(for: id) == nil)
    }

    @Test func fullDecodeSavesPreviewForNextTime() async throws {
        let h = harnessWithImages(1)
        let id = h.clipboard.history.entries[0].id
        try FileManager.default.removeItem(at: h.dir.appendingPathComponent("clipboard/previews/\(id.uuidString).img"))
        _ = await ClipThumbnails(clipboard: h.clipboard).preview(for: id)
        #expect(ClipThumbnails(clipboard: h.clipboard).quickPreview(for: id)?.width == 840)
    }

    @Test func textEntryHasNoThumbnail() async {
        let h = PanelHarness()
        h.pasteboard.copyText("hi"); h.clipboard.poll()
        let thumbs = ClipThumbnails(clipboard: h.clipboard)
        #expect(thumbs.listThumbnail(for: h.clipboard.history.entries[0].id) == nil)
        #expect(await thumbs.preview(for: h.clipboard.history.entries[0].id) == nil)
    }
}
