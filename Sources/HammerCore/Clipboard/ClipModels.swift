import Foundation

/// Pasteboard type identifiers (UTIs) Hammer understands.
public enum PasteboardType {
    public static let plainText = "public.utf8-plain-text"
    public static let rtf = "public.rtf"
    public static let html = "public.html"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let jpeg = "public.jpeg"
    public static let heic = "public.heic"
    public static let url = "public.url"
    public static let fileURL = "public.file-url"

    public static let imageTypes = [png, tiff, jpeg, heic]
    public static let textTypes = [plainText, rtf, html]
    public static let keptTypes: Set<String> = Set(imageTypes + textTypes + [url])
}

public struct Representation: Codable, Equatable, Sendable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct PasteboardSnapshot: Equatable, Sendable {
    public let representations: [Representation]
    public let sourceApp: String?

    public init(representations: [Representation], sourceApp: String?) {
        self.representations = representations
        self.sourceApp = sourceApp
    }
}

public enum ClipKind: String, Codable, Sendable {
    case text, image
}

public struct ClipEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ClipKind
    public var copiedAt: Date
    public let sourceApp: String?
    /// SHA-256 hex of the primary payload, used for dedupe.
    public let contentHash: String
    /// Text: first 2,000 characters of the plain text. Image: nil.
    public let snippet: String?
    public let charCount: Int?
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public init(id: UUID, kind: ClipKind, copiedAt: Date, sourceApp: String?, contentHash: String,
                snippet: String?, charCount: Int?, pixelWidth: Int?, pixelHeight: Int?) {
        self.id = id
        self.kind = kind
        self.copiedAt = copiedAt
        self.sourceApp = sourceApp
        self.contentHash = contentHash
        self.snippet = snippet
        self.charCount = charCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct ClipCandidate: Equatable, Sendable {
    public let entry: ClipEntry
    public let representations: [Representation]
}
