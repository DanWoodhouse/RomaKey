import XCTest
@testable import KeyboardCore

final class PredictionTests: XCTestCase {
    private let tsv = "thank\tyou the all\nso\ti am\nsee\tthe a"

    func testEnglishFromTheTable() {
        let predictor = NextWordPredictor(tsv: tsv, store: MemoryStore())
        XCTAssertEqual(predictor.english(after: "Thank"), ["you", "the", "all"])
        XCTAssertEqual(predictor.english(after: "so"), ["I", "am"])
        XCTAssertEqual(predictor.english(after: "zzz"), [])
    }

    func testLearnedPairsComeFirst() {
        let predictor = NextWordPredictor(tsv: tsv, store: MemoryStore())
        predictor.learn(previous: "see", next: "you")
        XCTAssertEqual(predictor.english(after: "see"), ["you", "the", "a"])
        predictor.reset()
        XCTAssertEqual(predictor.english(after: "see"), ["the", "a"])
    }

    func testJapaneseSuggestsParticlesAfterNouns() {
        let predictor = NextWordPredictor(store: MemoryStore())
        XCTAssertEqual(predictor.japanese(after: "猫"), ["は", "が", "を", "に", "の"])
        XCTAssertEqual(predictor.japanese(after: "コーヒー").first, "は")
        XCTAssertEqual(predictor.japanese(after: "たべる"), [])
        predictor.learn(previous: "猫", next: "が好き")
        XCTAssertEqual(predictor.japanese(after: "猫").first, "が好き")
    }

    func testBundledPairs() {
        let predictor = NextWordPredictor.bundled(store: MemoryStore())
        XCTAssertEqual(predictor.english(after: "thank").first, "you")
        XCTAssertEqual(predictor.english(after: "going").first, "to")
    }

    // MARK: - In the engine

    private func makeEngine(mode: InputMode) -> (KeyboardEngine, RecordingOutput) {
        let output = RecordingOutput()
        let engine = KeyboardEngine(mode: mode)
        engine.settings.autoCapitalization = false
        engine.output = output
        engine.predictor = NextWordPredictor(tsv: tsv, store: MemoryStore())
        return (engine, output)
    }

    private func type(_ text: String, into engine: KeyboardEngine) {
        for character in text {
            engine.press(character == " " ? .space : .character(String(character)))
        }
    }

    func testEnglishPredictionsAfterASpace() {
        let (engine, output) = makeEngine(mode: .english)
        type("thank ", into: engine)
        XCTAssertEqual(engine.candidates.map(\.text), ["you", "the", "all"])
        XCTAssertEqual(engine.candidates.first?.kind, .prediction)
        engine.selectCandidate(engine.candidates[0])
        XCTAssertEqual(output.committed, "thank you ")
    }

    func testEnglishLearnsWhatYouType() {
        let (engine, _) = makeEngine(mode: .english)
        type("see you later see ", into: engine)
        XCTAssertEqual(engine.candidates.first?.text, "you")
    }

    func testPredictiveTextCanBeTurnedOff() {
        let (engine, _) = makeEngine(mode: .english)
        engine.settings.predictiveText = false
        type("thank ", into: engine)
        XCTAssertEqual(engine.candidates, [])
    }

    func testJapaneseLearnsTheNextWord() {
        let (engine, output) = makeEngine(mode: .japanese)
        type("neko", into: engine)
        engine.press(.returnKey)
        type("ga", into: engine)
        engine.press(.returnKey)
        type("neko", into: engine)
        engine.press(.returnKey)
        XCTAssertEqual(output.committed, "ねこがねこ")
        XCTAssertEqual(engine.candidates.map(\.text), ["が"])
        engine.selectCandidate(engine.candidates[0])
        XCTAssertEqual(output.committed, "ねこがねこが")
    }
}
