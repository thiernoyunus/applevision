import AppleVisionCore
import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit

enum ReviewPreviewRenderer {
    private static let ciContext = CIContext(options: nil)
    private static let pageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 512 * 1024 * 1024
        return cache
    }()
    private static let sourceImageCache: NSCache<NSString, CachedCGImage> = {
        let cache = NSCache<NSString, CachedCGImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

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
        let cacheKey = "\(sourcePath)#\(pageNumber ?? 0)" as NSString
        if let cachedImage = pageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let cgImage = sourceCGImage(
            sourceURL: URL(fileURLWithPath: sourcePath),
            pageNumber: pageNumber
        ) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        pageCache.setObject(image, forKey: cacheKey)
        return image
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
        if let cachedImage = sourceImageCache.object(forKey: cacheKey)?.image {
            return cachedImage
        }

        let image: CGImage?
        if sourceURL.pathExtension.lowercased() == "pdf" {
            image = renderPDFPage(from: sourceURL, pageNumber: pageNumber)
        } else {
            image = loadOrientedImage(from: sourceURL)
        }

        if let image {
            sourceImageCache.setObject(CachedCGImage(image), forKey: cacheKey, cost: image.memoryCost)
        }
        return image
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

        let bounds = OCRService.normalizedPDFPageBounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let scale: CGFloat = 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: OCRService.preferredPDFDisplayBox(for: page), to: context)

        return context.makeImage()
    }

    private static func crop(cgImage: CGImage, to boundingBox: OCRBoundingBox) -> CGImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let rect = CGRect(
            x: boundingBox.minX * imageWidth,
            y: (1 - boundingBox.minY - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )
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

private final class CachedCGImage {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private extension CGImage {
    var memoryCost: Int {
        bytesPerRow * height
    }
}
