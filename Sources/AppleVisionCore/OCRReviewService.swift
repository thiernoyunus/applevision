import Foundation

public struct OCRReviewService {
    public init() {}

    public func review(results: [OCRResult]) -> OCRReviewReport {
        var issues: [OCRReviewIssue] = []
        let totalLineCount = results.reduce(0) { $0 + $1.lines.count }

        for result in results {
            for (index, line) in result.lines.enumerated() {
                if let issue = review(line: line, lineIndex: index + 1, in: result) {
                    issues.append(issue)
                }
            }
        }

        return OCRReviewReport(issues: issues, totalLineCount: totalLineCount)
    }

    private func review(line: OCRLine, lineIndex: Int, in result: OCRResult) -> OCRReviewIssue? {
        var reasons: [String] = []
        var severity: OCRReviewSeverity = .info
        var suggestion: String?

        if let confidence = line.confidence {
            if confidence < 0.70 {
                reasons.append("OCR confidence is very low.")
                severity = .critical
            } else if confidence < 0.88 {
                reasons.append("OCR confidence is lower than expected.")
                severity = max(severity, .warning)
            }
        }

        if let alternative = bestAlternative(for: line) {
            reasons.append("The top OCR guesses are very close, so this line may need review.")
            severity = max(severity, .warning)

            if shouldSuggestAlternative(primary: line.text, alternative: alternative.text) {
                suggestion = alternative.text
            }
        }

        if hasSuspiciousCharacterMix(line.text) {
            reasons.append("The line has an unusual mix of letters, digits, or symbols.")
            severity = max(severity, .warning)
        }

        if hasRepeatedSeparators(line.text) {
            reasons.append("The line contains repeated separators or punctuation.")
            severity = max(severity, .warning)
        }

        guard !reasons.isEmpty else {
            return nil
        }

        return OCRReviewIssue(
            sourcePath: result.sourcePath,
            pageNumber: result.pageNumber,
            lineIndex: lineIndex,
            originalText: line.text,
            suggestedText: suggestion,
            confidence: line.confidence,
            severity: severity,
            reasons: reasons,
            candidates: line.candidates,
            boundingBox: line.boundingBox
        )
    }

    private func bestAlternative(for line: OCRLine) -> OCRCandidate? {
        guard line.candidates.count > 1 else {
            return nil
        }

        let primary = line.candidates[0]
        let alternative = line.candidates[1]
        let gap = primary.confidence - alternative.confidence

        guard primary.confidence < 0.98, gap <= 0.12, primary.text != alternative.text else {
            return nil
        }

        return alternative
    }

    private func shouldSuggestAlternative(primary: String, alternative: String) -> Bool {
        if normalizeConfusable(primary) == normalizeConfusable(alternative) {
            return true
        }

        let lengthGap = abs(primary.count - alternative.count)
        return lengthGap <= 1 && primary != alternative
    }

    private func normalizeConfusable(_ text: String) -> String {
        let replacements: [Character: Character] = [
            "0": "O",
            "O": "O",
            "o": "O",
            "1": "I",
            "I": "I",
            "l": "I",
            "|": "I",
            "5": "S",
            "S": "S",
            "8": "B",
            "B": "B",
        ]

        return String(text.map { replacements[$0] ?? $0 }).lowercased()
    }

    private func hasSuspiciousCharacterMix(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter(CharacterSet.letters.contains).count
        let digits = text.unicodeScalars.filter(CharacterSet.decimalDigits.contains).count
        let punctuation = text.unicodeScalars.filter(CharacterSet.punctuationCharacters.contains).count
        let total = max(text.trimmingCharacters(in: .whitespacesAndNewlines).count, 1)

        if letters > 0, digits > 0, total <= 5 {
            return true
        }

        return punctuation >= 3 && Double(punctuation) / Double(total) > 0.25
    }

    private func hasRepeatedSeparators(_ text: String) -> Bool {
        text.contains("||") || text.contains("__") || text.contains("..") || text.contains(",,")
    }
}

private func max(_ lhs: OCRReviewSeverity, _ rhs: OCRReviewSeverity) -> OCRReviewSeverity {
    let rank: [OCRReviewSeverity: Int] = [
        .info: 0,
        .warning: 1,
        .critical: 2,
    ]

    return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
}
