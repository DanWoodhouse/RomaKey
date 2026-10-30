/// The colours of one keyboard theme, as 0xRRGGBB values.
public struct ThemeColors: Equatable {
    /// Behind the keys.
    public var background: UInt32
    public var key: UInt32
    /// Shift, delete, return and the other function keys.
    public var specialKey: UInt32
    public var pressedKey: UInt32
    public var text: UInt32
    /// Readings and meanings in the candidate bar.
    public var secondaryText: UInt32
    /// Flick guide, selected options and buttons.
    public var accent: UInt32

    public init(
        background: UInt32, key: UInt32, specialKey: UInt32, pressedKey: UInt32,
        text: UInt32, secondaryText: UInt32, accent: UInt32
    ) {
        self.background = background
        self.key = key
        self.specialKey = specialKey
        self.pressedKey = pressedKey
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
    }

    /// Every colour with its storage name, in the order the app lists them.
    public static let fields: [(name: String, keyPath: WritableKeyPath<ThemeColors, UInt32>)] = [
        ("background", \.background),
        ("key", \.key),
        ("specialKey", \.specialKey),
        ("pressedKey", \.pressedKey),
        ("text", \.text),
        ("secondaryText", \.secondaryText),
        ("accent", \.accent),
    ]

    var dictionary: [String: Int] {
        Dictionary(uniqueKeysWithValues: Self.fields.map { ($0.name, Int(self[keyPath: $0.keyPath])) })
    }

    /// Fills in from saved values, keeping `fallback` for any that are missing.
    init(dictionary: [String: Int], fallback: ThemeColors) {
        self = fallback
        for field in Self.fields {
            if let value = dictionary[field.name], (0...0xFFFFFF).contains(value) {
                self[keyPath: field.keyPath] = UInt32(value)
            }
        }
    }
}

/// The built-in themes' colours, for light and dark mode.
public enum ThemePalette {
    public static func colors(for theme: KeyboardSettings.Theme, dark: Bool) -> ThemeColors {
        switch (theme, dark) {
        case (.system, false), (.custom, false):
            return ThemeColors(background: 0xD1D4DB, key: 0xFFFFFF, specialKey: 0xABB0BA, pressedKey: 0xD1D3D8,
                               text: 0x000000, secondaryText: 0x6B7080, accent: 0x007AFF)
        case (.system, true), (.custom, true):
            return ThemeColors(background: 0x2B2B2E, key: 0x6B6B6F, specialKey: 0x464649, pressedKey: 0x8C8C90,
                               text: 0xFFFFFF, secondaryText: 0xB5B5BB, accent: 0x0A84FF)
        case (.ai, false):
            return ThemeColors(background: 0xD7DFEA, key: 0xFFFFFF, specialKey: 0xA9B8CF, pressedKey: 0xC7D3E5,
                               text: 0x14213A, secondaryText: 0x4A5A75, accent: 0x24477A)
        case (.ai, true):
            return ThemeColors(background: 0x141C2B, key: 0x2A3A55, specialKey: 0x1E2A3F, pressedKey: 0x3A4E70,
                               text: 0xE6ECF5, secondaryText: 0x9FB0CC, accent: 0x8FB0E6)
        case (.sakura, false):
            return ThemeColors(background: 0xF6E4E8, key: 0xFFFFFF, specialKey: 0xE3BCC6, pressedKey: 0xF2D3DA,
                               text: 0x3A1F27, secondaryText: 0x7A5560, accent: 0xC94F6D)
        case (.sakura, true):
            return ThemeColors(background: 0x2A1D21, key: 0x4A353B, specialKey: 0x3A2A2F, pressedKey: 0x5E444B,
                               text: 0xF7E8EC, secondaryText: 0xC9A7B0, accent: 0xF08CA5)
        case (.matcha, false):
            return ThemeColors(background: 0xE1E8D8, key: 0xFFFFFF, specialKey: 0xB5C4A3, pressedKey: 0xD3DEC6,
                               text: 0x24301D, secondaryText: 0x56654B, accent: 0x5B7F3A)
        case (.matcha, true):
            return ThemeColors(background: 0x1C2219, key: 0x36422F, specialKey: 0x2A3325, pressedKey: 0x46553D,
                               text: 0xE6EEDD, secondaryText: 0xA9B99B, accent: 0xA8CB82)
        case (.sumi, _):
            // Ink: dark in both light and dark mode.
            return ThemeColors(background: 0x1B1B1D, key: 0x3A3A3E, specialKey: 0x2A2A2D, pressedKey: 0x55555A,
                               text: 0xF2F2F2, secondaryText: 0xA8A8AD, accent: 0xE0B354)
        }
    }
}
