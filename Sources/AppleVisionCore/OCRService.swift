import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

public struct OCRService: Sendable {
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

        if options.pdfTextMode == .ocrOnly, document.pageCount > 1 {
            return try processOCROnlyPDFConcurrently(
                at: url,
                pageCount: document.pageCount,
                totalUnitCount: totalUnitCount,
                completedUnitCount: &completedUnitCount,
                progress: progress
            )
        }

        var pageResults: [OCRResult] = []

        for pageIndex in 0 ..< document.pageCount {
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

        return pageResults
    }

    private func processOCROnlyPDFConcurrently(
        at url: URL,
        pageCount: Int,
        totalUnitCount: Int,
        completedUnitCount: inout Int,
        progress: (@Sendable (OCRProgressUpdate) -> Void)?
    ) throws -> [OCRResult] {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        queue.qualityOfService = .userInitiated

        let state = ConcurrentPDFOCRState(
            pageCount: pageCount,
            completedUnitCount: completedUnitCount
        )

        for pageIndex in 0 ..< pageCount {
            queue.addOperation {
                guard !state.hasFailed else {
                    return
                }

                do {
                    let result = try self.processOCROnlyPDFPage(at: url, pageIndex: pageIndex)
                    let progressUpdate = state.record(
                        result: result,
                        pageIndex: pageIndex,
                        totalUnitCount: totalUnitCount,
                        sourcePath: url.path,
                        pageNumber: pageIndex + 1
                    )
                    progress?(progressUpdate)
                } catch {
                    state.record(error: error)
                }
            }
        }

        queue.waitUntilAllOperationsAreFinished()
        completedUnitCount = state.completedUnitCount
        return try state.orderedResults(sourcePath: url.path)
    }

    private func processOCROnlyPDFPage(at url: URL, pageIndex: Int) throws -> OCRResult {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex),
              let renderedPage = Self.renderPDFPage(page)
        else {
            throw AppleVisionError.unableToRenderPDFPage(url.path, pageIndex + 1)
        }

        return OCRResult(
            sourcePath: url.path,
            pageNumber: pageIndex + 1,
            lines: try recognizeText(in: renderedPage, orientation: .up)
        )
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

            let candidateLimit = options.detailLevel.includesAlternativeCandidates ? 3 : 1
            for candidate in observation.topCandidates(candidateLimit) {
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

            let candidates = options.detailLevel.includesAlternativeCandidates
                ? recognizedCandidates.map { candidate in
                    OCRCandidate(
                        text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: candidate.confidence
                    )
                }
                : []

            lines.append(RecognizedLine(
                line: OCRLine(
                    text: primaryCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: primaryCandidate.confidence,
                    boundingBox: OCRBoundingBox(rect: observation.boundingBox),
                    candidates: candidates,
                    words: options.detailLevel.includesWordGeometry ? extractWords(from: primaryCandidate) : []
                ),
                boundingBox: observation.boundingBox
            ))
        }

        return lines.sorted(by: RecognizedLine.isBefore).map { $0.line }
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

    public static func renderPDFPage(
        _ page: PDFPage,
        configuration: PDFRenderConfiguration = .default
    ) -> CGImage? {
        let bounds = normalizedPDFPageBounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let pixelSize = configuration.pixelSize(for: bounds.size)
        let scale = pixelSize.width / bounds.width
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
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
        page.bounds(for: preferredPDFDisplayBox(for: page)).standardized.integral
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

private final class ConcurrentPDFOCRState: @unchecked Sendable {
    private let lock = NSLock()
    private var pageResults: [OCRResult?]
    private var firstError: Error?
    private var storedCompletedUnitCount: Int

    init(pageCount: Int, completedUnitCount: Int) {
        self.pageResults = Array<OCRResult?>(repeating: nil, count: pageCount)
        self.storedCompletedUnitCount = completedUnitCount
    }

    var hasFailed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return firstError != nil
    }

    var completedUnitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletedUnitCount
    }

    func record(
        result: OCRResult,
        pageIndex: Int,
        totalUnitCount: Int,
        sourcePath: String,
        pageNumber: Int
    ) -> OCRProgressUpdate {
        lock.lock()
        defer { lock.unlock() }

        pageResults[pageIndex] = result
        storedCompletedUnitCount += 1
        return OCRProgressUpdate(
            completedUnitCount: storedCompletedUnitCount,
            totalUnitCount: totalUnitCount,
            sourcePath: sourcePath,
            pageNumber: pageNumber
        )
    }

    func record(error: Error) {
        lock.lock()
        defer { lock.unlock() }

        if firstError == nil {
            firstError = error
        }
    }

    func orderedResults(sourcePath: String) throws -> [OCRResult] {
        lock.lock()
        defer { lock.unlock() }

        if let firstError {
            throw firstError
        }

        return try pageResults.enumerated().map { pageIndex, result in
            guard let result else {
                throw AppleVisionError.unableToRenderPDFPage(sourcePath, pageIndex + 1)
            }
            return result
        }
    }
}

public struct PDFRenderConfiguration: Equatable, Sendable {
    public static let `default` = PDFRenderConfiguration()

    public let scale: CGFloat
    public let maximumPixelCount: CGFloat

    public init(scale: CGFloat = 2.0, maximumPixelCount: CGFloat = 8_000_000) {
        self.scale = max(scale, 0.1)
        self.maximumPixelCount = max(maximumPixelCount, 1)
    }

    public func pixelSize(for pointSize: CGSize) -> CGSize {
        guard pointSize.width > 0, pointSize.height > 0 else {
            return .zero
        }

        let requestedWidth = pointSize.width * scale
        let requestedHeight = pointSize.height * scale
        let requestedPixelCount = requestedWidth * requestedHeight

        guard requestedPixelCount > maximumPixelCount else {
            return CGSize(width: requestedWidth.rounded(.up), height: requestedHeight.rounded(.up))
        }

        let cappedScale = sqrt(maximumPixelCount / requestedPixelCount)
        return CGSize(
            width: max(1, (requestedWidth * cappedScale).rounded(.down)),
            height: max(1, (requestedHeight * cappedScale).rounded(.down))
        )
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
