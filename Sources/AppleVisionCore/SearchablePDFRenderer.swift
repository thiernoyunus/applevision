import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import PDFKit

public enum SearchablePDFRenderer {
    private static let ciContext = CIContext(options: nil)

    public static func render(results: [OCRResult]) throws -> Data {
        let mutableData = NSMutableData()
        var initialMediaBox = results.first.flatMap { firstResult -> CGRect? in
            var documentCache: [String: PDFDocument] = [:]
            var pdfCanvasBoundsCache: [String: CGRect] = [:]
            return try? loadSourcePage(
                for: firstResult,
                documentCache: &documentCache,
                pdfCanvasBoundsCache: &pdfCanvasBoundsCache
            ).bounds
        } ?? CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &initialMediaBox, nil)
        else {
            throw AppleVisionError.writeFailed("Unable to create searchable PDF data.")
        }

        var documentCache: [String: PDFDocument] = [:]
        var pdfCanvasBoundsCache: [String: CGRect] = [:]

        for result in results {
            let sourcePage = try loadSourcePage(
                for: result,
                documentCache: &documentCache,
                pdfCanvasBoundsCache: &pdfCanvasBoundsCache
            )
            renderPage(result: result, sourcePage: sourcePage, in: context)
        }

        context.closePDF()
        return mutableData as Data
    }

    private static func loadSourcePage(
        for result: OCRResult,
        documentCache: inout [String: PDFDocument],
        pdfCanvasBoundsCache: inout [String: CGRect]
    ) throws -> SearchableSourcePage {
        let sourceURL = URL(fileURLWithPath: result.sourcePath)

        if sourceURL.pathExtension.lowercased() == "pdf" {
            guard let pageNumber = result.pageNumber else {
                throw AppleVisionError.unableToRenderPDFPage(result.sourcePath, 0)
            }

            let document: PDFDocument
            if let cachedDocument = documentCache[result.sourcePath] {
                document = cachedDocument
            } else {
                guard let loadedDocument = PDFDocument(url: sourceURL) else {
                    throw AppleVisionError.unableToLoadPDF(result.sourcePath)
                }
                documentCache[result.sourcePath] = loadedDocument
                document = loadedDocument
            }

            guard let page = document.page(at: pageNumber - 1),
                  let backgroundImage = OCRService.renderPDFPage(page)
            else {
                throw AppleVisionError.unableToRenderPDFPage(result.sourcePath, pageNumber)
            }

            let pageBounds = CGRect(
                x: 0,
                y: 0,
                width: OCRService.normalizedPDFPageBounds(for: page).width,
                height: OCRService.normalizedPDFPageBounds(for: page).height
            )
            let canvasBounds: CGRect
            if let cachedBounds = pdfCanvasBoundsCache[result.sourcePath] {
                canvasBounds = cachedBounds
            } else {
                let computedBounds = standardizedPDFCanvasBounds(for: document)
                pdfCanvasBoundsCache[result.sourcePath] = computedBounds
                canvasBounds = computedBounds
            }
            let contentRect = aspectFitRect(for: pageBounds.size, in: canvasBounds)

            return SearchableSourcePage(
                bounds: canvasBounds,
                contentRect: contentRect,
                backgroundImage: backgroundImage,
                textReferenceRect: contentRect
            )
        }

        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let backgroundImage = loadOrientedImage(from: imageSource)
        else {
            throw AppleVisionError.unableToLoadImage(result.sourcePath)
        }

        return SearchableSourcePage(
            bounds: CGRect(x: 0, y: 0, width: backgroundImage.width, height: backgroundImage.height),
            contentRect: CGRect(x: 0, y: 0, width: backgroundImage.width, height: backgroundImage.height),
            backgroundImage: backgroundImage,
            textReferenceRect: CGRect(x: 0, y: 0, width: backgroundImage.width, height: backgroundImage.height)
        )
    }

    private static func loadOrientedImage(from source: CGImageSource) -> CGImage? {
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
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

    private static func drawSearchableText(
        for result: OCRResult,
        textReferenceRect: CGRect,
        in context: CGContext
    ) {
        let lines = result.structuredLines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var drewStructuredText = false

        for line in lines {
            let wordRects = line.words.compactMap { word -> (String, CGRect)? in
                let trimmed = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }

                return (trimmed, rect(for: word.boundingBox, referenceRect: textReferenceRect))
            }
            .sorted { lhs, rhs in
                lhs.1.minX < rhs.1.minX
            }

            if !wordRects.isEmpty {
                for (text, rect) in wordRects {
                    drawInvisibleLine(text, in: rect, context: context)
                }
                drewStructuredText = true
                continue
            }

            if let boundingBox = line.boundingBox {
                let rect = rect(for: boundingBox, referenceRect: textReferenceRect)
                drawInvisibleLine(line.text, in: rect, context: context)
                drewStructuredText = true
            }
        }

        if drewStructuredText {
            return
        }

        let pageText = result.structuredText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageText.isEmpty else {
            return
        }

        let insetX = max(24, textReferenceRect.width * 0.06)
        let insetY = max(24, textReferenceRect.height * 0.06)
        let textRect = textReferenceRect.insetBy(dx: insetX, dy: insetY)
        let approximateLineCount = max(lines.count, pageText.split(whereSeparator: \.isNewline).count)
        let fontSize = max(10, min(18, textRect.height / CGFloat(max(approximateLineCount, 1) + 6)))
        drawInvisibleTextBlock(pageText, in: textRect, fontSize: fontSize, context: context)
    }

    private static func rect(for boundingBox: OCRBoundingBox, referenceRect: CGRect) -> CGRect {
        CGRect(
            x: referenceRect.minX + boundingBox.minX * referenceRect.width,
            y: referenceRect.minY + boundingBox.minY * referenceRect.height,
            width: boundingBox.width * referenceRect.width,
            height: boundingBox.height * referenceRect.height
        )
        .integral
    }

    private static func standardizedPDFCanvasBounds(for document: PDFDocument) -> CGRect {
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0

        for pageIndex in 0 ..< document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let bounds = OCRService.normalizedPDFPageBounds(for: page)
            maxWidth = max(maxWidth, bounds.width)
            maxHeight = max(maxHeight, bounds.height)
        }

        if maxWidth <= 0 || maxHeight <= 0 {
            return CGRect(x: 0, y: 0, width: 612, height: 792)
        }

        return CGRect(x: 0, y: 0, width: maxWidth, height: maxHeight)
    }

    private static func aspectFitRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let widthScale = bounds.width / size.width
        let heightScale = bounds.height / size.height
        let scale = min(widthScale, heightScale)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)

        return CGRect(
            x: bounds.minX + ((bounds.width - fittedSize.width) / 2),
            y: bounds.minY + ((bounds.height - fittedSize.height) / 2),
            width: fittedSize.width,
            height: fittedSize.height
        ).integral
    }

    private static func drawInvisibleLine(_ text: String, in rect: CGRect, context: CGContext) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        let fontSize = max(8, rect.height * 0.82)
        let textStyle = invisibleTextStyle(for: text, fontSize: fontSize)
        let attributedText = NSAttributedString(string: text, attributes: textStyle.attributes)
        let line = CTLineCreateWithAttributedString(attributedText as CFAttributedString)
        let lineBounds = CTLineGetBoundsWithOptions(line, [])
        let baseline = rect.minY + max(1, min(rect.height * 0.18, CTFontGetDescent(textStyle.font) + 1))
        let widthScale = min(1, rect.width / max(lineBounds.width, 1))
        let availableWidth = Double(rect.width / max(widthScale, 0.0001))
        let flush: CGFloat = textStyle.isRightToLeft ? 1.0 : 0.0
        let offset = CGFloat(CTLineGetPenOffsetForFlush(line, Double(flush), availableWidth))

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity
        context.translateBy(x: rect.minX + (offset * widthScale), y: baseline)
        context.scaleBy(x: widthScale, y: 1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawInvisibleTextBlock(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        context: CGContext
    ) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        let textStyle = invisibleTextStyle(for: text, fontSize: fontSize)
        let attributedText = NSAttributedString(string: text, attributes: textStyle.attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func invisibleTextStyle(for text: String, fontSize: CGFloat) -> InvisibleTextStyle {
        let isRightToLeft = containsRightToLeftScript(text)
        let languageCode = preferredLanguageCode(for: text, isRightToLeft: isRightToLeft)
        let font = preferredFont(for: text, languageCode: languageCode, fontSize: fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = isRightToLeft ? .right : .left
        paragraphStyle.baseWritingDirection = isRightToLeft ? .rightToLeft : .leftToRight
        paragraphStyle.lineBreakMode = .byClipping

        let writingDirection = [
            NSNumber(
                value: (isRightToLeft ? NSWritingDirection.rightToLeft : NSWritingDirection.leftToRight).rawValue |
                    NSWritingDirectionFormatType.embedding.rawValue
            )
        ]

        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .writingDirection: writingDirection,
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]

        if let languageCode {
            attributes[NSAttributedString.Key(rawValue: kCTLanguageAttributeName as String)] = languageCode
        }

        return InvisibleTextStyle(font: font, attributes: attributes, isRightToLeft: isRightToLeft)
    }

    private static func preferredFont(for text: String, languageCode: String?, fontSize: CGFloat) -> CTFont {
        if languageCode == "ar", let arabicFont = preferredArabicFont(fontSize: fontSize) {
            return arabicFont
        }

        let baseFont = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ??
            CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)

        guard let languageCode else {
            return baseFont
        }

        return CTFontCreateForStringWithLanguage(
            baseFont,
            text as CFString,
            CFRange(location: 0, length: text.utf16.count),
            languageCode as CFString
        )
    }

    private static func preferredArabicFont(fontSize: CGFloat) -> CTFont? {
        let candidates = [
            "DecoTypeNaskh",
            "AlBayan",
            "DiwanKufi",
            "KufiStandardGK",
            "GeezaPro",
            "ArialUnicodeMS",
        ]

        for name in candidates {
            let font = CTFontCreateWithName(name as CFString, fontSize, nil)
            let postScriptName = CTFontCopyPostScriptName(font) as String
            if postScriptName.caseInsensitiveCompare(name) == .orderedSame {
                return font
            }
        }

        return nil
    }

    private static func preferredLanguageCode(for text: String, isRightToLeft: Bool) -> String? {
        if containsArabicScript(text) {
            return "ar"
        }

        if containsHebrewScript(text) {
            return "he"
        }

        return isRightToLeft ? "ar" : nil
    }

    private static func containsRightToLeftScript(_ text: String) -> Bool {
        containsArabicScript(text) || containsHebrewScript(text)
    }

    private static func containsArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0600 ... 0x06FF,
                 0x0750 ... 0x077F,
                 0x0870 ... 0x089F,
                 0x08A0 ... 0x08FF,
                 0xFB50 ... 0xFDFF,
                 0xFE70 ... 0xFEFF,
                 0x1EE00 ... 0x1EEFF:
                return true
            default:
                return false
            }
        }
    }

    private static func containsHebrewScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0590 ... 0x05FF,
                 0xFB1D ... 0xFB4F:
                return true
            default:
                return false
            }
        }
    }

    private static func renderPage(result: OCRResult, sourcePage: SearchableSourcePage, in context: CGContext) {
        var mediaBox = sourcePage.bounds
        let pageInfo: [CFString: Any] = [
            kCGPDFContextMediaBox: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size),
        ]
        context.beginPDFPage(pageInfo as CFDictionary)
        context.draw(sourcePage.backgroundImage, in: sourcePage.contentRect)
        drawSearchableText(for: result, textReferenceRect: sourcePage.textReferenceRect, in: context)
        context.endPDFPage()
    }
}

private struct SearchableSourcePage {
    let bounds: CGRect
    let contentRect: CGRect
    let backgroundImage: CGImage
    let textReferenceRect: CGRect
}

private struct InvisibleTextStyle {
    let font: CTFont
    let attributes: [NSAttributedString.Key: Any]
    let isRightToLeft: Bool
}
