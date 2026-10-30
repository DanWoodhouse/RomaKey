import KeyboardCore
import UIKit

/// ✨ in the toolbar: Apple Intelligence on the text before the cursor, in place of the keys.
/// Japanese gets grammar, an explanation, casual/です・ます/敬語 rewrites and kanji conversion;
/// English gets grammar and translation into Japanese. Results go through `AIValidation`, and
/// "Use this" swaps them in for the text.
///
/// Needs iOS 26 and Apple Intelligence. Whether Apple's model runs inside a keyboard isn't
/// documented: the app's Apple Intelligence test checks it on your phone.
final class AIPanel: UIView {
    var onClose: (() -> Void)?
    /// Replaces the text the AI worked on.
    var onReplace: ((String) -> Void)?

    enum Action: CaseIterable {
        case grammar, explain, casual, polite, honorific, kanji, toCasual, toPolite, toHonorific

        var title: String {
            switch self {
            case .grammar: return "文法 Check"
            case .explain: return "説明 Explain"
            case .casual: return "カジュアル"
            case .polite: return "です/ます"
            case .honorific: return "敬語"
            case .kanji: return "漢字に"
            case .toCasual: return "→ 日本語 casual"
            case .toPolite: return "→ 日本語 polite"
            case .toHonorific: return "→ 敬語"
            }
        }
    }

    struct Outcome {
        var main: String
        var extra: [String] = []
        /// What "Use this" puts in place of the text, if anything.
        var replacement: String?
    }

    private let input: String
    private let theme: KeyboardTheme
    private let showsRomaji: Bool
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let results = UIStackView()
    private var actionButtons: [Action: UIButton] = [:]
    private var bar: UIView?
    private var task: Task<Void, Never>?
    private static let barHeight: CGFloat = 38

