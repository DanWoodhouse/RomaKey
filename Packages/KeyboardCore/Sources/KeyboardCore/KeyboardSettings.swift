import Foundation

/// Everything the user can customise. Edited in the app, read by both keyboards through a
/// shared App Group (which needs Full Access to be turned on for the keyboard).
public struct KeyboardSettings: Equatable {
    public static let appGroup = "group.com.danwoodhouse.JapaneseKeyboard"

    public enum StartingMode: String, CaseIterable {
        case japanese
        case english
        case dictionary
        case lastUsed
    }

    public enum FlickSensitivity: String, CaseIterable {
        case gentle
        case normal
        case quick

        /// How far (in points) the finger must slide before it counts as a flick.
        public var threshold: Double {
            switch self {
            case .gentle: return 30
            case .normal: return 20
            case .quick: return 12
            }
        }
    }

    public enum Theme: String, CaseIterable {
        case system
        case ai
        case sakura
        case matcha
        case sumi
        /// The user's own colours, from `customColors`.
        case custom
    }

    public enum Height: String, CaseIterable {
        case compact
        case standard
        case tall
    }

    // ローマ字 keyboard
    public var startingMode: StartingMode = .japanese
    /// The modes the language key steps through, in あ → EN → 辞 order.
    public var languageKeyModes: [InputMode] = InputMode.allCases
    public var autoCapitalization = true
    public var doubleSpacePeriod = true
    public var keyPopups = true
    /// Hold q–p on the letters page for 1–0. The keys show the numbers as small hints.
    public var holdForNumbers = true
    /// Mirrors the mode wheel (→ あ … ← 🌐) for typing with the left thumb.
    public var leftHandedWheel = false

    // かな keyboard
    /// Turns off tap-to-cycle, so tapping あ twice types ああ.
    public var flickOnly = false
    public var flickSensitivity: FlickSensitivity = .normal

    // Both
    public var showMeanings = true
    /// Romaji after kana readings in suggestions and dictionary entries (ねこ neko), for learners.
    public var showRomaji = false
    public var fullWidthSpace = false
    public var spaceBarCursor = true
    public var keySounds = true
    /// Needs Full Access.
    public var haptics = false
    public var theme: Theme = .system
    public var height: Height = .standard

    // Suggestions
    public var autocorrect = true
    public var wordSuggestions = true
    public var emojiSuggestions = true
    /// Likely next words after a word is finished.
    public var predictiveText = true

    // Emoji and GIFs
    /// 0 = default yellow, 1–5 = light to dark.
    public var skinTone = 0
    /// Your own GIPHY API key. Empty turns GIF search off. Needs Full Access.
    public var giphyAPIKey = ""
    /// GIPHY content rating: g, pg, pg-13 or r.
    public var gifRating = "pg"
    /// The app changes this to ask the keyboards to forget learned words and choices.
    public var learningResetID: String?

    // Custom look
    /// Used when `theme` is `.custom`. The same colours in light and dark mode.
    public var customColors = ThemePalette.colors(for: .ai, dark: false)
    /// 0.3–1. Below 1, a background image shows through the keys.
    public var keyOpacity = 1.0
    /// Changes whenever the app saves a new background image; nil means no image.
    public var backgroundImageID: String?
    /// 0–0.8: how much the background image is darkened, to keep labels readable.
    public var backgroundDim = 0.2
    public var backgroundBlur = false

    /// Written by the keyboard, for `StartingMode.lastUsed`.
    public var lastUsedMode: InputMode = .japanese

    public init() {}

    /// The mode the ローマ字 keyboard opens in.
    public var initialMode: InputMode {
        switch startingMode {
        case .japanese: return .japanese
        case .english: return .english
        case .dictionary: return .dictionary
        case .lastUsed: return lastUsedMode
        }
    }

    // MARK: - Storage

    private enum Key {
        static let startingMode = "startingMode"
        static let languageKeyModes = "languageKeyModes"
        static let autoCapitalization = "autoCapitalization"
        static let doubleSpacePeriod = "doubleSpacePeriod"
        static let keyPopups = "keyPopups"
        static let holdForNumbers = "holdForNumbers"
        static let leftHandedWheel = "leftHandedWheel"
        static let showRomaji = "showRomaji"
        static let flickOnly = "flickOnly"
        static let flickSensitivity = "flickSensitivity"
        static let showMeanings = "showMeanings"
        static let fullWidthSpace = "fullWidthSpace"
        static let spaceBarCursor = "spaceBarCursor"
        static let keySounds = "keySounds"
        static let haptics = "haptics"
        static let theme = "theme"
        static let height = "height"
        static let autocorrect = "autocorrect"
        static let wordSuggestions = "wordSuggestions"
        static let emojiSuggestions = "emojiSuggestions"
        static let predictiveText = "predictiveText"
        static let skinTone = "skinTone"
        static let giphyAPIKey = "giphyAPIKey"
        static let gifRating = "gifRating"
        static let learningResetID = "learningResetID"
        static let customColors = "customColors"
        static let keyOpacity = "keyOpacity"
        static let backgroundImageID = "backgroundImageID"
        static let backgroundDim = "backgroundDim"
        static let backgroundBlur = "backgroundBlur"
        static let lastUsedMode = "lastUsedMode"
    }

