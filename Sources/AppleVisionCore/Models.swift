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
    public let structure: OCRDocumentStructure?

    public init(
        sourcePath: String,
        pageNumber: Int?,
        text: String,
        lines: [OCRLine] = [],
        structure: OCRDocumentStructure? = nil
    ) {
        self.sourcePath = sourcePath
        self.pageNumber = pageNumber
        self.text = text
        self.lines = lines
        self.structure = structure
    }

    public init(
        sourcePath: String,
        pageNumber: Int?,
        lines: [OCRLine],
        structure: OCRDocumentStructure? = nil
    ) {
        self.sourcePath = sourcePath
        self.pageNumber = pageNumber
        self.lines = lines
        self.text = lines
            .map(\.text)
            .joined(separator: "\n")
        self.structure = structure
    }

    public var structuredText: String {
        guard let structure, !structure.tables.isEmpty else {
            return text
        }

        let tables = structure.tables.enumerated().map { index, table in
            StructuredTable(index: index, table: table, anchor: table.anchorLineIndex(in: lines))
        }
        let tablesByAnchor = Dictionary(grouping: tables, by: \.anchor)
        let coveredLineIndices = Set(tables.flatMap { $0.table.validLineIndices(in: lines) })
        var output: [String] = []
        var emittedTables = Set<Int>()

        for lineIndex in 0 ... lines.count {
            if let anchoredTables = tablesByAnchor[lineIndex] {
                for entry in anchoredTables.sorted(by: { $0.index < $1.index }) {
                    guard emittedTables.insert(entry.index).inserted else {
                        continue
                    }
                    output.append(entry.table.renderedText(using: lines))
                }
            }

            guard lineIndex < lines.count, !coveredLineIndices.contains(lineIndex) else {
                continue
            }
            output.append(lines[lineIndex].text)
        }

        return output.joined(separator: "\n")
    }

    public var structuredLineIndices: [Int] {
        guard let structure, !structure.tables.isEmpty else {
            return Array(lines.indices)
        }

        let tables = structure.tables.enumerated().map { index, table in
            StructuredTable(index: index, table: table, anchor: table.anchorLineIndex(in: lines))
        }
        let tablesByAnchor = Dictionary(grouping: tables, by: \.anchor)
        var orderedIndices: [Int] = []
        var emittedIndices = Set<Int>()
        var emittedTables = Set<Int>()

        for lineIndex in 0 ... lines.count {
            if let anchoredTables = tablesByAnchor[lineIndex] {
                for entry in anchoredTables.sorted(by: { $0.index < $1.index }) {
                    guard emittedTables.insert(entry.index).inserted else {
                        continue
                    }
                    for index in entry.table.lineIndicesInReadingOrder(in: lines) where emittedIndices.insert(index).inserted {
                        orderedIndices.append(index)
                    }
                }
            }

            guard lineIndex < lines.count, emittedIndices.insert(lineIndex).inserted else {
                continue
            }
            orderedIndices.append(lineIndex)
        }

        return orderedIndices
    }

    public var structuredLines: [OCRLine] {
        structuredLineIndices.map { lines[$0] }
    }
}

public struct OCRDocumentStructure: Codable, Sendable, Equatable {
    public let tables: [OCRTable]

    public init(tables: [OCRTable]) {
        self.tables = tables
    }
}

public struct OCRTable: Codable, Sendable, Equatable {
    public let cells: [OCRTableCell]
    public let boundingBox: OCRBoundingBox?

    public init(cells: [OCRTableCell], boundingBox: OCRBoundingBox? = nil) {
        self.cells = cells
        self.boundingBox = boundingBox
    }
}

public struct OCRTableCell: Codable, Sendable, Equatable {
    public let row: Int
    public let column: Int
    public let rowSpan: Int
    public let columnSpan: Int
    public let fallbackText: String
    public let boundingBox: OCRBoundingBox?
    public let lineIndices: [Int]

    public init(
        row: Int,
        column: Int,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        fallbackText: String = "",
        boundingBox: OCRBoundingBox? = nil,
        lineIndices: [Int] = []
    ) {
        self.row = row
        self.column = column
        self.rowSpan = max(rowSpan, 1)
        self.columnSpan = max(columnSpan, 1)
        self.fallbackText = fallbackText
        self.boundingBox = boundingBox
        self.lineIndices = Array(Set(lineIndices)).sorted()
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

public struct OCRBoundingBox: Codable, Sendable, Equatable {
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

    /// Maps Vision's normalized, lower-left-origin box into a top-left-origin rectangle.
    public func rect(in topLeftBounds: CGRect) -> CGRect {
        CGRect(
            x: topLeftBounds.minX + CGFloat(minX) * topLeftBounds.width,
            y: topLeftBounds.minY + (1 - CGFloat(minY) - CGFloat(height)) * topLeftBounds.height,
            width: CGFloat(width) * topLeftBounds.width,
            height: CGFloat(height) * topLeftBounds.height
        )
    }
}

private struct StructuredTable {
    let index: Int
    let table: OCRTable
    let anchor: Int
}

private extension OCRTable {
    func validLineIndices(in lines: [OCRLine]) -> [Int] {
        Array(Set(cells.flatMap(\.lineIndices).filter { lines.indices.contains($0) })).sorted()
    }

    func anchorLineIndex(in lines: [OCRLine]) -> Int {
        validLineIndices(in: lines).first ?? 0
    }

    func lineIndicesInReadingOrder(in lines: [OCRLine]) -> [Int] {
        var seen = Set<Int>()
        return cells
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
            .flatMap(\.lineIndices)
            .filter { lines.indices.contains($0) && seen.insert($0).inserted }
    }

    func renderedText(using lines: [OCRLine]) -> String {
        guard let rowCount = cells.map({ $0.row + $0.rowSpan }).max(),
              let columnCount = cells.map({ $0.column + $0.columnSpan }).max()
        else {
            return ""
        }

        var rows = Array(repeating: Array(repeating: "", count: columnCount), count: rowCount)
        for cell in cells.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) where rows.indices.contains(cell.row) && rows[cell.row].indices.contains(cell.column) {
            let mappedIndices = cell.lineIndices.filter { lines.indices.contains($0) }
            rows[cell.row][cell.column] = mappedIndices.isEmpty
                ? cell.fallbackText
                : mappedIndices.map { lines[$0].text }.joined(separator: " ")
        }
        return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
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