    init(input: String, theme: KeyboardTheme, showsRomaji: Bool) {
        self.input = input
        self.theme = theme
        self.showsRomaji = showsRomaji
        super.init(frame: .zero)

        content.axis = .vertical
        content.spacing = 8
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24),
        ])
        results.axis = .vertical
        results.spacing = 4
        results.alignment = .leading

        if input.isEmpty {
            content.addArrangedSubview(label("Type something first, then tap ✨. AI works on the text before the cursor.", size: 14, secondary: true))
        } else {
            let quote = label(input, size: 13, secondary: true)
            quote.numberOfLines = 2
            content.addArrangedSubview(quote)
            content.addArrangedSubview(actionsRow())
            content.addArrangedSubview(results)
        }
        let bar = bottomBar()
        addSubview(bar)
        self.bar = bar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        task?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.barHeight)
        bar?.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 8, height: Self.barHeight)
    }

    /// The actions that make sense for the text's language.
    private var actions: [Action] {
        guard AIText.containsJapanese(input) else { return [.grammar, .toCasual, .toPolite, .toHonorific] }
        let hasKanji = input.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        return [.grammar, .explain, .casual, .polite, .honorific] + (hasKanji ? [] : [.kanji])
    }

    private func actionsRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        for action in actions {
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = theme.key
            configuration.baseForegroundColor = theme.text
            configuration.cornerStyle = .medium
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            var title = AttributedString(action.title)
            title.font = theme.font(13, weight: .medium)
            configuration.attributedTitle = title
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.run(action) })
            actionButtons[action] = button
            row.addArrangedSubview(button)
        }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 34),
        ])
        return scroll
    }

    private func bottomBar() -> UIView {
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.alignment = .center
        var done = UIButton.Configuration.plain()
        done.baseForegroundColor = theme.text
        var title = AttributedString("ABC")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        done.attributedTitle = title
        bar.addArrangedSubview(UIButton(configuration: done, primaryAction: UIAction { [weak self] _ in self?.onClose?() }))
        let heading = label("✨ Apple Intelligence", size: 13, secondary: true)
        heading.textAlignment = .center
        bar.addArrangedSubview(heading)
        return bar
    }

    private func label(_ text: String, size: CGFloat, secondary: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = secondary ? .systemFont(ofSize: size) : theme.font(size)
        label.textColor = secondary ? theme.secondaryText : theme.text
        return label
    }

    // MARK: - Running

    private func run(_ action: Action) {
        task?.cancel()
        for (candidate, button) in actionButtons {
            button.configuration?.baseBackgroundColor = candidate == action ? theme.accent : theme.key
            button.configuration?.baseForegroundColor = candidate == action ? .white : theme.text
        }
        show(Outcome(main: "Thinking…"))
        let input = input
        let showsRomaji = showsRomaji
        task = Task { @MainActor [weak self] in
            let result: Outcome
            if #available(iOS 26.0, *) {
                result = await Self.perform(action, input: input, showsRomaji: showsRomaji)
            } else {
                result = Outcome(main: "AI needs iOS 26 with Apple Intelligence turned on.")
            }
            guard !Task.isCancelled else { return }
            self?.show(result)
        }
    }

    private func show(_ result: Outcome) {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        results.addArrangedSubview(label(result.main, size: 17))
        for line in result.extra where !line.isEmpty {
            results.addArrangedSubview(label(line, size: 13, secondary: true))
        }
        if let replacement = result.replacement {
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = theme.accent
            configuration.baseForegroundColor = .white
            configuration.cornerStyle = .medium
            configuration.title = "Use this"
            results.addArrangedSubview(UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.onReplace?(replacement)
            }))
        }
    }

    @available(iOS 26.0, *)
    private static func perform(_ action: Action, input: String, showsRomaji: Bool) async -> Outcome {
#if canImport(FoundationModels)
        guard AIAssistant.isAvailable else {
            return Outcome(main: "Apple Intelligence isn't available. It needs an iPhone 15 Pro or newer with Apple Intelligence turned on in Settings.")
        }
        func reading(_ text: String?) -> String {
            guard let text else { return "" }
            return showsRomaji ? text + "  ·  " + KanaConverter.romaji(from: text) : text
        }
        do {
            switch action {
            case .grammar:
                switch try await AIAssistant.checkGrammar(input) {
                case .noMistakes:
                    return Outcome(main: "No mistakes found. ✓")
                case .unreliable:
                    return Outcome(main: "The answer didn't look like a fix, so it isn't shown.")
                case .corrected(let text, let corrections):
                    return Outcome(main: text, extra: corrections.map { "\($0.original) → \($0.fix): \($0.reason)" }, replacement: text)
                }
            case .explain:
                guard let explanation = try await AIAssistant.explain(input) else {
                    return Outcome(main: "The answer didn't look like an explanation, so it isn't shown.")
                }
                return Outcome(main: explanation.meaning, extra: [reading(explanation.reading)] + explanation.notes)
            case .kanji:
                guard let converted = try await AIAssistant.convertToKanji(input) else {
                    return Outcome(main: "The conversion changed the words, so it isn't shown.")
                }
                return Outcome(main: converted, replacement: converted)
            case .casual, .polite, .honorific:
                let target: Politeness = action == .casual ? .casual : action == .polite ? .polite : .honorific
                guard let rewritten = try await AIAssistant.rewrite(input, as: target) else {
                    return Outcome(main: "Already in that style, or the answer didn't look right.")
                }
                return Outcome(main: rewritten, replacement: rewritten)
            case .toCasual, .toPolite, .toHonorific:
                // 敬語 is a polite translation, then a 敬語 rewrite.
                guard let translation = try await AIAssistant.translate(input, style: action == .toCasual ? .casual : .polite) else {
                    return Outcome(main: "The answer didn't look like a translation, so it isn't shown.")
                }
                if action == .toHonorific, let honorific = try await AIAssistant.rewrite(translation.japanese, as: .honorific) {
                    return Outcome(main: honorific, replacement: honorific)
                }
                return Outcome(main: translation.japanese, extra: [reading(translation.reading)], replacement: translation.japanese)
            }
        } catch {
            return Outcome(main: "Apple Intelligence couldn't answer here (\(error.localizedDescription)). Try the Apple Intelligence test in the RomaKey app.")
        }
#else
        return Outcome(main: "This build doesn't include Apple Intelligence. Build with Xcode 26 or later.")
#endif
    }
}
