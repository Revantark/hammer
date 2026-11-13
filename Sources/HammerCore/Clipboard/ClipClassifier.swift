import CryptoKit
import Foundation
import ImageIO

public enum ClipClassifier {
    public static let snippetLimit = 2_000

    /// Turns a pasteboard snapshot into a history candidate, or nil if it shouldn't be recorded.
    /// Everything is recorded (including concealed/transient copies) except Finder file copies.
    public static func classify(_ snapshot: PasteboardSnapshot, id: UUID, at date: Date) -> ClipCandidate? {
        let reps = snapshot.representations
        if reps.contains(where: { $0.type == PasteboardType.fileURL }) { return nil }

        let kept = reps.filter { PasteboardType.keptTypes.contains($0.type) }
        let plain = reps.first { $0.type == PasteboardType.plainText }.flatMap { String(data: $0.data, encoding: .utf8) }
        let image = reps.first { PasteboardType.imageTypes.contains($0.type) }

        if let image, plain == nil || plain!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSingleURL(plain!) {
            let size = pixelSize(of: image.data)
            let entry = ClipEntry(id: id, kind: .image, copiedAt: date, sourceApp: snapshot.sourceApp,
                                  contentHash: sha256(image.data), snippet: nil, charCount: nil,
                                  pixelWidth: size?.width, pixelHeight: size?.height)
            return ClipCandidate(entry: entry, representations: kept)
        }

        if let plain, !plain.isEmpty {
            let entry = ClipEntry(id: id, kind: .text, copiedAt: date, sourceApp: snapshot.sourceApp,
                                  contentHash: sha256(Data(plain.utf8)), snippet: String(plain.prefix(snippetLimit)),
                                  charCount: plain.count, pixelWidth: nil, pixelHeight: nil)
            return ClipCandidate(entry: entry, representations: kept)
        }
        return nil
    }

    static func isSingleURL(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isNewline) else { return false }
        return ["http://", "https://", "file://"].contains { t.lowercased().hasPrefix($0) }
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
