import Foundation

public enum OutputRenderer {
    public static func render(results: [OCRResult], format: OCRTextFormat) throws -> String {
        switch format {
        case .text:
            return renderText(results: results)
        case .plain:
            return renderPlainText(results: results)
        case .json:
            return try renderJSON(results: results)
        }
    }

    public static func renderArabic(results: [OCRResult], mode: ArabicOutputMode) -> [(suffix: String, text: String)] {
        let withHarakat = renderPlainText(results: results)
        let withoutHarakat = ArabicTextTransformer.removeHarakat(from: withHarakat)

        switch mode {
        case .both:
            return [
                ("with_harakat", withHarakat),
                ("without_harakat", withoutHarakat),
            ]
        case .withHarakat:
            return [("with_harakat", withHarakat)]
        case .withoutHarakat:
            return [("without_harakat", withoutHarakat)]
        }
    }

    public static func render(report: OCRReviewReport) -> String {
        guard !report.issues.isEmpty else {
            return """
            OCR Verification Report
            No suspicious lines were found across \(report.totalLineCount) line(s).

            """
        }

        let header = """
        OCR Verification Report
        Suspicious lines: \(report.issueCount) of \(report.totalLineCount)
        Critical: \(report.criticalCount)
        Warning: \(report.warningCount)

        """

        let body = report.issues.map { issue in
            let label: String
            if let pageNumber = issue.pageNumber {
                label = "\(issue.sourcePath) [page \(pageNumber), line \(issue.lineIndex)]"
            } else {
                label = "\(issue.sourcePath) [line \(issue.lineIndex)]"
            }

            let confidence = issue.confidence.map { String(format: "%.2f", $0) } ?? "n/a"
            let reasons = issue.reasons.map { "- \($0)" }.joined(separator: "\n")
            let suggestionLine = issue.suggestedText.map { "Suggested review text: \($0)\n" } ?? ""

            return """
            ===== \(label) =====
            Severity: \(issue.severity.displayName)
            Confidence: \(confidence)
            Original: \(issue.originalText)
            \(suggestionLine)\(reasons)
            """
        }
        .joined(separator: "\n\n")

        return header + body + "\n"
    }

    private static func renderText(results: [OCRResult]) -> String {
        results.map { result in
            let label: String

            if let pageNumber = result.pageNumber {
                label = "\(result.sourcePath) [page \(pageNumber)]"
            } else {
                label = result.sourcePath
            }

            let body = result.text.isEmpty ? "[No text recognized]" : result.text
            return "===== \(label) =====\n\(body)"
        }
        .joined(separator: "\n\n") + "\n"
    }

    private static func renderJSON(results: [OCRResult]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(results)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func renderPlainText(results: [OCRResult]) -> String {
        results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n"
    }
}
