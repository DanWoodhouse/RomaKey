import Foundation

/// One choice on the mode key's wheel: a cross of four around the finger.
public enum ModeWheelSlot: CaseIterable, Hashable {
    case japanese
    case english
    case dictionary
    /// The 12-key flick board.
    case kana

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
        case .kana: return nil
        }
    }

    public var label: String {
        switch self {
        case .japanese: return "あ"
        case .english: return "EN"
        case .dictionary: return "辞"
        case .kana: return "かな"
        }
    }

    /// かな swaps the whole board, and sits below the key, where a sloppy tap slips to. So a
    /// quick flick never picks it: the wheel must have been showing for
    /// `ModeWheel.deliberateDelay` first.
    public var needsDeliberatePick: Bool {
        self == .kana
    }

    public var accessibilityName: String {
        switch self {
        case .japanese: return "Japanese romaji"
        case .english: return "English"
        case .dictionary: return "Dictionary"
        case .kana: return "Kana flick keyboard"
        }
    }
}

/// Press and drag from the mode key to pick a slot: ← あ, → EN, ↑ 辞, ↓ かな. The slots never
/// move, and never change with the current mode, so each one is always the same direction from
/// the key. A quick swipe works without waiting for the wheel to appear. The left-handed
/// setting swaps left and right. (The next keyboard isn't here: iOS shows 🌐 under the keyboard.)
public enum ModeWheel {
    public static let slots = ModeWheelSlot.allCases

    /// How far the finger must move before a slot is picked. Less than this is a tap.
    public static let threshold = 30.0

    /// Downwards is shorter: the mode key is on the bottom row, near the keyboard's edge.
    public static let downThreshold = 20.0

    /// How long the wheel must have been showing before かな can be picked.
    public static let deliberateDelay = 0.25

    /// The direction of a slot, in radians: π is straight left, π/2 straight up, 0 straight
    /// right and -π/2 straight down.
    public static func angle(of slot: ModeWheelSlot, leftHanded: Bool = false) -> Double {
        switch slot {
        case .japanese: return leftHanded ? 0 : Double.pi
        case .english: return leftHanded ? Double.pi : 0
        case .dictionary: return Double.pi / 2
        case .kana: return -Double.pi / 2
        }
    }

    /// The slot a drag points at, from the finger's movement since it touched the key
    /// (screen coordinates: `dy` grows downwards). Whichever axis moved more decides. Nil for a tap.
    public static func slot(dx: Double, dy: Double, leftHanded: Bool = false) -> ModeWheelSlot? {
        let downwards = dy > abs(dx)
        let needed = downwards ? downThreshold : threshold
        guard dx * dx + dy * dy >= needed * needed else { return nil }
        if abs(dx) > abs(dy) {
            return (dx < 0) != leftHanded ? .japanese : .english
        }
        return dy < 0 ? .dictionary : .kana
    }
}
