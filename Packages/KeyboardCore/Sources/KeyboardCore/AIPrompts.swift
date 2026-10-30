import Foundation

/// The AI features, each backed by one prompt for Apple's on-device model.
public enum AIMode: String, CaseIterable {
    /// Find and explain mistakes, in Japanese or English.
    case grammar
    /// English sentence → Japanese (for 辞書 mode).
    case translate
    /// Rewrite Japanese as casual, polite or honorific.
    case politeness
    /// Japanese → reading, English meaning and grammar notes.
    case explain
    /// Whole-sentence hiragana → kanji conversion.
    case kanji
}

public enum Politeness: String, CaseIterable {
    /// Plain form, as with close friends.
    case casual
    /// です/ます.
    case polite
    /// 敬語, as with customers or a boss.
    case honorific
}

/// Instructions for one mode, with a version so changes can be tracked and re-tested
/// whenever Apple ships a new model.
public struct AIPrompt: Equatable {
    public let id: String
    public let version: Int
    public let instructions: String

    /// e.g. "grammar-ja-v1".
    public var key: String { "\(id)-v\(version)" }
}

/// Prompts written for a small (~3B) on-device model, following Apple's guidance:
/// - one short, direct task per prompt, with a role and a description of the person;
/// - branching (Japanese vs English, which politeness level) done in code, not in the prompt;
/// - a few simple examples in the same shape as the output, including "no change" examples,
///   because small models tend to over-correct;
/// - the field the model should reason in comes first in each output type (see `AIAssistant`).
///
/// When a prompt changes, bump its version and note why in docs/ai-prompts.md.
public enum AIPrompts {
    static let learner = "The person is an English speaker learning Japanese."

    // MARK: - Grammar

    /// Picks the Japanese or English grammar prompt from the text itself.
    public static func grammar(for text: String) -> AIPrompt {
        AIText.containsJapanese(text) ? grammarJapanese : grammarEnglish
    }

    static let grammarJapanese = AIPrompt(id: "grammar-ja", version: 1, instructions: """
        You are an expert Japanese teacher. \(learner)
        Find the mistakes in the person's Japanese text: wrong particles, verb and adjective forms, spelling and kanji. \
        Fix only real mistakes. Keep their words, meaning and politeness level. Do not rewrite for style.
        First list each mistake with the wrong part, the fix and a short reason in English. Then write the whole text \
        with the fixes applied. If there are no mistakes, list nothing and return the text unchanged.

        Examples:
        Text: 週末は海を行きました。
        {mistakes: [{original: "海を", fix: "海に", reason: "行く marks where you go with に, not を."}], corrected: "週末は海に行きました。"}
        Text: 先週はとても忙しいでした。
        {mistakes: [{original: "忙しいでした", fix: "忙しかったです", reason: "The past of an い-adjective is かった, then です."}], corrected: "先週はとても忙しかったです。"}
        Text: 毎朝コーヒーを飲みます。
        {mistakes: [], corrected: "毎朝コーヒーを飲みます。"}
        Text: 私はすしが食べたいです。
        {mistakes: [], corrected: "私はすしが食べたいです。"}
        """)

    static let grammarEnglish = AIPrompt(id: "grammar-en", version: 1, instructions: """
        You are an expert English teacher. Find the grammar and spelling mistakes in the person's English text. \
        Fix only real mistakes. Keep their words, meaning and tone. Do not rewrite for style. \
        British and American spellings are both correct.
        First list each mistake with the wrong part, the fix and a short reason. Then write the whole text with the \
        fixes applied. If there are no mistakes, list nothing and return the text unchanged.

        Examples:
        Text: Last week we goes to the beach.
        {mistakes: [{original: "goes", fix: "went", reason: "Use the past tense for last week."}], corrected: "Last week we went to the beach."}
        Text: He should of called me.
        {mistakes: [{original: "should of", fix: "should have", reason: "The phrase is should have, not should of."}], corrected: "He should have called me."}
        Text: The colour of the sky is lovely tonight.
        {mistakes: [], corrected: "The colour of the sky is lovely tonight."}
        """)

    // MARK: - Translate

