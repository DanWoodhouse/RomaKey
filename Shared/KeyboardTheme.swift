import KeyboardCore
import UIKit

/// Colours for the keyboard: a built-in theme or the user's own, with key opacity applied.
struct KeyboardTheme {
    /// Behind the keys. Clear lets the system keyboard background show through.
    let background: UIColor
    let key: UIColor
    let specialKey: UIColor
    let pressedKey: UIColor
    let text: UIColor
    let secondaryText: UIColor
    /// Flick guide highlight and other emphasis.
    let accent: UIColor
    /// The key colour at full opacity, for popups and panels that sit on top of the keys.
    let panel: UIColor

    /// The theme `settings` describe.
    init(_ settings: KeyboardSettings) {
        self.init(theme: settings.theme, custom: settings.customColors, keyOpacity: settings.keyOpacity)
    }

    init(theme: KeyboardSettings.Theme, custom: ThemeColors? = nil, keyOpacity: Double = 1) {
        func color(_ keyPath: KeyPath<ThemeColors, UInt32>, alpha: Double = 1) -> UIColor {
            if theme == .custom, let custom {
                return UIColor(hex: custom[keyPath: keyPath], alpha: alpha)
            }
            let light = ThemePalette.colors(for: theme, dark: false)[keyPath: keyPath]
            let dark = ThemePalette.colors(for: theme, dark: true)[keyPath: keyPath]
            return .dynamic(light: light, dark: dark, alpha: alpha)
        }

        if theme == .system {
            // Match the system keyboard: its own background, system text colours.
            background = .clear
            text = .label
            secondaryText = .secondaryLabel
            accent = .systemBlue
        } else {
            background = color(\.background)
            text = color(\.text)
            secondaryText = color(\.secondaryText)
            accent = color(\.accent)
        }
        key = color(\.key, alpha: keyOpacity)
        specialKey = color(\.specialKey, alpha: keyOpacity)
        pressedKey = color(\.pressedKey)
        panel = color(\.key)
    }

    static func named(_ theme: KeyboardSettings.Theme) -> KeyboardTheme {
        KeyboardTheme(theme: theme)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func dynamic(light: UInt32, dark: UInt32, alpha: Double = 1) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        }
    }

    /// 0xRRGGBB, dropping alpha. Used when saving colours picked in the app.
    var hexValue: UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32((min(max(value, 0), 1) * 255).rounded())
        }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }
}
