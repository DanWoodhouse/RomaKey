import XCTest
@testable import KeyboardCore

final class RomajiComposerTests: XCTestCase {
    private func convert(_ romaji: String) -> String {
        var composer = RomajiComposer()
        for character in romaji {
            composer.input(character)
        }
        return composer.finalizedText
    }

    func testBasicSyllables() {
        XCTAssertEqual(convert("aiueo"), "あいうえお")
        XCTAssertEqual(convert("sushi"), "すし")
        XCTAssertEqual(convert("tsukue"), "つくえ")
        XCTAssertEqual(convert("kyouto"), "きょうと")
        XCTAssertEqual(convert("shashin"), "しゃしん")
        XCTAssertEqual(convert("fujisan"), "ふじさん")
        XCTAssertEqual(convert("arigatou"), "ありがとう")
    }

    func testN() {
        XCTAssertEqual(convert("konnichiha"), "こんにちは")
        XCTAssertEqual(convert("konnnichiha"), "こんにちは")
        XCTAssertEqual(convert("minna"), "みんな")
        XCTAssertEqual(convert("sanpo"), "さんぽ")
        XCTAssertEqual(convert("sannpo"), "さんぽ")
        XCTAssertEqual(convert("konnyaku"), "こんにゃく")
        XCTAssertEqual(convert("kin'en"), "きんえん")
        XCTAssertEqual(convert("hon"), "ほん")
        XCTAssertEqual(convert("honn"), "ほん")
    }

    func testSmallTsu() {
        XCTAssertEqual(convert("kitte"), "きって")
        XCTAssertEqual(convert("zasshi"), "ざっし")
        XCTAssertEqual(convert("matcha"), "まっちゃ")
        XCTAssertEqual(convert("xtu"), "っ")
    }

    func testLongVowelAndPunctuation() {
        XCTAssertEqual(convert("ra-men"), "らーめん")
        XCTAssertEqual(convert("hai,sou."), "はい、そう。")
    }

    func testDisplayTextShowsPendingRomaji() {
        var composer = RomajiComposer()
        "kak".forEach { composer.input($0) }
        XCTAssertEqual(composer.displayText, "かk")
        composer.input("n")
        XCTAssertEqual(composer.displayText, "かkn")
    }

    func testDeleteRemovesPendingRomajiFirst() {
        var composer = RomajiComposer()
        "kaky".forEach { composer.input($0) }
        composer.deleteBackward()
        XCTAssertEqual(composer.displayText, "かk")
        composer.deleteBackward()
        composer.deleteBackward()
        XCTAssertTrue(composer.isEmpty)
    }

    func testKatakana() {
        XCTAssertEqual(KanaConverter.katakana(from: "らーめん"), "ラーメン")
        XCTAssertEqual(KanaConverter.katakana(from: "ゔぁいおりん"), "ヴァイオリン")
    }

    func testKanaToRomaji() {
        let cases = [
            "ねこ": "neko", "がっこう": "gakkou", "きっぷ": "kippu", "しゃしん": "shashin",
            "きんえん": "kin'en", "ほんや": "hon'ya", "コーヒー": "koohii", "まっちゃ": "matcha",
            "ちょっと": "chotto", "ファン": "fan", "こんにちは": "konnichiha", "猫": "猫",
        ]
        for (kana, romaji) in cases {
            XCTAssertEqual(KanaConverter.romaji(from: kana), romaji, kana)
        }
    }
}
