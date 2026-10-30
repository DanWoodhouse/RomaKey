import Foundation
import KeyboardCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One test case's run, for the prompt check screen.
struct AIEvalResult: Identifiable {
    let id = UUID()
    let testCase: AIEvalCase
    let output: AIEvalOutput
    /// What the model returned before validation, to see why a case failed.
    let raw: String
    let seconds: Double
    let failures: [String]

    var passed: Bool { failures.isEmpty }
}

#if canImport(FoundationModels)

// Output types. Property names match the prompts' examples, and the model fills them in
// declaration order, so anything it should think about first comes first.

@available(iOS 26.0, *)
@Generable
struct GrammarResponse {
    @Guide(description: "Each mistake: the wrong part, the fix and a short reason")
    var mistakes: [MistakeResponse]
    @Guide(description: "The whole text with every fix applied")
    var corrected: String
}

@available(iOS 26.0, *)
@Generable
struct MistakeResponse {
    var original: String
    var fix: String
    @Guide(description: "One short sentence")
    var reason: String
}

@available(iOS 26.0, *)
@Generable
struct TranslationResponse {
    @Guide(description: "The Japanese translation")
    var japanese: String
    @Guide(description: "The translation's reading in hiragana")
    var reading: String
}

@available(iOS 26.0, *)
@Generable
struct RewriteResponse {
    @Guide(description: "The rewritten text only")
    var text: String
}

@available(iOS 26.0, *)
@Generable
struct ExplanationResponse {
    @Guide(description: "The whole text in hiragana")
    var reading: String
    @Guide(description: "A natural English translation")
    var meaning: String
    @Guide(description: "Short notes in English on the grammar or words", .maximumCount(3))
    var notes: [String]
}

@available(iOS 26.0, *)
@Generable
struct EnglishTranslationResponse {
    @Guide(description: "The English translation")
    var english: String
}

@available(iOS 26.0, *)
@Generable
struct ConversionResponse {
    @Guide(description: "The text written with kanji and kana")
    var converted: String
}

/// Runs the AI modes on Apple's on-device model. Every request uses a fresh session, so earlier
/// requests can't influence later ones, and greedy decoding, so the same text always gets the
/// same answer. Outputs go through `AIValidation` before anything is shown.
@available(iOS 26.0, *)
enum AIAssistant {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static func checkGrammar(_ text: String) async throws -> GrammarOutcome {
        let input = AIPrompts.trimmedInput(text)
        let response = try await grammarResponse(input)
        return AIValidation.grammar(
            input: input,
            corrected: response.corrected,
            corrections: response.mistakes.map { GrammarCorrection(original: $0.original, fix: $0.fix, reason: $0.reason) }
        )
    }

    /// English → Japanese. Honorific isn't a translation style: translate politely, then use `rewrite`.
    static func translate(_ english: String, style: Politeness) async throws -> Translation? {
        let response = try await translationResponse(AIPrompts.trimmedInput(english), style: style)
        return AIValidation.translation(japanese: response.japanese, reading: response.reading)
    }

    static func rewrite(_ japanese: String, as target: Politeness) async throws -> String? {
        let input = AIPrompts.trimmedInput(japanese)
        let response = try await rewriteResponse(input, target: target)
        return AIValidation.rewrite(input: input, output: response.text)
    }

    static func explain(_ japanese: String) async throws -> Explanation? {
        let response = try await explanationResponse(AIPrompts.trimmedInput(japanese))
        return AIValidation.explanation(reading: response.reading, meaning: response.meaning, notes: response.notes)
    }

    static func rewriteEnglish(_ english: String, as style: EnglishStyle) async throws -> String? {
        let input = AIPrompts.trimmedInput(english)
        let response = try await englishRewriteResponse(input, style: style)
        return AIValidation.englishRewrite(input: input, output: response.text)
    }

    static func translateToEnglish(_ japanese: String) async throws -> String? {
        let response = try await englishTranslationResponse(AIPrompts.trimmedInput(japanese))
        return AIValidation.englishTranslation(response.english)
    }

