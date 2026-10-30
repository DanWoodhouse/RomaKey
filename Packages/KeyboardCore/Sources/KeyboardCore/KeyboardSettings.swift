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

    // かな keyboard
    /// Turns off tap-to-cycle, so tapping あ twice types ああ.
    public var flickOnly = false
    public var flickSensitivity: FlickSensitivity = .normal

    // Both
    public var showMeanings = true
    public var fullWidthSpace = false
    public var spaceBarCursor = true
    public var keySounds = true
    /// Needs Full Access.
    public var haptics = false
    public var theme: Theme = .system
    public var height: Height = .standard

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
        static let flickOnly = "flickOnly"
        static let flickSensitivity = "flickSensitivity"
        static let showMeanings = "showMeanings"
        static let fullWidthSpace = "fullWidthSpace"
        static let spaceBarCursor = "spaceBarCursor"
        static let keySounds = "keySounds"
        static let haptics = "haptics"
        static let theme = "theme"
        static let height = "height"
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
        flickOnly = bool(Key.flickOnly, flickOnly)
        flickSensitivity = value(Key.flickSensitivity, flickSensitivity)
        showMeanings = bool(Key.showMeanings, showMeanings)
        fullWidthSpace = bool(Key.fullWidthSpace, fullWidthSpace)
        spaceBarCursor = bool(Key.spaceBarCursor, spaceBarCursor)
        keySounds = bool(Key.keySounds, keySounds)
        haptics = bool(Key.haptics, haptics)
        theme = value(Key.theme, theme)
        height = value(Key.height, height)
        lastUsedMode = value(Key.lastUsedMode, lastUsedMode)
    }

    /// Saves everything the user edits in the app.
    public func save(to defaults: UserDefaults) {
        defaults.set(startingMode.rawValue, forKey: Key.startingMode)
        defaults.set(languageKeyModes.map(\.rawValue), forKey: Key.languageKeyModes)
        defaults.set(autoCapitalization, forKey: Key.autoCapitalization)
        defaults.set(doubleSpacePeriod, forKey: Key.doubleSpacePeriod)
        defaults.set(keyPopups, forKey: Key.keyPopups)
        defaults.set(flickOnly, forKey: Key.flickOnly)
        defaults.set(flickSensitivity.rawValue, forKey: Key.flickSensitivity)
        defaults.set(showMeanings, forKey: Key.showMeanings)
        defaults.set(fullWidthSpace, forKey: Key.fullWidthSpace)
        defaults.set(spaceBarCursor, forKey: Key.spaceBarCursor)
        defaults.set(keySounds, forKey: Key.keySounds)
        defaults.set(haptics, forKey: Key.haptics)
        defaults.set(theme.rawValue, forKey: Key.theme)
        defaults.set(height.rawValue, forKey: Key.height)
        // lastUsedMode is left alone: only the keyboard writes it, via saveLastUsedMode.
    }

    /// Saves only the last-used mode, so the keyboard doesn't overwrite settings changed in the app.
    public static func saveLastUsedMode(_ mode: InputMode, to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Key.lastUsedMode)
    }
}
