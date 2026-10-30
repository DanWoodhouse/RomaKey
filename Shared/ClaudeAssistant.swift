import Foundation
import KeyboardCore

/// What the ✨ panel needs from a model. Apple Intelligence (the default) and Claude both answer
/// with the same prompts (`AIPrompts`), and both go through `AIValidation`.
protocol AIEngine {
    func checkGrammar(_ text: String) async throws -> GrammarOutcome
    func translate(_ english: String, style: Politeness) async throws -> Translation?
    func rewrite(_ japanese: String, as target: Politeness) async throws -> String?
    func explain(_ japanese: String) async throws -> Explanation?
    func convertToKanji(_ hiragana: String) async throws -> String?
    func rewriteEnglish(_ english: String, as style: EnglishStyle) async throws -> String?
    func translateToEnglish(_ japanese: String) async throws -> String?
}

#if canImport(FoundationModels)
/// Apple's on-device model, through `AIAssistant`.
@available(iOS 26.0, *)
struct AppleAIEngine: AIEngine {
    func checkGrammar(_ text: String) async throws -> GrammarOutcome { try await AIAssistant.checkGrammar(text) }
    func translate(_ english: String, style: Politeness) async throws -> Translation? { try await AIAssistant.translate(english, style: style) }
    func rewrite(_ japanese: String, as target: Politeness) async throws -> String? { try await AIAssistant.rewrite(japanese, as: target) }
    func explain(_ japanese: String) async throws -> Explanation? { try await AIAssistant.explain(japanese) }
    func convertToKanji(_ hiragana: String) async throws -> String? { try await AIAssistant.convertToKanji(hiragana) }
    func rewriteEnglish(_ english: String, as style: EnglishStyle) async throws -> String? { try await AIAssistant.rewriteEnglish(english, as: style) }
    func translateToEnglish(_ japanese: String) async throws -> String? { try await AIAssistant.translateToEnglish(japanese) }
}
#endif

/// Claude, through the Messages API with the user's own API key (Settings → AI). The text goes
/// to Anthropic, so it's opt-in, and the keyboard needs Full Access to reach the network.
/// Answers are structured JSON in the same shapes as Apple's guided generation.
struct ClaudeAIEngine: AIEngine {
    let apiKey: String

    enum Failure: LocalizedError {
        case missingKey
        case refused
        case http(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Add your Claude API key in the RomaKey app: Settings → AI."
            case .refused: return "Claude declined this text."
            case .http(401): return "Claude didn't accept the API key. Check it in the RomaKey app."
            case .http(429): return "Too many requests. Try again in a moment."
            case .http(let status): return "Claude couldn't answer (error \(status))."
            case .unreadable: return "Claude's answer couldn't be read."
            }
        }
    }

    private static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func checkGrammar(_ text: String) async throws -> GrammarOutcome {
        let input = AIPrompts.trimmedInput(text)
        let response: GrammarJSON = try await ask(AIPrompts.grammar(for: input), input: input, schema: Self.object([
            "mistakes": ["type": "array", "items": Self.object([
                "original": ["type": "string"], "fix": ["type": "string"], "reason": ["type": "string"],
            ])],
            "corrected": ["type": "string"],
        ]))
        return AIValidation.grammar(
            input: input,
            corrected: response.corrected,
            corrections: response.mistakes.map { GrammarCorrection(original: $0.original, fix: $0.fix, reason: $0.reason) }
        )
    }

    func translate(_ english: String, style: Politeness) async throws -> Translation? {
        let input = AIPrompts.trimmedInput(english)
        let response: TranslationJSON = try await ask(AIPrompts.translate(style: style), input: input, schema: Self.object([
            "japanese": ["type": "string"], "reading": ["type": "string"],
        ]))
        return AIValidation.translation(japanese: response.japanese, reading: response.reading)
    }

    func rewrite(_ japanese: String, as target: Politeness) async throws -> String? {
        let input = AIPrompts.trimmedInput(japanese)
        let response: RewriteJSON = try await ask(AIPrompts.politeness(target), input: input, schema: Self.object([
            "text": ["type": "string"],
        ]))
        return AIValidation.rewrite(input: input, output: response.text)
    }

    func explain(_ japanese: String) async throws -> Explanation? {
        let input = AIPrompts.trimmedInput(japanese)
        let response: ExplanationJSON = try await ask(AIPrompts.explain, input: input, schema: Self.object([
            "reading": ["type": "string"], "meaning": ["type": "string"],
            "notes": ["type": "array", "items": ["type": "string"]],
        ]))
        return AIValidation.explanation(reading: response.reading, meaning: response.meaning, notes: response.notes)
    }

    func convertToKanji(_ hiragana: String) async throws -> String? {
        let input = AIPrompts.trimmedInput(hiragana)
        let response: ConversionJSON = try await ask(AIPrompts.kanji, input: input, schema: Self.object([
            "converted": ["type": "string"],
        ]))
        return AIValidation.kanjiConversion(input: input, output: response.converted)
    }

    func rewriteEnglish(_ english: String, as style: EnglishStyle) async throws -> String? {
        let input = AIPrompts.trimmedInput(english)
        let response: RewriteJSON = try await ask(AIPrompts.englishRewrite(style), input: input, schema: Self.object([
            "text": ["type": "string"],
        ]))
        return AIValidation.englishRewrite(input: input, output: response.text)
    }

    func translateToEnglish(_ japanese: String) async throws -> String? {
        let input = AIPrompts.trimmedInput(japanese)
        let response: EnglishJSON = try await ask(AIPrompts.toEnglish, input: input, schema: Self.object([
            "english": ["type": "string"],
        ]))
        return AIValidation.englishTranslation(response.english)
    }

    // MARK: - Request

    private func ask<Response: Decodable>(_ prompt: AIPrompt, input: String, schema: [String: Any]) async throws -> Response {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 4000,
            "system": prompt.instructions,
            "messages": [["role": "user", "content": AIPrompts.prompt(for: input)]],
            // Short rewrites: low effort keeps answers quick enough for a keyboard.
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            // If Claude declines, Anthropic retries on its recommended fallback model.
            "fallbacks": "default",
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.http(http.statusCode)
        }
        let message = try JSONDecoder().decode(MessageJSON.self, from: data)
        guard message.stopReason != "refusal" else { throw Failure.refused }
        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Response.self, from: json) else { throw Failure.unreadable }
        return decoded
    }

    /// A JSON schema object where every property is required, as structured outputs expect.
    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": Array(properties.keys), "additionalProperties": false]
    }

    private struct MessageJSON: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct GrammarJSON: Decodable {
        struct Mistake: Decodable {
            let original: String
            let fix: String
            let reason: String
        }

        let mistakes: [Mistake]
        let corrected: String
    }

    private struct TranslationJSON: Decodable {
        let japanese: String
        let reading: String
    }

    private struct RewriteJSON: Decodable {
        let text: String
    }

    private struct ExplanationJSON: Decodable {
        let reading: String
        let meaning: String
        let notes: [String]
    }

    private struct EnglishJSON: Decodable {
        let english: String
    }

    private struct ConversionJSON: Decodable {
        let converted: String
    }
}
