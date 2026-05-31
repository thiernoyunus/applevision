import AppleVisionCore
import Foundation
#if canImport(Vision)
import Vision
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleIntelligenceReviewSuggestion: Equatable, Sendable {
    let correctedText: String
    let reason: String
}

struct AppleIntelligenceReviewContext: Sendable {
    let previousLine: String?
    let nextLine: String?
    let documentExcerpt: String
}

enum AppleIntelligenceReviewAvailability: Equatable, Sendable {
    case available(String)
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var message: String {
        switch self {
        case .available(let message), .unavailable(let message):
            return message
        }
    }
}

enum AppleIntelligenceReviewError: LocalizedError {
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .emptyResponse:
            return "Apple Intelligence returned an empty suggestion."
        }
    }
}

actor AppleIntelligenceReviewService {
    static let shared = AppleIntelligenceReviewService()

    static func availability() -> AppleIntelligenceReviewAvailability {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return .available("Apple Intelligence is ready. Ask for a suggestion only on the flagged lines you want reviewed.")
            }

            let detail = String(describing: model.availability)
            return .unavailable("Apple Intelligence is not ready on this Mac right now (\(detail)).")
        }
#endif
        return .unavailable("Apple Intelligence suggestions require macOS 26 or later.")
    }

    func suggestCorrection(
        for issue: OCRReviewIssue,
        currentText: String,
        context: AppleIntelligenceReviewContext
    ) async throws -> AppleIntelligenceReviewSuggestion {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AppleIntelligenceReviewError.unavailable(Self.availability().message)
            }

            let cropEvidence = secondaryOCREvidence(for: issue)

            let session = LanguageModelSession(instructions: """
            You review OCR output conservatively.
            Use only the OCR evidence and local document context provided in the prompt.
            Prefer evidence from the crop-only OCR pass and surrounding lines over the current export text.
            Never translate, summarize, paraphrase, or normalize names, IDs, or uncommon spellings.
            Preserve the same language and script.
            For Arabic text, prefer valid Arabic word forms and common spacing only when they are supported by multiple clues in the prompt.
            If the evidence is ambiguous, return the current export text unchanged and explain why.
            """)

            let response = try await session.respond(
                to: prompt(
                    for: issue,
                    currentText: currentText,
                    context: context,
                    cropEvidence: cropEvidence
                ),
                generating: OCRLineCorrection.self
            )

            let correctedText = response.content.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !correctedText.isEmpty else {
                throw AppleIntelligenceReviewError.emptyResponse
            }

            let reason = response.content.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return AppleIntelligenceReviewSuggestion(
                correctedText: correctedText,
                reason: reason.isEmpty ? "Apple Intelligence reviewed this line and kept the best supported text." : reason
            )
        }
#endif
        throw AppleIntelligenceReviewError.unavailable(Self.availability().message)
    }

    private func prompt(
        for issue: OCRReviewIssue,
        currentText: String,
        context: AppleIntelligenceReviewContext,
        cropEvidence: SecondaryOCREvidence
    ) -> String {
        let confidenceText: String
        if let confidence = issue.confidence {
            confidenceText = String(format: "%.2f", confidence)
        } else {
            confidenceText = "unknown"
        }

        let candidateText: String
        if issue.candidates.isEmpty {
            candidateText = "None"
        } else {
            candidateText = issue.candidates.enumerated().map { index, candidate in
                let score = String(format: "%.2f", candidate.confidence)
                return "\(index + 1). \(candidate.text) (confidence \(score))"
            }.joined(separator: "\n")
        }

        let heuristicSuggestion = issue.suggestedText?.isEmpty == false ? issue.suggestedText! : "None"
        let pageLabel = issue.pageNumber.map(String.init) ?? "none"
        let previousLine = context.previousLine?.isEmpty == false ? context.previousLine! : "None"
        let nextLine = context.nextLine?.isEmpty == false ? context.nextLine! : "None"

        return """
        Review this one flagged OCR line.

        Original OCR text:
        \(issue.originalText)

        OCR candidates:
        \(candidateText)

        Crop-only OCR evidence:
        best text: \(cropEvidence.primaryText)
        candidates:
        \(cropEvidence.candidatesText)

        Previous line:
        \(previousLine)

        Next line:
        \(nextLine)

        Nearby document excerpt:
        \(context.documentExcerpt)

        OCR confidence:
        \(confidenceText)

        Source location:
        file: \(URL(fileURLWithPath: issue.sourcePath).lastPathComponent)
        page: \(pageLabel)
        line: \(issue.lineIndex)

        Current export text:
        \(currentText)

        Heuristic suggestion:
        \(heuristicSuggestion)

        Why this line was flagged:
        \(issue.reasons.joined(separator: " "))

        Return the safest text to export for this line.
        Change the text only if the crop-only OCR pass, neighboring lines, or multiple OCR candidates support the correction.
        """
    }

    private func secondaryOCREvidence(for issue: OCRReviewIssue) -> SecondaryOCREvidence {
#if canImport(Vision)
        guard let croppedImage = ReviewPreviewRenderer.croppedCGImage(for: issue) else {
            return .empty
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ar", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: croppedImage, options: [:])

        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let candidates = observations
                .flatMap { $0.topCandidates(5) }
                .map { OCRCandidate(text: $0.string, confidence: $0.confidence) }
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            guard !candidates.isEmpty else {
                return .empty
            }

            let deduplicated = deduplicateCandidates(candidates)
            return SecondaryOCREvidence(
                primaryText: deduplicated.first?.text ?? "None",
                candidates: deduplicated
            )
        } catch {
            return .empty
        }
#else
        return .empty
#endif
    }

    private func deduplicateCandidates(_ candidates: [OCRCandidate]) -> [OCRCandidate] {
        var seen: Set<String> = []
        var result: [OCRCandidate] = []

        for candidate in candidates {
            let normalized = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(OCRCandidate(text: normalized, confidence: candidate.confidence))
        }

        return Array(result.prefix(5))
    }
}

private struct SecondaryOCREvidence {
    let primaryText: String
    let candidates: [OCRCandidate]

    static let empty = SecondaryOCREvidence(primaryText: "None", candidates: [])

    var candidatesText: String {
        if candidates.isEmpty {
            return "None"
        }

        return candidates.enumerated().map { index, candidate in
            let score = String(format: "%.2f", candidate.confidence)
            return "\(index + 1). \(candidate.text) (confidence \(score))"
        }.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct OCRLineCorrection {
    @Guide(description: "The exact text that should be exported for this OCR line. If uncertain, return the current export text unchanged.")
    let correctedText: String

    @Guide(description: "One brief sentence explaining the correction or why the current text was preserved.")
    let reason: String
}
#endif