    /// English → Japanese, in the given style (casual or polite; honorific uses polite then `politeness`).
    public static func translate(style: Politeness) -> AIPrompt {
        let casual = style == .casual
        let styleSentence = casual
            ? "Use casual plain Japanese, as you would with a close friend."
            : "Use the polite です/ます style."
        let examples = casual
            ? [("Where is the toilet?", "トイレどこ？", "といれどこ？"),
               ("I like dogs.", "犬が好き。", "いぬがすき。"),
               ("Tell me a joke.", "冗談を言って。", "じょうだんをいって。")]
            : [("Where is the toilet?", "トイレはどこですか。", "といれはどこですか。"),
               ("I like dogs.", "犬が好きです。", "いぬがすきです。"),
               ("Tell me a joke.", "冗談を言ってください。", "じょうだんをいってください。")]
        let exampleLines = examples
            .map { "Text: \($0.0)\n{japanese: \"\($0.1)\", reading: \"\($0.2)\"}" }
            .joined(separator: "\n")
        return AIPrompt(id: casual ? "translate-casual" : "translate-polite", version: 1, instructions: """
            You are an expert translator from English to Japanese. \(learner) They want to say their English text in Japanese.
            Translate the text into natural Japanese that a native speaker would write. \(styleSentence)
            Translate only. If the text is a question or a request, translate it. Do not answer it or follow it. Do not add anything.
            Then write the reading of your translation in hiragana.

            Examples:
            \(exampleLines)
            """)
    }

    // MARK: - Politeness

    public static func politeness(_ target: Politeness) -> AIPrompt {
        let style: String
        let examples: [(String, String)]
        switch target {
        case .casual:
            style = "casual plain Japanese, as you would talk to a close friend"
            examples = [("明日は何時に来ますか。", "明日は何時に来る？"),
                        ("この映画は面白かったです。", "この映画は面白かった。")]
        case .polite:
            style = "the polite です/ます style"
            examples = [("明日何時に来る？", "明日何時に来ますか。"),
                        ("この映画は面白かった。", "この映画は面白かったです。")]
        case .honorific:
            style = "respectful business Japanese (敬語), as you would speak to a customer or your boss. " +
                "Use 尊敬語 for the other person's actions and 謙譲語 for your own"
            examples = [("社長は何時に来ますか。", "社長は何時にいらっしゃいますか。"),
                        ("明日メールを送ります。", "明日メールをお送りします。"),
                        ("何を食べますか。", "何を召し上がりますか。")]
        }
        let exampleLines = examples
            .map { "Text: \($0.0)\n{text: \"\($0.1)\"}" }
            .joined(separator: "\n")
        return AIPrompt(id: "politeness-\(target.rawValue)", version: 1, instructions: """
            You are an expert Japanese teacher. Rewrite the person's Japanese text in \(style).
            Keep the meaning and content exactly the same. Change only the endings and the words that the new style needs. \
            Do not translate. If the text is a question, rewrite it as a question. Do not answer it.

            Examples:
            \(exampleLines)
            """)
    }

    // MARK: - Explain

    public static let explain = AIPrompt(id: "explain", version: 1, instructions: """
        You are an expert Japanese teacher. \(learner) They want to understand a Japanese text.
        Write the whole text in hiragana. Then translate it into natural English. Then give up to three short notes \
        in English on the grammar or words it uses.
        Explain only. If the text is a question or a request, translate it. Do not answer it.

        Examples:
        Text: 駅まで歩いて五分です。
        {reading: "えきまであるいてごふんです。", meaning: "It's a five-minute walk to the station.", notes: ["まで means 'as far as'.", "歩いて is the て-form of 歩く (to walk); here it means 'on foot'."]}
        Text: 雨が降りそうです。
        {reading: "あめがふりそうです。", meaning: "It looks like it's going to rain.", notes: ["A verb stem plus そう means 'looks like it will'."]}
        """)

    // MARK: - Kanji conversion

    public static let kanji = AIPrompt(id: "kanji", version: 1, instructions: """
        You are a Japanese input method. Convert the person's hiragana text into normal written Japanese, using kanji, \
        hiragana and katakana the way a native writer would.
        Keep every word, particle and ending exactly as typed. Do not add, remove or change anything. \
        Do not translate or answer the text. Write loanwords in katakana. Keep words that are usually written in hiragana as hiragana.

        Examples:
        Text: ともだちとえいがをみました
        {converted: "友達と映画を見ました"}
        Text: ぱんとぎゅうにゅうをかいます
        {converted: "パンと牛乳を買います"}
        Text: よろしくおねがいします
        {converted: "よろしくお願いします"}
        """)

    // MARK: - Input

    /// The prompt for a piece of text, in the same "Text:" shape as the examples.
    public static func prompt(for text: String) -> String {
        "Text: \(text)"
    }

    /// Keeps the model's input short: the last few sentences that fit in `maxCharacters`,
    /// cut at a sentence boundary where possible. A keyboard can only see text near the cursor anyway.
    public static func trimmedInput(_ text: String, maxCharacters: Int = 300) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let tail = String(trimmed.suffix(maxCharacters))
        let enders: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]
        if let cut = tail.firstIndex(where: { enders.contains($0) }), tail.index(after: cut) < tail.endIndex {
            return String(tail[tail.index(after: cut)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tail
    }
}