    static func convertToKanji(_ hiragana: String) async throws -> String? {
        let input = AIPrompts.trimmedInput(hiragana)
        let response = try await conversionResponse(input)
        return AIValidation.kanjiConversion(input: input, output: response.converted)
    }

    // MARK: - Evaluation

    /// Runs one test case through the same code the keyboard uses, and scores it.
    static func evaluate(_ testCase: AIEvalCase) async -> AIEvalResult {
        let start = Date()
        var fields: [String: String] = [:]
        var raw = ""
        do {
            let input = testCase.input
            switch testCase.mode {
            case .grammar:
                let response = try await grammarResponse(input)
                raw = "corrected: \(response.corrected)\n" + response.mistakes
                    .map { "• \($0.original) → \($0.fix): \($0.reason)" }.joined(separator: "\n")
                let corrections = response.mistakes.map { GrammarCorrection(original: $0.original, fix: $0.fix, reason: $0.reason) }
                switch AIValidation.grammar(input: input, corrected: response.corrected, corrections: corrections) {
                case .noMistakes: fields["text"] = input
                case .corrected(let text, _): fields["text"] = text
                case .unreliable: break
                }
            case .translate:
                let response = try await translationResponse(input, style: testCase.style ?? .polite)
                raw = "\(response.japanese)\n\(response.reading)"
                if let translation = AIValidation.translation(japanese: response.japanese, reading: response.reading) {
                    fields["text"] = translation.japanese
                    fields["reading"] = translation.reading
                }
            case .politeness:
                let response = try await rewriteResponse(input, target: testCase.style ?? .polite)
                raw = response.text
                fields["text"] = AIValidation.rewrite(input: input, output: response.text)
            case .explain:
                let response = try await explanationResponse(input)
                raw = "\(response.reading)\n\(response.meaning)\n" + response.notes.joined(separator: "\n")
                if let explanation = AIValidation.explanation(reading: response.reading, meaning: response.meaning, notes: response.notes) {
                    fields["meaning"] = explanation.meaning
                    fields["reading"] = explanation.reading
                }
            case .kanji:
                let response = try await conversionResponse(input)
                raw = response.converted
                fields["text"] = AIValidation.kanjiConversion(input: input, output: response.converted)
            case .englishRewrite:
                let response = try await englishRewriteResponse(input, style: testCase.englishStyle ?? .formal)
                raw = response.text
                fields["text"] = AIValidation.englishRewrite(input: input, output: response.text)
            case .toEnglish:
                let response = try await englishTranslationResponse(input)
                raw = response.english
                fields["text"] = AIValidation.englishTranslation(response.english)
            }
        } catch {
            raw = "Error: \(error.localizedDescription)"
        }
        let output = AIEvalOutput(fields: fields)
        return AIEvalResult(
            testCase: testCase,
            output: output,
            raw: raw,
            seconds: Date().timeIntervalSince(start),
            failures: AIEvaluation.failures(for: testCase, output: output)
        )
    }

    // MARK: - Model calls

    private static func instructions(for prompt: AIPrompt) -> String {
        // Apple's advice for non-US locales: start the instructions with this exact phrase.
        let locale = Locale.current
        let localePhrase = Locale.Language(identifier: "en_US").isEquivalent(to: locale.language)
            ? ""
            : "The person's locale is \(locale.identifier).\n"
        return localePhrase + prompt.instructions
    }

