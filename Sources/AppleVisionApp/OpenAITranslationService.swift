import Foundation

enum OpenAITranslationModel: String, CaseIterable, Identifiable, Sendable {
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt5 = "gpt-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt5Mini:
            return "GPT-5 mini"
        case .gpt5Nano:
            return "GPT-5 nano"
        case .gpt41Mini:
            return "GPT-4.1 mini"
        case .gpt5:
            return "GPT-5"
        }
    }

    var detail: String {
        switch self {
        case .gpt5Mini:
            return "Balanced quality and cost."
        case .gpt5Nano:
            return "Cheapest and fastest."
        case .gpt41Mini:
            return "Fast non-reasoning option."
        case .gpt5:
            return "Highest quality, higher cost."
        }
    }
}

enum OpenAITranslationError: LocalizedError {
    case missingAPIKey
    case requestFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key before using the OpenAI translation provider."
        case .requestFailed(let message):
            return message
        case .emptyResponse:
            return "OpenAI returned an empty translation."
        }
    }
}

actor OpenAITranslationService {
    static let shared = OpenAITranslationService()

    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func translateDocument(
        text: String,
        to target: DocumentTranslationTarget,
        apiKey: String,
        model: OpenAITranslationModel
    ) async throws -> String {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw OpenAITranslationError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(normalizedKey)", forHTTPHeaderField: "Authorization")

        let body = OpenAIResponseRequest(
            model: model.rawValue,
            instructions: """
            Translate the provided Arabic document faithfully into \(target.displayName).
            Preserve paragraph breaks, line ordering, punctuation intent, citations, numbers, names, URLs, and document structure.
            Do not summarize, explain, or add commentary.
            Return only the translated document text.
            """,
            input: text
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranslationError.requestFailed("OpenAI returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data)
            let message = apiError?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAITranslationError.requestFailed("OpenAI translation failed: \(message)")
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        let translatedText = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else {
            throw OpenAITranslationError.emptyResponse
        }

        return translatedText + "\n"
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private struct OpenAIResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentItem]?
    }

    let output: [OutputItem]?

    var outputText: String {
        output?
            .flatMap { $0.content ?? [] }
            .compactMap { item in
                item.type == "output_text" ? item.text : nil
            }
            .joined(separator: "") ?? ""
    }
}
