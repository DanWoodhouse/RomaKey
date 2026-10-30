import Foundation

/// Where the engine sends text. The keyboard extension forwards these to `UITextDocumentProxy`.
public protocol TextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func setMarkedText(_ text: String)
    func unmarkText()
}

public enum KeyLabel: Equatable {
    case text(String)
    /// SF Symbol name.
    case systemImage(String)
}

/// Keyboard state and key handling, independent of UIKit.
public final class KeyboardEngine {
    public enum ShiftState: Equatable {
        case off
        case once
        case locked
    }

    public private(set) var mode: InputMode
    public private(set) var page: KeyboardPage = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var composer = RomajiComposer()

    /// Whether to show our own globe key. Decided by the system per device, not per language.
    public var showsGlobe: Bool {
        didSet { if showsGlobe != oldValue { onChange?() } }
    }

    public weak var output: TextOutput?
    public var onChange: (() -> Void)?

    private let now: () -> Date
    private var lastShiftTap: Date?
    private static let doubleTapInterval: TimeInterval = 0.35

    public init(mode: InputMode = .japanese, showsGlobe: Bool = true, now: @escaping () -> Date = Date.init) {
        self.mode = mode
        self.showsGlobe = showsGlobe
        self.now = now
    }

    public var layout: KeyboardLayout {
        .layout(for: page, showsGlobe: showsGlobe)
    }

    public var isComposing: Bool { !composer.isEmpty }

    /// Conversion choices for the current composition (kanji conversion will go here later).
    public var candidates: [String] {
        guard isComposing else { return [] }
        let hiragana = composer.finalizedText
        let katakana = KanaConverter.katakana(from: hiragana)
        return katakana == hiragana ? [hiragana] : [hiragana, katakana]
    }

    public func press(_ kind: KeyKind) {
        switch kind {
        case .character(let character):
            typeCharacter(character)
        case .shift:
            toggleShift()
        case .delete:
            deleteBackward()
        case .pageToggle:
            page = page == .letters ? .numbers : .letters
            shift = .off
        case .symbolsToggle:
            page = page == .numbers ? .symbols : .numbers
        case .globe:
            break  // Handled by the system's input mode list.
        case .languageToggle:
            commitComposition()
            mode = mode == .english ? .japanese : .english
            page = .letters
            shift = .off
        case .space:
            if isComposing {
                commitComposition()
            } else {
                output?.insertText(" ")
            }
        case .longVowel:
            if mode == .japanese {
                composer.input("-")
                updateMarkedText()
            } else {
                output?.insertText("-")
            }
        case .returnKey:
            if isComposing {
                commitComposition()
            } else {
                output?.insertText("\n")
            }
        }
        onChange?()
    }

    public func selectCandidate(_ candidate: String) {
        commit(candidate)
        onChange?()
    }

    public func commitComposition() {
        guard isComposing else { return }
        commit(composer.finalizedText)
    }

    public func label(for kind: KeyKind) -> KeyLabel {
        switch kind {
        case .character(let character):
            return .text(isShifted ? character.uppercased() : character)
        case .shift:
            switch shift {
            case .off: return .systemImage("shift")
            case .once: return .systemImage("shift.fill")
            case .locked: return .systemImage("capslock.fill")
            }
        case .delete:
            return .systemImage("delete.left")
        case .pageToggle:
            if page == .letters { return .text("123") }
            return .text(mode == .japanese ? "かな" : "ABC")
        case .symbolsToggle:
            return .text(page == .numbers ? "#+=" : "123")
        case .globe:
            return .systemImage("globe")
        case .languageToggle:
            return .text(mode == .japanese ? "あ" : "EN")
        case .space:
            return .text(mode == .japanese ? "空白" : "space")
        case .longVowel:
            return .text(mode == .japanese ? "ー" : "-")
        case .returnKey:
            if mode == .english { return .text("return") }
            return .text(isComposing ? "確定" : "改行")
        }
    }

    private var isShifted: Bool { page == .letters && shift != .off }

    private func typeCharacter(_ character: String) {
        let text = isShifted ? character.uppercased() : character
        switch mode {
        case .english:
            output?.insertText(text)
        case .japanese:
            if isShifted {
                composer.inputLiteral(text)
            } else {
                for romaji in text {
                    composer.input(romaji)
                }
            }
            updateMarkedText()
        }
        if shift == .once {
            shift = .off
        }
    }

    private func toggleShift() {
        let time = now()
        if shift == .once, let lastShiftTap, time.timeIntervalSince(lastShiftTap) < Self.doubleTapInterval {
            shift = .locked
        } else {
            shift = shift == .off ? .once : .off
        }
        lastShiftTap = time
    }

    private func deleteBackward() {
        if isComposing {
            composer.deleteBackward()
            updateMarkedText()
        } else {
            output?.deleteBackward()
        }
    }

    private func updateMarkedText() {
        if composer.isEmpty {
            output?.setMarkedText("")
            output?.unmarkText()
        } else {
            output?.setMarkedText(composer.displayText)
        }
    }

    private func commit(_ text: String) {
        output?.setMarkedText(text)
        output?.unmarkText()
        composer.reset()
    }
}