    private static func options(maximumTokens: Int) -> GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maximumTokens)
    }

    /// Apple's safety filter stopped the text at every attempt.
    enum Failure: LocalizedError {
        case blockedBySafetyFilter

        var errorDescription: String? {
            "Apple's on-device safety filter stopped this text, even with relaxed settings. Switch to Claude below for this one."
        }
    }

    /// Asks the model for a structured answer.
    ///
    /// Apple's safety filter sometimes stops ordinary text (私は昨日学校を行きました。 was refused
    /// on an iPhone). Every mode only transforms the person's own text, which is what the
    /// permissive guardrails are for, so a refusal is retried with them: first asking for JSON in
    /// the same shape (they only cover plain-text answers), then, if that's stopped too and the
    /// mode allows it (`plain`), with short instructions and no examples, for the bare answer.
    private static func generate<Response: Generable>(
        _ prompt: AIPrompt, input: String, as type: Response.Type, maximumTokens: Int,
        plain: (instructions: String, make: (String) -> Response)? = nil
    ) async throws -> Response {
        do {
            return try await LanguageModelSession(instructions: instructions(for: prompt))
                .respond(to: AIPrompts.prompt(for: input), generating: type, options: options(maximumTokens: maximumTokens))
                .content
        } catch let error as LanguageModelSession.GenerationError where isSafetyStop(error) {
            let permissive = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            do {
                let session = LanguageModelSession(model: permissive, instructions: instructions(for: prompt) + """

                    Answer with JSON only, in the same shape as the examples, with every key in double quotes.
                    """)
                let answer = try await session
                    .respond(to: AIPrompts.prompt(for: input), options: options(maximumTokens: maximumTokens))
                    .content
                return try Response(GeneratedContent(json: jsonObject(in: answer)))
            } catch {
                guard let plain else { throw Failure.blockedBySafetyFilter }
                do {
                    let answer = try await LanguageModelSession(model: permissive, instructions: plain.instructions)
                        .respond(to: input, options: options(maximumTokens: maximumTokens))
                        .content
                    return plain.make(answer.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    throw Failure.blockedBySafetyFilter
                }
            }
        }
    }

    private static func isSafetyStop(_ error: LanguageModelSession.GenerationError) -> Bool {
        switch error {
        case .guardrailViolation, .refusal: return true
        default: return false
        }
    }

    /// The outermost {…} in an answer, without any text or code fences around it.
    private static func jsonObject(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }

    private static func grammarResponse(_ input: String) async throws -> GrammarResponse {
        let japanese = AIText.containsJapanese(input)
        return try await generate(AIPrompts.grammar(for: input), input: input, as: GrammarResponse.self, maximumTokens: 500,
                                  plain: (instructions: "Correct any grammar or spelling mistakes in this \(japanese ? "Japanese" : "English") text. "
                                            + "Change nothing else. Reply with only the corrected text.",
                                          make: { GrammarResponse(mistakes: [], corrected: $0) }))
    }

    private static func translationResponse(_ input: String, style: Politeness) async throws -> TranslationResponse {
        try await generate(AIPrompts.translate(style: style), input: input, as: TranslationResponse.self, maximumTokens: 300)
    }

    private static func rewriteResponse(_ input: String, target: Politeness) async throws -> RewriteResponse {
        let style = target == .casual ? "casual plain form" : target == .polite ? "polite です/ます form" : "respectful 敬語"
        return try await generate(AIPrompts.politeness(target), input: input, as: RewriteResponse.self, maximumTokens: 300,
                                  plain: (instructions: "Rewrite this Japanese text in \(style). Keep the meaning. Reply with only the rewritten text.",
                                          make: { RewriteResponse(text: $0) }))
    }

    private static func explanationResponse(_ input: String) async throws -> ExplanationResponse {
        try await generate(AIPrompts.explain, input: input, as: ExplanationResponse.self, maximumTokens: 400)
    }

    private static func englishRewriteResponse(_ input: String, style: EnglishStyle) async throws -> RewriteResponse {
        try await generate(AIPrompts.englishRewrite(style), input: input, as: RewriteResponse.self, maximumTokens: 300,
                           plain: (instructions: "Rewrite this English text to be \(style == .shorter ? "shorter" : style.rawValue). "
                                     + "Keep the meaning. Reply with only the rewritten text.",
                                   make: { RewriteResponse(text: $0) }))
    }

    private static func englishTranslationResponse(_ input: String) async throws -> EnglishTranslationResponse {
        try await generate(AIPrompts.toEnglish, input: input, as: EnglishTranslationResponse.self, maximumTokens: 300,
                           plain: (instructions: "Translate this Japanese text into natural English. Reply with only the translation.",
                                   make: { EnglishTranslationResponse(english: $0) }))
    }

    private static func conversionResponse(_ input: String) async throws -> ConversionResponse {
        try await generate(AIPrompts.kanji, input: input, as: ConversionResponse.self, maximumTokens: 200)
    }
}

#endif
