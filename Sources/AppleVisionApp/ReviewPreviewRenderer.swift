import AppleVisionCore
import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit

enum ReviewPreviewRenderer {
    private static let ciContext = CIContext(options: nil)
    private static let sourceImageCache: NSCache<NSString, CachedSourceImage> = {
        let cache = NSCache<NSString, CachedSourceImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private static let sourceImageLock = NSLock()

    static func image(for issue: OCRReviewIssue) -> NSImage? {
        guard let croppedImage = croppedCGImage(for: issue) else {
            return nil
        }

        let size = NSSize(width: croppedImage.width, height: croppedImage.height)
        return NSImage(cgImage: croppedImage, size: size)
    }

    static func image(for line: ReviewedLine) -> NSImage? {
        guard let croppedImage = croppedCGImage(
            sourcePath: line.sourcePath,
            pageNumber: line.pageNumber,
            boundingBox: line.boundingBox
        ) else {
            return nil
        }

        let size = NSSize(width: croppedImage.width, height: croppedImage.height)
        return NSImage(cgImage: croppedImage, size: size)
    }

    static func pageImage(sourcePath: String, pageNumber: Int?) -> NSImage? {
        guard let cgImage = sourceCGImage(
            sourceURL: URL(fileURLWithPath: sourcePath),
            pageNumber: pageNumber
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func clearSourceImageCache() {
        sourceImageCache.removeAllObjects()
    }

    static func croppedCGImage(for issue: OCRReviewIssue) -> CGImage? {
        croppedCGImage(
            sourcePath: issue.sourcePath,
            pageNumber: issue.pageNumber,
            boundingBox: issue.boundingBox
        )
    }

    static func croppedCGImage(sourcePath: String, pageNumber: Int?, boundingBox: OCRBoundingBox?) -> CGImage? {
        guard let boundingBox else {
            return nil
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let cgImage = sourceCGImage(sourceURL: sourceURL, pageNumber: pageNumber)

        guard let cgImage,
              let croppedImage = crop(cgImage: cgImage, to: boundingBox)
        else {
            return nil
        }

        return croppedImage
    }

    private static func sourceCGImage(sourceURL: URL, pageNumber: Int?) -> CGImage? {
        let cacheKey = "\(sourceURL.path)#\(pageNumber ?? 0)" as NSString
        sourceImageLock.lock()
        defer { sourceImageLock.unlock() }

        if let cachedImage = sourceImageCache.object(forKey: cacheKey) {
            return cachedImage.cgImage
        }

        // ponytail: global preview decode lock; use per-source locks only if review decoding contention becomes measurable.
        let cgImage: CGImage?
        if sourceURL.pathExtension.lowercased() == "pdf" {
            cgImage = renderPDFPage(from: sourceURL, pageNumber: pageNumber)
        } else {
            cgImage = loadOrientedImage(from: sourceURL)
        }

        guard let cgImage else {
            return nil
        }

        sourceImageCache.setObject(
            CachedSourceImage(cgImage),
            forKey: cacheKey,
            cost: cgImage.bytesPerRow * cgImage.height
        )
        return cgImage
    }

    private static func loadOrientedImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let orientation = imageOrientation(for: source)
        guard orientation != .up else {
            return cgImage
        }

        let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
        let rect = ciImage.extent.integral
        let normalizedImage = ciImage.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let normalizedRect = CGRect(origin: .zero, size: rect.size)
        return ciContext.createCGImage(normalizedImage, from: normalizedRect)
    }

    private static func imageOrientation(for source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation]
        else {
            return .up
        }

        if let value = rawOrientation as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: value) {
            return orientation
        }

        if let value = rawOrientation as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) {
            return orientation
        }

        return .up
    }

    private static func renderPDFPage(from url: URL, pageNumber: Int?) -> CGImage? {
        guard let pageNumber,
              let document = PDFDocument(url: url),
              let page = document.page(at: pageNumber - 1)
        else {
            return nil
        }

        return OCRService.renderPDFPage(page)
    }

    private static func crop(cgImage: CGImage, to boundingBox: OCRBoundingBox) -> CGImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let rect = boundingBox.rect(in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        .insetBy(dx: -24, dy: -16)
        .standardized
        .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        .integral

        guard rect.width > 1, rect.height > 1 else {
            return nil
        }

        return cgImage.cropping(to: rect)
    }
}

private final class CachedSourceImage {
    let cgImage: CGImage

    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }
}
