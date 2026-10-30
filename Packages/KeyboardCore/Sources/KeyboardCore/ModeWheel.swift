import Foundation

/// One choice on the mode key's half wheel, listed left to right.
public enum ModeWheelSlot: CaseIterable, Hashable {
    case japanese
    case english
    case dictionary
    /// The 12-key flick board.
    case kana
    /// The next keyboard installed on the phone (what 🌐 used to do).
    case nextKeyboard

    public init(_ mode: InputMode) {
        switch mode {
        case .japanese: self = .japanese
        case .english: self = .english
        case .dictionary: self = .dictionary
        }
    }

    /// The ローマ字 board's mode for this slot, if it is one.
    public var inputMode: InputMode? {
        switch self {
        case .japanese: return .japanese
        case .english: return .english
        case .dictionary: return .dictionary
        case .kana, .nextKeyboard: return nil
        }
    }

    public var label: String {
        switch self {
        case .japanese: return "あ"
        case .english: return "EN"
        case .dictionary: return "辞"
        case .kana: return "かな"
        case .nextKeyboard: return "🌐"
        }
    }

    public var accessibilityName: String {
        switch self {
        case .japanese: return "Japanese romaji"
        case .english: return "English"
        case .dictionary: return "Dictionary"
        case .kana: return "Kana flick keyboard"
        case .nextKeyboard: return "Next keyboard"
        }
    }
}

/// Press and drag from the mode key to pick a slot from a half wheel above it. The slots never
/// move, and never change with the current mode, so each one is always the same direction from
/// the key: straight up is 辞, up-right is かな, and so on. A quick swipe works without waiting
/// for the wheel to appear.
public enum ModeWheel {
    public static let slots = ModeWheelSlot.allCases

    /// How far the finger must move before a slot is picked. Less than this is a tap.
    public static let threshold = 22.0

    /// The direction of a slot's centre, in radians: π is straight left, π/2 straight up and
    /// 0 straight right. The half circle is split into equal sectors.
    public static func angle(of slot: ModeWheelSlot) -> Double {
        let index = Double(slots.firstIndex(of: slot)!)
        return Double.pi - sector * (index + 0.5)
    }

    /// The slot a drag points at, from the finger's movement since it touched the key
    /// (screen coordinates: `dy` grows downwards). Nil for a tap.
    public static func slot(dx: Double, dy: Double, threshold: Double = threshold) -> ModeWheelSlot? {
        guard dx * dx + dy * dy >= threshold * threshold else { return nil }
        var angle = atan2(-dy, dx)
        // Below the key: the nearest end of the wheel.
        if angle < 0 {
            angle = dx < 0 ? Double.pi : 0
        }
        let index = min(Int((Double.pi - angle) / sector), slots.count - 1)
        return slots[index]
    }

    private static var sector: Double { Double.pi / Double(slots.count) }
}
