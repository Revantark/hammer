import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageThumbnailer {
    /// Decodes a downscaled image directly (never a full-resolution decode). Never upscales.
    public static func thumbnail(data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        var limit = maxPixelSize
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            limit = min(limit, max(w, h))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Encodes a preview: JPEG (small, ~2 ms to decode at 840 px) unless any pixel is see-through, then PNG.
    public static func previewData(_ image: CGImage) -> Data? {
        isOpaque(image) ? jpegData(image) : pngData(image)
    }

    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// True when the image has no alpha channel, or every pixel's alpha is 255 (e.g. screenshots saved with alpha).
    static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let width = image.width, height = image.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = ctx.data else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in stride(from: 3, to: width * height * 4, by: 4) where bytes[i] != 255 { return false }
        return true
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