    /// Reads saved settings, using the default for anything missing or unreadable.
    public init(defaults: UserDefaults) {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func number(_ key: String, _ fallback: Double, in range: ClosedRange<Double>) -> Double {
            guard let saved = defaults.object(forKey: key) as? Double else { return fallback }
            return min(max(saved, range.lowerBound), range.upperBound)
        }

        startingMode = value(Key.startingMode, startingMode)
        if let modes = defaults.stringArray(forKey: Key.languageKeyModes) {
            let enabled = InputMode.allCases.filter { modes.contains($0.rawValue) }
            if enabled.count >= 2 {
                languageKeyModes = enabled
            }
        }
        autoCapitalization = bool(Key.autoCapitalization, autoCapitalization)
        doubleSpacePeriod = bool(Key.doubleSpacePeriod, doubleSpacePeriod)
        keyPopups = bool(Key.keyPopups, keyPopups)
        holdForNumbers = bool(Key.holdForNumbers, holdForNumbers)
        leftHandedWheel = bool(Key.leftHandedWheel, leftHandedWheel)
        showRomaji = bool(Key.showRomaji, showRomaji)
        flickOnly = bool(Key.flickOnly, flickOnly)
        flickSensitivity = value(Key.flickSensitivity, flickSensitivity)
        showMeanings = bool(Key.showMeanings, showMeanings)
        fullWidthSpace = bool(Key.fullWidthSpace, fullWidthSpace)
        spaceBarCursor = bool(Key.spaceBarCursor, spaceBarCursor)
        keySounds = bool(Key.keySounds, keySounds)
        haptics = bool(Key.haptics, haptics)
        theme = value(Key.theme, theme)
        height = value(Key.height, height)
        autocorrect = bool(Key.autocorrect, autocorrect)
        wordSuggestions = bool(Key.wordSuggestions, wordSuggestions)
        emojiSuggestions = bool(Key.emojiSuggestions, emojiSuggestions)
        predictiveText = bool(Key.predictiveText, predictiveText)
        skinTone = min(max(defaults.object(forKey: Key.skinTone) as? Int ?? skinTone, 0), 5)
        giphyAPIKey = defaults.string(forKey: Key.giphyAPIKey) ?? giphyAPIKey
        gifRating = ["g", "pg", "pg-13", "r"].contains(defaults.string(forKey: Key.gifRating) ?? "")
            ? defaults.string(forKey: Key.gifRating)! : gifRating
        learningResetID = defaults.string(forKey: Key.learningResetID)
        if let saved = defaults.dictionary(forKey: Key.customColors) as? [String: Int] {
            customColors = ThemeColors(dictionary: saved, fallback: customColors)
        }
        keyOpacity = number(Key.keyOpacity, keyOpacity, in: 0.3...1)
        backgroundImageID = defaults.string(forKey: Key.backgroundImageID)
        backgroundDim = number(Key.backgroundDim, backgroundDim, in: 0...0.8)
        backgroundBlur = bool(Key.backgroundBlur, backgroundBlur)
        lastUsedMode = value(Key.lastUsedMode, lastUsedMode)
    }

    /// Saves everything the user edits in the app.
    public func save(to defaults: UserDefaults) {
        defaults.set(startingMode.rawValue, forKey: Key.startingMode)
        defaults.set(languageKeyModes.map(\.rawValue), forKey: Key.languageKeyModes)
        defaults.set(autoCapitalization, forKey: Key.autoCapitalization)
        defaults.set(doubleSpacePeriod, forKey: Key.doubleSpacePeriod)
        defaults.set(keyPopups, forKey: Key.keyPopups)
        defaults.set(holdForNumbers, forKey: Key.holdForNumbers)
        defaults.set(leftHandedWheel, forKey: Key.leftHandedWheel)
        defaults.set(showRomaji, forKey: Key.showRomaji)
        defaults.set(flickOnly, forKey: Key.flickOnly)
        defaults.set(flickSensitivity.rawValue, forKey: Key.flickSensitivity)
        defaults.set(showMeanings, forKey: Key.showMeanings)
        defaults.set(fullWidthSpace, forKey: Key.fullWidthSpace)
        defaults.set(spaceBarCursor, forKey: Key.spaceBarCursor)
        defaults.set(keySounds, forKey: Key.keySounds)
        defaults.set(haptics, forKey: Key.haptics)
        defaults.set(theme.rawValue, forKey: Key.theme)
        defaults.set(height.rawValue, forKey: Key.height)
        defaults.set(autocorrect, forKey: Key.autocorrect)
        defaults.set(wordSuggestions, forKey: Key.wordSuggestions)
        defaults.set(emojiSuggestions, forKey: Key.emojiSuggestions)
        defaults.set(predictiveText, forKey: Key.predictiveText)
        defaults.set(skinTone, forKey: Key.skinTone)
        defaults.set(giphyAPIKey, forKey: Key.giphyAPIKey)
        defaults.set(gifRating, forKey: Key.gifRating)
        defaults.set(learningResetID, forKey: Key.learningResetID)
        defaults.set(customColors.dictionary, forKey: Key.customColors)
        defaults.set(keyOpacity, forKey: Key.keyOpacity)
        defaults.set(backgroundImageID, forKey: Key.backgroundImageID)
        defaults.set(backgroundDim, forKey: Key.backgroundDim)
        defaults.set(backgroundBlur, forKey: Key.backgroundBlur)
        // lastUsedMode is left alone: only the keyboard writes it, via saveLastUsedMode.
    }

    /// Where the app saves the background image, in the App Group container shared with the keyboards.
    public static var backgroundImageURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("KeyboardBackground.jpg")
    }

    /// Saves only the skin tone, which the keyboard changes when you pick a toned emoji.
    public static func saveSkinTone(_ tone: Int, to defaults: UserDefaults) {
        defaults.set(tone, forKey: Key.skinTone)
    }

    /// Saves only the last-used mode, so the keyboard doesn't overwrite settings changed in the app.
    public static func saveLastUsedMode(_ mode: InputMode, to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Key.lastUsedMode)
    }
}
