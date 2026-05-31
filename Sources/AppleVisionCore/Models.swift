import Foundation
import Vision

public enum OCRTextFormat: String, CaseIterable, Sendable {
    case text
    case json
    case plain
}

public enum ArabicOutputMode: String, CaseIterable, Identifiable, Sendable {
    case both
    case withHarakat
    case withoutHarakat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .both:
            return "Both Versions"
        case .withHarakat:
            return "With Harakat"
        case .withoutHarakat:
            return "Without Harakat"
        }
    }
}

public enum DocumentExportChoice: String, CaseIterable, Identifiable, Sendable {
    case text
    case searchablePDF
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text:
            return "Text Files"
        case .searchablePDF:
            return "Searchable PDF"
        case .both:
            return "Both"
        }
    }

    public var includesTextFiles: Bool {
        self == .text || self == .both
    }

    public var includesSearchablePDF: Bool {
        self == .searchablePDF || self == .both
    }
}

public enum PDFTextMode: String, CaseIterable, Identifiable, Sendable {
    case preferEmbeddedText
    case ocrOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .preferEmbeddedText:
            return "Prefer PDF Text"
        case .ocrOnly:
            return "Force OCR"
        }
    }
}

public struct OCRRequestOptions: Sendable {
    public let recursive: Bool
    public let recognitionLevel: VNRequestTextRecognitionLevel
    public let recognitionLanguages: [String]
    public let usesLanguageCorrection: Bool
    public let pdfTextMode: PDFTextMode

    public init(
        recursive: Bool = false,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        recognitionLanguages: [String] = [],
        usesLanguageCorrection: Bool = true,
        pdfTextMode: PDFTextMode = .preferEmbeddedText
    ) {
        self.recursive = recursive
        self.recognitionLevel = recognitionLevel
        self.recognitionLanguages = recognitionLanguages
        self.usesLanguageCorrection = usesLanguageCorrection
        self.pdfTextMode = pdfTextMode
    }

    public static let arabicDefault = OCRRequestOptions(
        recursive: false,
        recognitionLevel: .accurate,
        recognitionLanguages: ["ar", "en-US"],
        usesLanguageCorrection: true,
        pdfTextMode: .preferEmbeddedText
    )
}

public struct OCRResult: Codable, Sendable {
    public let sourcePath: String
    public let pageNumber: Int?
    public let text: String
    public let lines: [OCRLine]

    public init(sourcePath: String, pageNumber: Int?, text: String, lines: [OCRLine] = []) {
        self.sourcePath = sourcePath
        self.pageNumber = pageNumber
        self.text = text
        self.lines = lines
    }

    public init(sourcePath: String, pageNumber: Int?, lines: [OCRLine]) {
        self.sourcePath = sourcePath
        self.pageNumber = pageNumber
        self.lines = lines
        self.text = lines
            .map(\.text)
            .joined(separator: "\n")
    }
}

public struct OCRLine: Codable, Sendable {
    public let text: String
    public let confidence: Float?
    public let boundingBox: OCRBoundingBox?
    public let candidates: [OCRCandidate]
    public let words: [OCRWord]

    public init(
        text: String,
        confidence: Float? = nil,
        boundingBox: OCRBoundingBox? = nil,
        candidates: [OCRCandidate] = [],
        words: [OCRWord] = []
    ) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.candidates = candidates
        self.words = words
    }
}

public struct OCRWord: Codable, Sendable {
    public let text: String
    public let confidence: Float?
    public let boundingBox: OCRBoundingBox

    public init(text: String, confidence: Float? = nil, boundingBox: OCRBoundingBox) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct OCRCandidate: Codable, Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public struct OCRBoundingBox: Codable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

public enum OCRReviewSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case critical

    public var displayName: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }
}

public struct OCRReviewIssue: Codable, Sendable, Identifiable {
    public let id: String
    public let sourcePath: String
    public let pageNumber: Int?
    public let lineIndex: Int
    public let originalText: String
    public let suggestedText: String?
    public let confidence: Float?
    public let severity: OCRReviewSeverity
    public let reasons: [String]
    public let candidates: [OCRCandidate]
    public let boundingBox: OCRBoundingBox?

    public init(
        sourcePath: String,
        pageNumber: Int?,
        lineIndex: Int,
        originalText: String,
        suggestedText: String?,
        confidence: Float?,
        severity: OCRReviewSeverity,
        reasons: [String],
        candidates: [OCRCandidate],
        boundingBox: OCRBoundingBox?
    ) {
        self.id = "\(sourcePath)#\(pageNumber ?? 0)#\(lineIndex)"
        self.sourcePath = sourcePath
        self.pageNumber = pageNumber
        self.lineIndex = lineIndex
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.confidence = confidence
        self.severity = severity
        self.reasons = reasons
        self.candidates = candidates
        self.boundingBox = boundingBox
    }
}

public struct OCRReviewReport: Codable, Sendable {
    public let issues: [OCRReviewIssue]
    public let totalLineCount: Int

    public init(issues: [OCRReviewIssue], totalLineCount: Int) {
        self.issues = issues
        self.totalLineCount = totalLineCount
    }

    public var issueCount: Int {
        issues.count
    }

    public var criticalCount: Int {
        issues.filter { $0.severity == .critical }.count
    }

    public var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }
}

public struct OCRProgressUpdate: Sendable {
    public let completedUnitCount: Int
    public let totalUnitCount: Int
    public let sourcePath: String
    public let pageNumber: Int?

    public init(completedUnitCount: Int, totalUnitCount: Int, sourcePath: String, pageNumber: Int?) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.sourcePath = sourcePath
        self.pageNumber = pageNumber
    }
}

public enum InputOrdering {
    public static func isNaturalPageBefore(_ lhs: URL, _ rhs: URL) -> Bool {
        NSString(string: lhs.path).localizedStandardCompare(rhs.path) == .orderedAscending
    }
}

public enum AppleVisionError: LocalizedError, Sendable {
    case invalidArguments(String)
    case fileNotFound(String)
    case unsupportedInput(String)
    case noSupportedInputs(String)
    case unableToLoadImage(String)
    case unableToLoadPDF(String)
    case unableToRenderPDFPage(String, Int)
    case writeFailed(String)
    case dropFailed

    public var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            return message
        case let .fileNotFound(path):
            return "Input path not found: \(path)"
        case let .unsupportedInput(path):
            return "Unsupported input type: \(path)"
        case let .noSupportedInputs(message):
            return message
        case let .unableToLoadImage(path):
            return "Unable to load image: \(path)"
        case let .unableToLoadPDF(path):
            return "Unable to load PDF: \(path)"
        case let .unableToRenderPDFPage(path, page):
            return "Unable to render PDF page \(page) for \(path)"
        case let .writeFailed(path):
            return "Failed to write output to \(path)"
        case .dropFailed:
            return "Unable to read the dropped files."
        }
    }
}
