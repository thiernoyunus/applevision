import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

public struct OCRService {
    private let options: OCRRequestOptions

    public init(options: OCRRequestOptions) {
        self.options = options
    }

    public func process(url: URL) throws -> [OCRResult] {
        if url.pathExtension.lowercased() == "pdf" {
            return try processPDF(at: url)
        }

        return [try processImage(at: url)]
    }

    public func process(urls: [URL]) throws -> [OCRResult] {
        try process(urls: urls, progress: nil)
    }

    public func process(urls: [URL], progress: (@Sendable (OCRProgressUpdate) -> Void)?) throws -> [OCRResult] {
        var results: [OCRResult] = []
        let totalUnitCount = try totalUnitCount(for: urls)
        var completedUnitCount = 0

        results.reserveCapacity(max(totalUnitCount, urls.count))

        for url in urls {
            try autoreleasepool {
                if url.pathExtension.lowercased() == "pdf" {
                    results.append(contentsOf: try processPDF(
                        at: url,
                        totalUnitCount: totalUnitCount,
                        completedUnitCount: &completedUnitCount,
                        progress: progress
                    ))
                } else {
                    let result = try processImage(at: url)
                    results.append(result)
                    completedUnitCount += 1
                    progress?(OCRProgressUpdate(
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        sourcePath: url.path,
                        pageNumber: nil
                    ))
                }
            }
        }

        return results
    }

    public func processStructured(urls: [URL]) async throws -> [OCRResult] {
        try await processStructured(urls: urls, progress: nil)
    }

    public func processStructured(
        urls: [URL],
        progress: (@Sendable (OCRProgressUpdate) -> Void)?
    ) async throws -> [OCRResult] {
        var results: [OCRResult] = []
        let totalUnitCount = try totalUnitCount(for: urls)
        var completedUnitCount = 0

        results.reserveCapacity(max(totalUnitCount, urls.count))

        for url in urls {
            if url.pathExtension.lowercased() == "pdf" {
                results.append(contentsOf: try await processStructuredPDF(
                    at: url,
                    totalUnitCount: totalUnitCount,
                    completedUnitCount: &completedUnitCount,
                    progress: progress
                ))
            } else {
                results.append(try await processStructuredImage(at: url))
                completedUnitCount += 1
                progress?(OCRProgressUpdate(
                    completedUnitCount: completedUnitCount,
                    totalUnitCount: totalUnitCount,
                    sourcePath: url.path,
                    pageNumber: nil
                ))
            }
        }

        return results
    }

