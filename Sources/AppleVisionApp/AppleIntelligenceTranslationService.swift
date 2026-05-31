import Foundation

#if canImport(Translation)
import Translation
#endif

enum TranslationProvider: String, CaseIterable, Identifiable, Sendable {
    case apple
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:
            return "Apple Translation"
        case .openAI:
            return "OpenAI"
        }
    }

    var description: String {
        switch self {
        case .apple:
            return "Free local translation on supported Macs."
        case .openAI:
            return "Cloud translation using your own OpenAI API key."
        }
    }
}

enum DocumentTranslationTarget: String, CaseIterable, Identifiable, Sendable {
    case english
    case french
    case spanish
    case german

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .french:
            return "French"
        case .spanish:
            return "Spanish"
        case .german:
            return "German"
        }
    }

    var fileSuffix: String {
        "translated_\(rawValue)"
    }

#if canImport(Translation)
    @available(macOS 15.0, *)
    var language: Locale.Language {
        switch self {
        case .english:
            return Locale.Language(identifier: "en")
        case .french:
            return Locale.Language(identifier: "fr")
        case .spanish:
            return Locale.Language(identifier: "es")
        case .german:
            return Locale.Language(identifier: "de")
        }
    }
#endif
}

enum DocumentTranslationAvailability: Equatable, Sendable {
    case checking(String)
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
        case .checking(let message), .available(let message), .unavailable(let message):
            return message
        }
    }
}

enum AppleIntelligenceTranslationError: LocalizedError {
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .emptyResponse:
            return "Apple Translation returned an empty document."
        }
    }
}

actor AppleIntelligenceTranslationService {
    static let shared = AppleIntelligenceTranslationService()

    static func defaultAvailability() -> DocumentTranslationAvailability {
        .checking("Checking Arabic translation support on this Mac.")
    }

    func availability(for target: DocumentTranslationTarget) async -> DocumentTranslationAvailability {
#if canImport(Translation)
        if #available(macOS 15.0, *) {
            let availability = LanguageAvailability()
            let status = await availability.status(from: Self.sourceLanguage, to: target.language)

            switch status {
            case .installed:
                return .available("Arabic to \(target.displayName) translation is ready.")
            case .supported:
                return .available("Arabic to \(target.displayName) translation is supported and may download language assets the first time.")
            case .unsupported:
                return .unavailable("Arabic to \(target.displayName) translation is not available on this Mac right now.")
            @unknown default:
                return .unavailable("The translation status for Arabic to \(target.displayName) could not be determined.")
            }
        }
#endif
        return .unavailable("Document translation requires macOS 15 or later.")
    }

#if canImport(Translation)
    @available(macOS 15.0, *)
    static func configuration(for target: DocumentTranslationTarget) -> TranslationSession.Configuration {
        TranslationSession.Configuration(source: Self.sourceLanguage, target: target.language)
    }

    @available(macOS 15.0, *)
    func translateDocument(
        text: String,
        using session: TranslationSession
    ) async throws -> String {
        let segments = Self.makeSegments(from: text)
        var translatedSegments: [String] = []
        translatedSegments.reserveCapacity(segments.count)

        for segment in segments {
            if !segment.isTranslatable {
                translatedSegments.append(segment.text)
                continue
            }

            for chunk in Self.makeChunks(from: segment.text) {
                let response = try await session.translate(chunk)
                let translatedChunk = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translatedChunk.isEmpty else {
                    throw AppleIntelligenceTranslationError.emptyResponse
                }
                translatedSegments.append(translatedChunk)
            }
        }

        let translatedText = translatedSegments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else {
            throw AppleIntelligenceTranslationError.emptyResponse
        }

        return translatedText + "\n"
    }

    @available(macOS 15.0, *)
    private static var sourceLanguage: Locale.Language {
        Locale.Language(identifier: "ar")
    }

    private struct TranslationSegment: Sendable {
        let text: String
        let isTranslatable: Bool
    }

    private static func makeSegments(from text: String) -> [TranslationSegment] {
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false)

        var segments: [TranslationSegment] = []
        var paragraphLines: [String] = []
        var separator = ""

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            segments.append(TranslationSegment(text: paragraphLines.joined(separator: "\n"), isTranslatable: true))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushSeparator() {
            guard !separator.isEmpty else { return }
            segments.append(TranslationSegment(text: separator, isTranslatable: false))
            separator.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let value = String(line)
            if value.isEmpty {
                flushParagraph()
                separator.append("\n")
            } else {
                flushSeparator()
                paragraphLines.append(value)
            }
        }

        flushParagraph()
        flushSeparator()

        return segments
    }

    private static func makeChunks(from text: String, maxLength: Int = 1_200) -> [String] {
        if text.count <= maxLength {
            return [text]
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var chunks: [String] = []
        var current = ""

        for line in lines {
            let candidate = current.isEmpty ? line : current + "\n" + line
            if candidate.count <= maxLength {
                current = candidate
                continue
            }

            if !current.isEmpty {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }

            if line.count <= maxLength {
                current = line
                continue
            }

            var startIndex = line.startIndex
            while startIndex < line.endIndex {
                let endIndex = line.index(startIndex, offsetBy: maxLength, limitedBy: line.endIndex) ?? line.endIndex
                chunks.append(String(line[startIndex..<endIndex]))
                startIndex = endIndex
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
#endif
}
