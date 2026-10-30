import KeyboardCore
import UIKit

/// Colours for one keyboard theme. Every colour adapts to light and dark mode.
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

    static func named(_ theme: KeyboardSettings.Theme) -> KeyboardTheme {
        switch theme {
        case .system:
            return KeyboardTheme(
                background: .clear,
                key: .dynamic(light: 0xFFFFFF, dark: 0x6B6B6F),
                specialKey: .dynamic(light: 0xABB0BA, dark: 0x464649),
                pressedKey: .dynamic(light: 0xD1D3D8, dark: 0x8C8C90),
                text: .label,
                secondaryText: .secondaryLabel,
                accent: .systemBlue
            )
        case .ai:
            return KeyboardTheme(
                background: .dynamic(light: 0xD7DFEA, dark: 0x141C2B),
                key: .dynamic(light: 0xFFFFFF, dark: 0x2A3A55),
                specialKey: .dynamic(light: 0xA9B8CF, dark: 0x1E2A3F),
                pressedKey: .dynamic(light: 0xC7D3E5, dark: 0x3A4E70),
                text: .dynamic(light: 0x14213A, dark: 0xE6ECF5),
                secondaryText: .dynamic(light: 0x4A5A75, dark: 0x9FB0CC),
                accent: .dynamic(light: 0x24477A, dark: 0x8FB0E6)
            )
        case .sakura:
            return KeyboardTheme(
                background: .dynamic(light: 0xF6E4E8, dark: 0x2A1D21),
                key: .dynamic(light: 0xFFFFFF, dark: 0x4A353B),
                specialKey: .dynamic(light: 0xE3BCC6, dark: 0x3A2A2F),
                pressedKey: .dynamic(light: 0xF2D3DA, dark: 0x5E444B),
                text: .dynamic(light: 0x3A1F27, dark: 0xF7E8EC),
                secondaryText: .dynamic(light: 0x7A5560, dark: 0xC9A7B0),
                accent: .dynamic(light: 0xC94F6D, dark: 0xF08CA5)
            )
        case .matcha:
            return KeyboardTheme(
                background: .dynamic(light: 0xE1E8D8, dark: 0x1C2219),
                key: .dynamic(light: 0xFFFFFF, dark: 0x36422F),
                specialKey: .dynamic(light: 0xB5C4A3, dark: 0x2A3325),
                pressedKey: .dynamic(light: 0xD3DEC6, dark: 0x46553D),
                text: .dynamic(light: 0x24301D, dark: 0xE6EEDD),
                secondaryText: .dynamic(light: 0x56654B, dark: 0xA9B99B),
                accent: .dynamic(light: 0x5B7F3A, dark: 0xA8CB82)
            )
        case .sumi:
            // Ink: dark in both light and dark mode.
            return KeyboardTheme(
                background: .dynamic(light: 0x1B1B1D, dark: 0x1B1B1D),
                key: .dynamic(light: 0x3A3A3E, dark: 0x3A3A3E),
                specialKey: .dynamic(light: 0x2A2A2D, dark: 0x2A2A2D),
                pressedKey: .dynamic(light: 0x55555A, dark: 0x55555A),
                text: .dynamic(light: 0xF2F2F2, dark: 0xF2F2F2),
                secondaryText: .dynamic(light: 0xA8A8AD, dark: 0xA8A8AD),
                accent: .dynamic(light: 0xE0B354, dark: 0xE0B354)
            )
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}
