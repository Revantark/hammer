import AppKit
import HammerCore

/// Right-hand preview in clipboard mode: big image or full text, details underneath.
@MainActor public final class ClipboardPreviewView: NSView {
    public static let textPreviewLimit = 20_000
    public static let imagePixelSize = ClipboardController.previewPixels

    private let imageView = NSImageView()
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private let metaDivider = NSView()
    private var metaRows: [(NSTextField, NSTextField)] = []

    public private(set) var displayedText: String?
    public private(set) var displayedImage: CGImage?
    public private(set) var metadataLines: [(label: String, value: String)] = []

    public override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textColor = Theme.primaryText
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textScroll.documentView = textView
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.scrollerStyle = .overlay

        metaDivider.wantsLayer = true
        metaDivider.layer?.backgroundColor = Theme.divider.cgColor

        [imageView, textScroll, metaDivider].forEach(addSubview)
        clear()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func clear() {
        displayedText = nil
        displayedImage = nil
        metadataLines = []
        imageView.image = nil
        textView.string = ""
        imageView.isHidden = true
        textScroll.isHidden = true
        metaDivider.isHidden = true
        setMetaRows([])
    }

    public func show(entry: ClipEntry, payload: [Representation]?, image: CGImage?, now: Date) {
        clear()
        metaDivider.isHidden = false
        let source = entry.sourceApp ?? "Unknown"
        let copied = Self.relative(entry.copiedAt, now: now)
        switch entry.kind {
        case .image:
            setImage(image)
            imageView.isHidden = false
            let dims = (entry.pixelWidth.map { w in entry.pixelHeight.map { "\(w) × \($0)" } } ?? nil) ?? "Unknown"
            metadataLines = [("Source", source), ("Dimensions", dims), ("Copied", copied)]
        case .text:
            let full = payload?.first { $0.type == PasteboardType.plainText }.flatMap { String(data: $0.data, encoding: .utf8) }
            let text = String((full ?? entry.snippet ?? "").prefix(Self.textPreviewLimit))
            displayedText = text
            let code = Self.looksLikeCode(String(text.prefix(2_000)))
            textView.font = code ? .monospacedSystemFont(ofSize: 12.5, weight: .regular) : Theme.font(13)
            textView.string = text
            textView.textColor = Theme.primaryText
            textScroll.isHidden = false
            let count = NumberFormatter.localizedString(from: NSNumber(value: entry.charCount ?? text.count), number: .decimal)
            metadataLines = [("Source", source), ("Characters", count), ("Copied", copied)]
        }
        setMetaRows(metadataLines)
        needsLayout = true
    }

    /// Sets (or clears) the preview image; used when the async decode finishes.
    public func setImage(_ image: CGImage?) {
        displayedImage = image
        imageView.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width / 2, height: $0.height / 2)) }
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let metaHeight: CGFloat = metaRows.isEmpty ? 0 : CGFloat(metaRows.count) * 20 + 14
        var y: CGFloat = 8
        for (label, value) in metaRows.reversed() {
            label.frame = NSRect(x: 14, y: y, width: 100, height: 17)
            value.frame = NSRect(x: 114, y: y, width: bounds.width - 128, height: 17)
            y += 20
        }
        metaDivider.frame = NSRect(x: 0, y: metaHeight, width: bounds.width, height: 1)
        let content = NSRect(x: 14, y: metaHeight + 12, width: bounds.width - 28, height: bounds.height - metaHeight - 24)
        textScroll.frame = content
        if let image = imageView.image {
            let scale = min(1, content.width / image.size.width, content.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = NSRect(x: content.midX - size.width / 2, y: content.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    private func setMetaRows(_ lines: [(label: String, value: String)]) {
        metaRows.forEach { $0.0.removeFromSuperview(); $0.1.removeFromSuperview() }
        metaRows = lines.map { line in
            let label = makeLabel(Theme.font(12), Theme.secondaryText).withText(line.label)
            let value = makeLabel(Theme.font(12), Theme.primaryText).withText(line.value)
            value.alignment = .right
            addSubview(label)
            addSubview(value)
            return (label, value)
        }
    }

    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Monospace when the text has code punctuation or ≥2 indented lines.
    static func looksLikeCode(_ text: String) -> Bool {
        if text.contains("{") || text.contains(";") { return true }
        let indented = text.split(separator: "\n").filter { $0.first == " " || $0.first == "\t" }.count
        return indented >= 2
    }
}
