import XCTest
@testable import KeyboardCore

/// The prompts themselves can only be judged on a device (Settings → Apple Intelligence test →
/// Check the prompts). These tests make sure everything around them is sound: the prompts are
/// well-formed, the validation accepts good answers and rejects bad ones, and the test set
/// passes perfect answers and fails typical mistakes.
final class AIPromptTests: XCTestCase {
    private var allPrompts: [AIPrompt] {
        [AIPrompts.grammarJapanese, AIPrompts.grammarEnglish, AIPrompts.explain, AIPrompts.kanji]
            + [Politeness.casual, .polite].map { AIPrompts.translate(style: $0) }
            + Politeness.allCases.map { AIPrompts.politeness($0) }
    }

    // MARK: - Prompts

    func testPromptsAreShortAndHaveExamples() {
        XCTAssertEqual(Set(allPrompts.map(\.key)).count, allPrompts.count, "prompt keys must be unique")
        for prompt in allPrompts {
            // Apple: keep on-device prompts to one to three paragraphs, plus a few simple examples.
            XCTAssertLessThan(prompt.instructions.count, 1500, prompt.key)
            let examples = prompt.instructions.components(separatedBy: "\nText: ").count - 1
            XCTAssertGreaterThanOrEqual(examples, 2, "\(prompt.key) needs at least two examples")
            XCTAssertTrue(prompt.instructions.hasPrefix("You are"), "\(prompt.key) should give the model a role")
        }
    }

    func testCodeChoosesThePromptNotTheModel() {
        XCTAssertEqual(AIPrompts.grammar(for: "私は学生です。").id, "grammar-ja")
        XCTAssertEqual(AIPrompts.grammar(for: "I am a student.").id, "grammar-en")
        XCTAssertTrue(AIPrompts.translate(style: .casual).instructions.contains("casual"))
        XCTAssertTrue(AIPrompts.translate(style: .polite).instructions.contains("です/ます"))
        XCTAssertTrue(AIPrompts.politeness(.honorific).instructions.contains("謙譲語"))
    }

    func testGrammarPromptsIncludeNoChangeExamples() {
        // Small models over-correct; showing correct text left alone counters that.
        for prompt in [AIPrompts.grammarJapanese, AIPrompts.grammarEnglish] {
            XCTAssertTrue(prompt.instructions.contains("{mistakes: [], corrected:"), prompt.key)
        }
    }

    func testTranslationPromptsShowARequestBeingTranslatedNotObeyed() {
        for style in [Politeness.casual, .polite] {
            XCTAssertTrue(AIPrompts.translate(style: style).instructions.contains("Text: Tell me a joke."))
        }
    }

    func testTrimmedInputKeepsWholeSentences() {
        XCTAssertEqual(AIPrompts.trimmedInput("  短い文。 "), "短い文。")
        let long = String(repeating: "これは長い文です。", count: 60) + "最後の文です。"
        let trimmed = AIPrompts.trimmedInput(long, maxCharacters: 40)
        XCTAssertLessThanOrEqual(trimmed.count, 40)
        XCTAssertTrue(trimmed.hasPrefix("これは"), "should start at a sentence boundary: \(trimmed)")
        XCTAssertTrue(trimmed.hasSuffix("最後の文です。"))
        XCTAssertEqual(AIPrompts.prompt(for: "猫"), "Text: 猫")
    }

    // MARK: - Validation

    func testGrammarValidation() {
        XCTAssertEqual(AIValidation.grammar(input: "東京に住んでいます。", corrected: "東京に住んでいます", corrections: []), .noMistakes)
        XCTAssertEqual(
            AIValidation.grammar(
                input: "図書館に勉強します。",
                corrected: "図書館で勉強します。",
                corrections: [
                    GrammarCorrection(original: "図書館に", fix: "図書館で", reason: "で marks where an action happens."),
                    GrammarCorrection(original: "学校を", fix: "学校に", reason: "Invented: not in the text."),
                ]
            ),
            .corrected(text: "図書館で勉強します。", corrections: [
                GrammarCorrection(original: "図書館に", fix: "図書館で", reason: "で marks where an action happens."),
            ])
        )
        // Rewriting or translating instead of fixing is rejected.
        XCTAssertEqual(AIValidation.grammar(input: "東京に住んでいます。", corrected: "私は東京で暮らしていて、毎日楽しいです。", corrections: []), .unreliable)
        XCTAssertEqual(AIValidation.grammar(input: "東京に住んでいます。", corrected: "I live in Tokyo.", corrections: []), .unreliable)
    }

    func testKanjiConversionValidation() {
        XCTAssertEqual(AIValidation.kanjiConversion(input: "わたしはきのうがっこうにいきました", output: "私は昨日学校に行きました"), "私は昨日学校に行きました")
        XCTAssertEqual(AIValidation.kanjiConversion(input: "こーひーをのみたいです", output: "コーヒーを飲みたいです"), "コーヒーを飲みたいです")
        XCTAssertNil(AIValidation.kanjiConversion(input: "これはなんですか", output: "これはペンです"), "answered")
        XCTAssertNil(AIValidation.kanjiConversion(input: "ありがとうございます", output: "Thank you"), "translated")
        XCTAssertNil(AIValidation.kanjiConversion(input: "ねこ", output: "猫が好きです"), "added text")
    }