    private func processImage(at url: URL) throws -> OCRResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AppleVisionError.unableToLoadImage(url.path)
        }

        let orientation = Self.orientation(for: source)
        let lines = try recognizeText(in: cgImage, orientation: orientation)
        return OCRResult(sourcePath: url.path, pageNumber: nil, lines: lines)
    }

    private func processStructuredImage(at url: URL) async throws -> OCRResult {
        let sourceImage = try autoreleasepool { () throws -> (image: CGImage, orientation: CGImagePropertyOrientation) in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw AppleVisionError.unableToLoadImage(url.path)
            }

            return (cgImage, Self.orientation(for: source))
        }
        let recognition = try await recognizeTextStructured(in: sourceImage.image, orientation: sourceImage.orientation)
        return OCRResult(
            sourcePath: url.path,
            pageNumber: nil,
            lines: recognition.lines,
            structure: recognition.structure
        )
    }

    private func processPDF(at url: URL) throws -> [OCRResult] {
        var completedUnitCount = 0
        return try processPDF(
            at: url,
            totalUnitCount: 0,
            completedUnitCount: &completedUnitCount,
            progress: nil
        )
    }

    private func processPDF(
        at url: URL,
        totalUnitCount: Int,
        completedUnitCount: inout Int,
        progress: (@Sendable (OCRProgressUpdate) -> Void)?
    ) throws -> [OCRResult] {
        guard let document = PDFDocument(url: url) else {
            throw AppleVisionError.unableToLoadPDF(url.path)
        }

        var pageResults: [OCRResult] = []

        for pageIndex in 0 ..< document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: pageIndex) else {
                    throw AppleVisionError.unableToRenderPDFPage(url.path, pageIndex + 1)
                }

                let result: OCRResult

                switch options.pdfTextMode {
                case .preferEmbeddedText:
                    let extractedPDFText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if !extractedPDFText.isEmpty {
                        result = OCRResult(
                            sourcePath: url.path,
                            pageNumber: pageIndex + 1,
                            lines: Self.makeTextLines(from: extractedPDFText)
                        )
                    } else if let renderedPage = Self.renderPDFPage(page) {
                        result = OCRResult(
                            sourcePath: url.path,
                            pageNumber: pageIndex + 1,
                            lines: try recognizeText(in: renderedPage, orientation: .up)
                        )
                    } else {
                        throw AppleVisionError.unableToRenderPDFPage(url.path, pageIndex + 1)
                    }
                case .ocrOnly:
                    guard let renderedPage = Self.renderPDFPage(page) else {
                        throw AppleVisionError.unableToRenderPDFPage(url.path, pageIndex + 1)
                    }
                    result = OCRResult(
                        sourcePath: url.path,
                        pageNumber: pageIndex + 1,
                        lines: try recognizeText(in: renderedPage, orientation: .up)
                    )
                }

                pageResults.append(result)
                completedUnitCount += 1

                if let progress {
                    progress(OCRProgressUpdate(
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        sourcePath: url.path,
                        pageNumber: pageIndex + 1
                    ))
                }
            }
        }

        return pageResults
    }

    private func processStructuredPDF(
        at url: URL,
        totalUnitCount: Int,
        completedUnitCount: inout Int,
        progress: (@Sendable (OCRProgressUpdate) -> Void)?
    ) async throws -> [OCRResult] {
        guard let document = PDFDocument(url: url) else {
            throw AppleVisionError.unableToLoadPDF(url.path)
        }

        var pageResults: [OCRResult] = []

        for pageIndex in 0 ..< document.pageCount {
            let work = try autoreleasepool { () throws -> StructuredPDFPageWork in
                guard let page = document.page(at: pageIndex) else {
                    throw AppleVisionError.unableToRenderPDFPage(url.path, pageIndex + 1)
                }

                if options.pdfTextMode == .preferEmbeddedText {
                    let extractedPDFText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !extractedPDFText.isEmpty {
                        return .embeddedText(Self.makeTextLines(from: extractedPDFText))
                    }
                }

                guard let renderedPage = Self.renderPDFPage(page) else {
                    throw AppleVisionError.unableToRenderPDFPage(url.path, pageIndex + 1)
                }
                return .renderedPage(renderedPage)
            }

            let result: OCRResult
            switch work {
            case let .embeddedText(lines):
                result = OCRResult(sourcePath: url.path, pageNumber: pageIndex + 1, lines: lines)
            case let .renderedPage(image):
                let recognition = try await recognizeTextStructured(in: image, orientation: .up)
                result = OCRResult(
                    sourcePath: url.path,
                    pageNumber: pageIndex + 1,
                    lines: recognition.lines,
                    structure: recognition.structure
                )
            }

            pageResults.append(result)
            completedUnitCount += 1
            progress?(OCRProgressUpdate(
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount,
                sourcePath: url.path,
                pageNumber: pageIndex + 1
            ))
        }

        return pageResults
    }

    private func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest(completionHandler: nil)
        request.recognitionLevel = options.recognitionLevel
        request.usesLanguageCorrection = options.usesLanguageCorrection

        if !options.recognitionLanguages.isEmpty {
            request.recognitionLanguages = options.recognitionLanguages
        }

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []

        var lines: [RecognizedLine] = []
        lines.reserveCapacity(observations.count)

        for observation in observations {
            var recognizedCandidates: [VNRecognizedText] = []

            for candidate in observation.topCandidates(3) {
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    continue
                }

                guard !recognizedCandidates.contains(where: {
                    $0.string.trimmingCharacters(in: .whitespacesAndNewlines) == text
                }) else {
                    continue
                }

                recognizedCandidates.append(candidate)
            }

            guard let primaryCandidate = recognizedCandidates.first else {
                continue
            }

            let candidates = recognizedCandidates.map { candidate in
                OCRCandidate(
                    text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: candidate.confidence
                )
            }

            lines.append(RecognizedLine(
                line: OCRLine(
                    text: primaryCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: primaryCandidate.confidence,
                    boundingBox: OCRBoundingBox(rect: observation.boundingBox),
                    candidates: candidates,
                    words: extractWords(from: primaryCandidate)
                ),
                boundingBox: observation.boundingBox
            ))
        }

        return lines.sorted(by: RecognizedLine.isBefore).map { $0.line }
    }

    private func recognizeTextStructured(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> StructuredRecognition {
        guard options.recognitionLevel == .accurate else {
            return StructuredRecognition(lines: try recognizeText(in: image, orientation: orientation), structure: nil)
        }

        if #available(macOS 26.0, *) {
            do {
                if let recognition = try await recognizeDocument(in: image, orientation: orientation) {
                    return recognition
                }
            } catch {
                // Keep the established text recognizer as the failure fallback.
            }
        }

        return StructuredRecognition(lines: try recognizeText(in: image, orientation: orientation), structure: nil)
    }

    @available(macOS 26.0, *)
    private func recognizeDocument(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> StructuredRecognition? {
        var request = RecognizeDocumentsRequest()
        var textOptions = request.textRecognitionOptions
        let requestedLanguages = options.recognitionLanguages.map(Locale.Language.init(identifier:))
        textOptions.recognitionLanguages = requestedLanguages.filter(request.supportedRecognitionLanguages.contains)
        textOptions.useLanguageCorrection = options.usesLanguageCorrection
        textOptions.maximumCandidateCount = 3
        request.textRecognitionOptions = textOptions

        guard let observation = try await request.perform(on: image, orientation: orientation)
            .max(by: { $0.confidence < $1.confidence })
        else {
            return nil
        }

        var lineIndicesByUUID: [UUID: Int] = [:]
        var lines: [OCRLine] = []
        for lineObservation in observation.document.text.lines {
            guard let line = makeDocumentLine(from: lineObservation) else {
                continue
            }
            lineIndicesByUUID[lineObservation.uuid] = lines.count
            lines.append(line)
        }

        guard !lines.isEmpty else {
            return nil
        }

        let tables = observation.document.tables.compactMap {
            makeTable(from: $0, lineIndicesByUUID: lineIndicesByUUID)
        }
        return StructuredRecognition(
            lines: lines,
            structure: tables.isEmpty ? nil : OCRDocumentStructure(tables: tables)
        )
    }

    @available(macOS 26.0, *)
    private func makeDocumentLine(from observation: RecognizedTextObservation) -> OCRLine? {
        let candidates = documentCandidates(from: observation)
        guard let primaryCandidate = candidates.first else {
            return nil
        }

        return OCRLine(
            text: primaryCandidate.text,
            confidence: primaryCandidate.confidence,
            boundingBox: OCRBoundingBox(rect: observation.boundingRegion.boundingBox.cgRect),
            candidates: candidates.map { OCRCandidate(text: $0.text, confidence: $0.confidence) },
            words: extractWords(from: primaryCandidate.recognizedText)
        )
    }

    @available(macOS 26.0, *)
    private func documentCandidates(from observation: RecognizedTextObservation) -> [DocumentCandidate] {
        var candidates: [DocumentCandidate] = []
        for candidate in observation.topCandidates(3) {
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  !candidates.contains(where: { $0.text == text })
            else {
                continue
            }
            candidates.append(DocumentCandidate(text: text, confidence: candidate.confidence, recognizedText: candidate))
        }
        return candidates
    }

    @available(macOS 26.0, *)
    private func makeTable(
        from table: DocumentObservation.Container.Table,
        lineIndicesByUUID: [UUID: Int]
    ) -> OCRTable? {
        let uniqueCells = Set(table.rows.flatMap { $0 })
        let cells = uniqueCells.map { cell in
            OCRTableCell(
                row: cell.rowRange.lowerBound,
                column: cell.columnRange.lowerBound,
                rowSpan: cell.rowRange.count,
                columnSpan: cell.columnRange.count,
                fallbackText: cell.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                boundingBox: OCRBoundingBox(rect: cell.content.boundingRegion.boundingBox.cgRect),
                lineIndices: Array(Set(cell.content.text.lines.compactMap { lineIndicesByUUID[$0.uuid] })).sorted()
            )
        }
        .sorted { ($0.row, $0.column) < ($1.row, $1.column) }

        guard !cells.isEmpty else {
            return nil
        }
        return OCRTable(cells: cells, boundingBox: OCRBoundingBox(rect: table.boundingRegion.boundingBox.cgRect))
    }

    private static func makeTextLines(from text: String) -> [OCRLine] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { OCRLine(text: $0) }
    }

    private func extractWords(from candidate: VNRecognizedText) -> [OCRWord] {
        let text = candidate.string
        let fullRange = text.startIndex ..< text.endIndex
        var words: [OCRWord] = []

        text.enumerateSubstrings(in: fullRange, options: [.byWords, .localized]) { substring, substringRange, _, _ in
            guard let substring else {
                return
            }

            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }

            guard let boundingBox = try? candidate.boundingBox(for: substringRange) else {
                return
            }

            words.append(OCRWord(
                text: trimmed,
                confidence: candidate.confidence,
                boundingBox: OCRBoundingBox(rect: boundingBox.boundingBox)
            ))
        }

        return words
    }

    @available(macOS 26.0, *)
    private func extractWords(from candidate: RecognizedText) -> [OCRWord] {
        let text = candidate.string
        let fullRange = text.startIndex ..< text.endIndex
        var words: [OCRWord] = []

        text.enumerateSubstrings(in: fullRange, options: [.byWords, .localized]) { substring, substringRange, _, _ in
            guard let substring,
                  let boundingBox = candidate.boundingBox(for: substringRange)
            else {
                return
            }

            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            words.append(OCRWord(text: trimmed, confidence: candidate.confidence, boundingBox: OCRBoundingBox(rect: boundingBox.boundingBox.cgRect)))
        }

        return words
    }

    private static func orientation(for source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation]
        else {
            return .up
        }

        if let orientationNumber = rawOrientation as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: orientationNumber) {
            return orientation
        }

        if let orientationNumber = rawOrientation as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: orientationNumber.uint32Value) {
            return orientation
        }

        return .up
    }

    public static func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = normalizedPDFPageBounds(for: page)
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
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: preferredPDFDisplayBox(for: page), to: context)

        return context.makeImage()
    }
    public static func preferredPDFDisplayBox(for page: PDFPage) -> PDFDisplayBox {
        let cropBounds = page.bounds(for: .cropBox)
        if cropBounds.width > 0, cropBounds.height > 0 {
            return .cropBox
        }
        return .mediaBox
    }

    public static func normalizedPDFPageBounds(for page: PDFPage) -> CGRect {
        let displayBox = preferredPDFDisplayBox(for: page)
        return page.bounds(for: displayBox)
            .applying(page.transform(for: displayBox))
            .standardized
            .integral
    }

    private func totalUnitCount(for urls: [URL]) throws -> Int {
        var total = 0

        for url in urls {
            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url) else {
                    throw AppleVisionError.unableToLoadPDF(url.path)
                }
                total += max(document.pageCount, 1)
            } else {
                total += 1
            }
        }

        return max(total, 1)
    }
}

struct RecognizedLine {
    let line: OCRLine
    let boundingBox: CGRect

    static func isBefore(_ lhs: RecognizedLine, _ rhs: RecognizedLine) -> Bool {
        let verticalDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)

        if verticalDelta > 0.02 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }

        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
}

private struct StructuredRecognition {
    let lines: [OCRLine]
    let structure: OCRDocumentStructure?
}

private enum StructuredPDFPageWork {
    case embeddedText([OCRLine])
    case renderedPage(CGImage)
}

@available(macOS 26.0, *)
private struct DocumentCandidate {
    let text: String
    let confidence: Float
    let recognizedText: RecognizedText
}

private extension OCRBoundingBox {
    init(rect: CGRect) {
        self.init(
            minX: rect.minX,
            minY: rect.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
