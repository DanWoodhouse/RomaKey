import XCTest
@testable import KeyboardCore

/// A few real JMdict lines, in frequency order, so the tests don't depend on the full file.
enum SampleDictionary {
    static let tsv = [
        "猫\tねこ\t0\tnoun\tcat (esp. the domestic cat, Felis catus) | shamisen",
        "食べる\tたべる\t0\tverb\tto eat | to live on (e.g. a salary); to live off",
        "\tどうも\t1\tinterjection\tthank you; thanks | much (thanks); very (sorry)",
        "犬\tいぬ\t0\tnoun\tdog (Canis (lupus) familiaris) | squealer; rat; snitch",
        "\tコーヒー\t1\tnoun\tcoffee",
        "戌\tいぬ\t0\tnoun\tthe Dog (eleventh sign of the Chinese zodiac) | west-northwest",
        "有り難う\tありがとう\t1\tinterjection\tthank you; thanks",
        "種類\tしゅるい\t0\tnoun\tvariety; kind; type; category",
    ].joined(separator: "\n")
}

final class JapaneseDictionaryTests: XCTestCase {
    private let dictionary = JapaneseDictionary(tsv: SampleDictionary.tsv)

    func testEntryForms() {
        let thanks = dictionary.entries(reading: "ありがとう")[0]
        XCTAssertEqual(thanks.word, "ありがとう")  // usually written in kana
        XCTAssertEqual(thanks.kanji, "有り難う")
        XCTAssertEqual(dictionary.entries(reading: "ねこ")[0].word, "猫")
        XCTAssertEqual(dictionary.entries(reading: "ねこ")[0].senses[0][0], "cat (esp. the domestic cat, Felis catus)")
    }

    func testEnglishSearchPrefersMainMeaning() {
        XCTAssertEqual(dictionary.search(english: "dog").map(\.word), ["犬", "戌"])
        XCTAssertEqual(dictionary.search(english: "eat").first?.word, "食べる")
        XCTAssertEqual(dictionary.search(english: "Thank you").map(\.word), ["どうも", "ありがとう"])
    }

    func testEnglishSearchMatchesWhileTyping() {
        // "ca" already finds cat; exact words beat longer ones ("category").
        XCTAssertEqual(dictionary.search(english: "ca").first?.word, "猫")
        XCTAssertEqual(dictionary.search(english: "cat").first?.word, "猫")
        XCTAssertEqual(dictionary.search(english: "categ").first?.word, "種類")
        XCTAssertTrue(dictionary.search(english: "zzz").isEmpty)
    }

    func testReadingLookup() {
        XCTAssertEqual(dictionary.entries(reading: "いぬ").map(\.word), ["犬", "戌"])
        // Katakana words are found from hiragana input.
        XCTAssertEqual(dictionary.entries(reading: "こーひー").map(\.word), ["コーヒー"])
        XCTAssertEqual(dictionary.predictions(readingPrefix: "た").map(\.word), ["食べる"])
        XCTAssertTrue(dictionary.predictions(readingPrefix: "たべる").isEmpty)
    }

    func testNormalize() {
        XCTAssertEqual(JapaneseDictionary.normalize("To eat (something)"), "eat")
        XCTAssertEqual(JapaneseDictionary.normalize("dog (Canis (lupus) familiaris)"), "dog")
        XCTAssertEqual(JapaneseDictionary.normalize("  the   Dog "), "dog")
    }

    func testBundledDictionary() throws {
        let bundled = try XCTUnwrap(JapaneseDictionary.bundled())
        XCTAssertGreaterThan(bundled.entries.count, 20_000)
        XCTAssertEqual(bundled.search(english: "cat").first?.word, "猫")
        XCTAssertEqual(bundled.search(english: "good morning").first?.word, "おはようございます")
        XCTAssertTrue(bundled.entries(reading: "ねこ").contains { $0.word == "猫" })
    }
}

final class KeyboardSettingsTests: XCTestCase {
    func testRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KeyboardSettingsTests-\(UUID())"))
        var settings = KeyboardSettings()
        settings.theme = .sakura
        settings.height = .tall
        settings.flickOnly = true
        settings.languageKeyModes = [.japanese, .dictionary]
        settings.startingMode = .lastUsed
        settings.theme = .custom
        settings.customColors.key = 0x123456
        settings.customColors.accent = 0xFF00AA
        settings.keyOpacity = 0.6
        settings.backgroundImageID = "photo-1"
        settings.backgroundDim = 0.5
        settings.backgroundBlur = true
        settings.autocorrect = false
        settings.emojiSuggestions = false
        settings.skinTone = 3
        settings.giphyAPIKey = "abc123"
        settings.gifRating = "g"
        settings.learningResetID = "reset-1"
        settings.save(to: defaults)
        XCTAssertEqual(KeyboardSettings(defaults: defaults), settings)

        settings.backgroundImageID = nil
        settings.save(to: defaults)
        XCTAssertNil(KeyboardSettings(defaults: defaults).backgroundImageID)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KeyboardSettingsTests-\(UUID())"))
        defaults.set(0.0, forKey: "keyOpacity")
        defaults.set(5.0, forKey: "backgroundDim")
        defaults.set(["key": 0x1000000, "text": 0x00FF00], forKey: "customColors")
        let settings = KeyboardSettings(defaults: defaults)
        XCTAssertEqual(settings.keyOpacity, 0.3)
        XCTAssertEqual(settings.backgroundDim, 0.8)
        // Invalid colours keep the default; valid ones are used.
        XCTAssertEqual(settings.customColors.key, KeyboardSettings().customColors.key)
        XCTAssertEqual(settings.customColors.text, 0x00FF00)
    }

    func testPresetPalettes() {
        for theme in KeyboardSettings.Theme.allCases {
            for dark in [false, true] {
                let colors = ThemePalette.colors(for: theme, dark: dark)
                XCTAssertNotEqual(colors.key, colors.text, "\(theme) keys and text must differ")
            }
        }
    }

    func testMissingValuesUseDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KeyboardSettingsTests-\(UUID())"))
        defaults.set("not-a-theme", forKey: "theme")
        defaults.set(["english"], forKey: "languageKeyModes")  // fewer than two: ignored
        let settings = KeyboardSettings(defaults: defaults)
        XCTAssertEqual(settings, KeyboardSettings())
    }

    func testLastUsedMode() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KeyboardSettingsTests-\(UUID())"))
        var settings = KeyboardSettings()
        settings.startingMode = .lastUsed
        settings.save(to: defaults)
        KeyboardSettings.saveLastUsedMode(.dictionary, to: defaults)
        XCTAssertEqual(KeyboardSettings(defaults: defaults).initialMode, .dictionary)
    }
}