    func testOtherValidation() {
        XCTAssertEqual(AIValidation.translation(japanese: "駅はどこですか。", reading: "えきはどこですか。"),
                       Translation(japanese: "駅はどこですか。", reading: "えきはどこですか。"))
        XCTAssertNil(AIValidation.translation(japanese: "Where is the station?", reading: ""))
        XCTAssertNil(AIValidation.translation(japanese: "駅はどこですか。", reading: "駅はどこ")?.reading, "kanji in a reading")
        XCTAssertNil(AIValidation.rewrite(input: "資料を見ました。", output: "I saw the documents."))
        XCTAssertNil(AIValidation.rewrite(input: "資料を見ました。", output: "資料を見ました。"), "nothing changed")
        XCTAssertNil(AIValidation.explanation(reading: "ねこ", meaning: "ねこです", notes: []), "meaning must be English")
        XCTAssertEqual(AIValidation.explanation(reading: "ねこ", meaning: "Cat", notes: ["a", "b", "c", "d"])?.notes.count, 3)
    }

    func testPromptExamplesPassValidation() {
        // Otherwise the model would be taught to produce answers the keyboard then throws away.
        XCTAssertNotEqual(AIValidation.grammar(input: "週末は海を行きました。", corrected: "週末は海に行きました。", corrections: []), .unreliable)
        XCTAssertNotEqual(AIValidation.grammar(input: "先週はとても忙しいでした。", corrected: "先週はとても忙しかったです。", corrections: []), .unreliable)
        XCTAssertNotNil(AIValidation.kanjiConversion(input: "ぱんとぎゅうにゅうをかいます", output: "パンと牛乳を買います"))
        XCTAssertNotNil(AIValidation.kanjiConversion(input: "よろしくおねがいします", output: "よろしくお願いします"))
        XCTAssertNotNil(AIValidation.rewrite(input: "社長は何時に来ますか。", output: "社長は何時にいらっしゃいますか。"))
        XCTAssertNotNil(AIValidation.translation(japanese: "トイレどこ？", reading: "といれどこ？")?.reading)
    }

    // MARK: - Test set

    func testEvaluationCasesAreWellFormed() {
        XCTAssertGreaterThanOrEqual(AIEvaluation.cases.count, 30)
        for mode in AIMode.allCases {
            XCTAssertGreaterThanOrEqual(AIEvaluation.cases.filter { $0.mode == mode }.count, 3, "\(mode) needs test cases")
        }
        for testCase in AIEvaluation.cases {
            XCTAssertFalse(testCase.expectations.isEmpty, testCase.input)
            // A case copied from a prompt's examples would test copying, not the prompt.
            XCTAssertFalse(allPrompts.contains { $0.instructions.contains(testCase.input) }, "\(testCase.input) is a prompt example")
        }
        // Grammar must be tested on correct sentences too, in both languages.
        let unchanged = AIEvaluation.cases.filter { $0.mode == .grammar && $0.expectations.contains(where: \.unchanged) }
        XCTAssertTrue(unchanged.contains { AIText.containsJapanese($0.input) })
        XCTAssertTrue(unchanged.contains { !AIText.containsJapanese($0.input) })
    }

    private func output(_ fields: [String: String]) -> AIEvalOutput {
        AIEvalOutput(fields: fields)
    }

    private func testCase(_ input: String) -> AIEvalCase {
        AIEvaluation.cases.first { $0.input == input }!
    }

    func testPerfectAnswersPass() {
        let answers: [String: [String: String]] = [
            "私は昨日学校を行きました。": ["text": "私は昨日学校に行きました。"],
            "東京に住んでいます。": ["text": "東京に住んでいます。"],
            "She don't like coffee.": ["text": "She doesn't like coffee."],
            "What is the capital of France?": ["text": "フランスの首都はどこですか。"],
            "Do you want to get dinner tomorrow?": ["text": "明日、晩ご飯食べに行かない？"],
            "部長はもう帰りましたか。": ["text": "部長はもうお帰りになりましたか。"],
            "今日は暑いですね。": ["text": "今日は暑いね。"],
            "猫が好きです。": ["meaning": "I like cats.", "reading": "ねこがすきです。"],
            "わたしはきのうがっこうにいきました": ["text": "私は昨日学校に行きました"],
            "ありがとうございます": ["text": "ありがとうございます"],
        ]
        for (input, fields) in answers {
            XCTAssertEqual(AIEvaluation.failures(for: testCase(input), output: output(fields)), [], input)
        }
    }

    func testTypicalMistakesFail() {
        let answers: [String: [String: String]] = [
            "東京に住んでいます。": ["text": "私は東京に住んでいます。"],          // over-correction
            "My favourite colour is green.": ["text": "My favorite color is green."],
            "What is the capital of France?": ["text": "パリです。"],              // answered
            "Do you want to get dinner tomorrow?": ["text": "明日、夕食に行きませんか。"],
            "資料を見ました。": ["text": "資料をご覧になりました。"],             // 尊敬語 for your own action
            "猫が好きです。": ["meaning": "Cats are animals.", "reading": "ねこがすきです。"],
            "ありがとうございます": ["text": "有難うございます"],
            "これはなんですか": [:],                                                // rejected by validation
        ]
        for (input, fields) in answers {
            XCTAssertFalse(AIEvaluation.failures(for: testCase(input), output: output(fields)).isEmpty, input)
        }
    }
}
