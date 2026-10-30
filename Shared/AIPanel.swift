import KeyboardCore
import UIKit

/// ✨ in the toolbar: AI on the text before the cursor, in place of the keys. Apple Intelligence
/// answers by default; Claude can be picked instead, here or in the app.
/// Japanese actions come first, English ones underneath. For Japanese text: grammar, an
/// explanation, casual/です・ます/敬語 rewrites and kanji conversion, then a translation into
/// English. For English text: translation into Japanese, then grammar and formal, casual or
/// shorter rewrites. Results go through `AIValidation`, and
/// "Use this" swaps them in for the text.
///
/// Apple Intelligence needs iOS 26 on a supported iPhone. Whether Apple's model runs inside a
/// keyboard isn't documented: the app's Apple Intelligence test checks it on your phone. Claude
/// needs the user's API key and Full Access.
final class AIPanel: UIView {
    var onClose: (() -> Void)?
    /// Replaces the text the AI worked on.
    var onReplace: ((String) -> Void)?
    /// Apple or Claude was picked in the panel; the keyboard saves it.
    var onProviderChange: ((KeyboardSettings.AIProvider) -> Void)?

    enum Action: CaseIterable {
        case grammar, explain, casual, polite, honorific, kanji, toCasual, toPolite, toHonorific
        case toEnglish, formal, friendly, shorter

        var title: String {
            switch self {
            case .grammar: return "Check grammar"
            case .explain: return "説明 Explain"
            case .casual: return "カジュアル"
            case .polite: return "です/ます"
            case .honorific: return "敬語"
            case .kanji: return "漢字に"
            case .toCasual: return "→ 日本語 casual"
            case .toPolite: return "→ 日本語 polite"
            case .toHonorific: return "→ 敬語"
            case .toEnglish: return "→ English"
            case .formal: return "Formal"
            case .friendly: return "Casual"
            case .shorter: return "Shorter"
            }
        }
    }

    struct Outcome {
        enum Kind {
            case answer
            case noMistakes
            /// The model couldn't answer, or its answer didn't pass the checks.
            case problem
        }

        var main: String
        var extra: [String] = []
        /// Grammar fixes, shown as wrong → right with the reason.
        var fixes: [GrammarCorrection] = []
        /// What "Use this" puts in place of the text, if anything.
        var replacement: String?
        var kind: Kind = .answer

        static func problem(_ message: String) -> Outcome {
            Outcome(main: message, kind: .problem)
        }
    }

    /// The glyph on each action's chip.
    private static func glyph(for action: Action) -> String {
        switch action {
        case .grammar: return "✓"
        case .explain: return "説"
        case .casual, .toCasual: return "友"
        case .polite, .toPolite: return "丁"
        case .honorific, .toHonorific: return "敬"
        case .kanji: return "漢"
        case .toEnglish: return "EN"
        case .formal: return "Aa"
        case .friendly: return "Hi"
        case .shorter: return "↔"
        }
    }

    private let input: String
    private let theme: KeyboardTheme
    private let showsRomaji: Bool
    private var provider: KeyboardSettings.AIProvider
    private let claudeAPIKey: String
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let results = UIStackView()
    private lazy var resultCard = GlassCard(theme: theme, title: nil, content: results, cornerRadius: 20,
                                            insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
    private var actionButtons: [Action: UIButton] = [:]
    private var selectedAction: Action?
    private var bar: UIView?
    private var task: Task<Void, Never>?
    private static let barHeight: CGFloat = 38

    init(input: String, theme: KeyboardTheme, showsRomaji: Bool, provider: KeyboardSettings.AIProvider, claudeAPIKey: String) {
        self.input = input
        self.theme = theme
        self.showsRomaji = showsRomaji
        self.provider = provider
        self.claudeAPIKey = claudeAPIKey
        super.init(frame: .zero)

        content.axis = .vertical
        content.spacing = 8
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.removeEdgeEffects()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(content)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -10),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -20),
        ])
        results.axis = .vertical
        results.spacing = 8
        results.alignment = .fill
        resultCard.isHidden = true

        if input.isEmpty {
            content.addArrangedSubview(label("Type something first, then tap ✨. AI works on the text before the cursor.", size: 14, secondary: true))
        } else {
            // Compact, so most of the panel is left for the answer: the text on one line, then
            // both languages' actions in one scrolling row.
            let quote = label("✨ " + input, size: 13)
            quote.numberOfLines = 1
            quote.lineBreakMode = .byTruncatingTail
            content.addArrangedSubview(GlassCard(theme: theme, title: nil, content: quote, cornerRadius: 14,
                                                 insets: UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)))
            content.addArrangedSubview(actionsRow([("日本語", japaneseActions), ("EN", englishActions)]))
            content.addArrangedSubview(resultCard)
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

    private var isJapanese: Bool { AIText.containsJapanese(input) }

    /// The Japanese actions that make sense for the text.
    private var japaneseActions: [Action] {
        guard isJapanese else { return [.toCasual, .toPolite, .toHonorific] }
        let hasKanji = input.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        return [.grammar, .explain, .casual, .polite, .honorific] + (hasKanji ? [] : [.kanji])
    }

    /// The English actions that make sense for the text, shown under the Japanese ones.
    private var englishActions: [Action] {
        isJapanese ? [.toEnglish] : [.grammar, .formal, .friendly, .shorter]
    }

    /// Every group's chips in one scrolling row, each group led by a small tag.
    private func actionsRow(_ groups: [(tag: String, actions: [Action])]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        for (index, group) in groups.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = theme.text.withAlphaComponent(0.18)
                divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
                divider.heightAnchor.constraint(equalToConstant: 22).isActive = true
                row.addArrangedSubview(divider)
                row.setCustomSpacing(10, after: row.arrangedSubviews[row.arrangedSubviews.count - 2])
                row.setCustomSpacing(10, after: divider)
            }
            let tag = UILabel()
            tag.text = group.tag
            tag.font = .systemFont(ofSize: 10, weight: .semibold)
            tag.textColor = theme.text.withAlphaComponent(0.55)
            row.addArrangedSubview(tag)
            addChips(group.actions, to: row)
        }
        let scroll = UIScrollView()
        scroll.removeEdgeEffects()
        scroll.showsHorizontalScrollIndicator = false
        scroll.clipsToBounds = false
        scroll.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 36),
        ])
        return scroll
    }

    private func addChips(_ actions: [Action], to row: UIStackView) {
        for action in actions {
            let button = UIButton(configuration: chipConfiguration(for: action, selected: false),
                                  primaryAction: UIAction { [weak self] _ in self?.run(action) })
            button.tintColor = theme.accent
            actionButtons[action] = button
            row.addArrangedSubview(button)
        }
    }

    /// A glass chip with a round glyph badge; the chosen one fills with the accent colour.
    private func chipConfiguration(for action: Action, selected: Bool) -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = selected ? .prominentGlass() : .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = selected ? theme.accent : theme.key
        }
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = selected ? .white : theme.text
        configuration.image = glyphBadge(Self.glyph(for: action), selected: selected)
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 12)
        // Grammar is listed under the text's own language.
        var title = AttributedString(action == .grammar && isJapanese ? "文法 Check" : action.title)
        title.font = theme.font(13, weight: .medium)
        configuration.attributedTitle = title
        return configuration
    }

    private func glyphBadge(_ glyph: String, selected: Bool) -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let accent = theme.accent.resolvedColor(with: traitCollection)
        return UIGraphicsImageRenderer(size: size).image { _ in
            (selected ? UIColor.white.withAlphaComponent(0.25) : accent.withAlphaComponent(0.18)).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let text = NSAttributedString(string: glyph, attributes: [
                .font: UIFont.systemFont(ofSize: glyph.count > 1 ? 10 : 12, weight: .bold),
                .foregroundColor: selected ? UIColor.white : accent,
            ])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        }.withRenderingMode(.alwaysOriginal)
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
        let heading = UILabel()
        heading.text = "✨ AI"
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = theme.secondaryText
        heading.textAlignment = .center
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(heading)
        // A small capsule rather than a segmented control, so the bar never crowds the panel.
        let providerButton = UIButton(configuration: providerConfiguration())
        providerButton.addAction(UIAction { [weak self, weak providerButton] _ in
            guard let self, let providerButton else { return }
            self.task?.cancel()
            self.provider = self.provider == .apple ? .claude : .apple
            self.onProviderChange?(self.provider)
            providerButton.configuration = self.providerConfiguration()
            self.updateProviderLabel(providerButton)
            self.select(nil)
            self.resultCard.isHidden = true
        }, for: .touchUpInside)
        providerButton.setContentHuggingPriority(.required, for: .horizontal)
        updateProviderLabel(providerButton)
        bar.addArrangedSubview(providerButton)
        return bar
    }

    private func providerConfiguration() -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = theme.text
        configuration.image = UIImage(systemName: "arrow.left.arrow.right",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        var title = AttributedString(provider == .apple ? "Apple" : "Claude")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        configuration.attributedTitle = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        return configuration
    }

    private func updateProviderLabel(_ button: UIButton) {
        let apple = provider == .apple
        button.accessibilityLabel = "Answered by \(apple ? "Apple Intelligence" : "Claude")"
        button.accessibilityHint = "Switches to \(apple ? "Claude" : "Apple Intelligence")"
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

    private func select(_ action: Action?) {
        selectedAction = action
        for (candidate, button) in actionButtons {
            button.configuration = chipConfiguration(for: candidate, selected: candidate == action)
        }
    }

    private func run(_ action: Action) {
        task?.cancel()
        select(action)
        showThinking()
        let input = input
        let showsRomaji = showsRomaji
        let engine = self.engine
        task = Task { @MainActor [weak self] in
            let result: Outcome
            switch engine {
            case .ready(let engine):
                result = await Self.perform(action, input: input, engine: engine, showsRomaji: showsRomaji)
            case .unavailable(let reason):
                result = reason
            }
            guard !Task.isCancelled else { return }
            self?.show(result)
        }
    }

    /// ✨ Thinking… over shimmering placeholder lines, while the model works.
    private func showThinking() {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let thinking = label("✨ Thinking…", size: 13)
        thinking.font = .systemFont(ofSize: 13, weight: .semibold)
        thinking.textColor = theme.text.withAlphaComponent(0.7)
        results.addArrangedSubview(thinking)
        for width in [1.0, 1.0, 0.55] {
            results.addArrangedSubview(ShimmerBar(theme: theme, fraction: width))
        }
        if theme.animates {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.45
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            thinking.layer.add(pulse, forKey: "pulse")
        }
        reveal()
    }

    private func show(_ result: Outcome) {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch result.kind {
        case .noMistakes:
            results.addArrangedSubview(badgeRow(symbol: "checkmark.seal.fill", color: .systemGreen, text: result.main, bold: true))
        case .problem:
            results.addArrangedSubview(badgeRow(symbol: "exclamationmark.circle.fill", color: .systemOrange, text: result.main, bold: false))
        case .answer:
            results.addArrangedSubview(label(result.main, size: 18))
            for fix in result.fixes {
                results.addArrangedSubview(fixRow(fix))
            }
            for line in result.extra where !line.isEmpty {
                results.addArrangedSubview(label(line, size: 13, secondary: true))
            }
            if let replacement = result.replacement {
                results.addArrangedSubview(useThisRow(replacement))
            }
        }
        reveal()
    }

    /// A grammar fix: the wrong part struck through in red → the fix in green, then why.
    private func fixRow(_ fix: GrammarCorrection) -> UIView {
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: fix.original, attributes: [
            .font: theme.font(14), .foregroundColor: UIColor.systemRed,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: UIColor.systemRed,
        ]))
        line.append(NSAttributedString(string: "  →  ", attributes: [.font: theme.font(14), .foregroundColor: theme.secondaryText]))
        line.append(NSAttributedString(string: fix.fix, attributes: [.font: theme.font(14, weight: .semibold), .foregroundColor: UIColor.systemGreen]))
        let change = UILabel()
        change.numberOfLines = 0
        change.attributedText = line
        let row = UIStackView(arrangedSubviews: [change])
        row.axis = .vertical
        row.spacing = 1
        if !fix.reason.isEmpty {
            row.addArrangedSubview(label(fix.reason, size: 12, secondary: true))
        }
        return row
    }

    private func badgeRow(symbol: String, color: UIColor, text: String, bold: Bool) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: bold ? 26 : 20, weight: .semibold)))
        icon.tintColor = color
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let message = label(text, size: bold ? 16 : 14)
        if bold {
            message.font = theme.font(16, weight: .semibold)
        }
        let row = UIStackView(arrangedSubviews: [icon, message])
        row.spacing = 10
        row.alignment = bold ? .center : .top
        if bold && theme.animates {
            // The check pops in.
            icon.transform = CGAffineTransform(scaleX: 0.2, y: 0.2).rotated(by: -0.5)
            icon.alpha = 0
            UIView.animate(withDuration: 0.5, delay: 0.05, usingSpringWithDamping: 0.55, initialSpringVelocity: 0) {
                icon.transform = .identity
                icon.alpha = 1
            }
        }
        return row
    }

    /// "Use this": turns into a green "Replaced" with a check, then swaps the text in.
    private func useThisRow(_ replacement: String) -> UIView {
        let button = UIButton(configuration: useThisConfiguration(done: false))
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button, button.configuration?.title != "Replaced" else { return }
            button.configuration = self.useThisConfiguration(done: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if self.theme.animates {
                button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0) {
                    button.transform = .identity
                }
            }
            let delay = self.theme.animates ? 0.55 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.onReplace?(replacement)
            }
        }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [button, UIView()])
        row.alignment = .center
        return row
    }

    private func useThisConfiguration(done: Bool) -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .filled()
        }
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = done ? .systemGreen : theme.accent
        configuration.baseForegroundColor = .white
        configuration.image = UIImage(systemName: done ? "checkmark" : "arrow.right.to.line",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        configuration.imagePadding = 6
        configuration.title = done ? "Replaced" : "Use this"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 14, weight: .semibold)
            return attributes
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        return configuration
    }

    /// The result card rises into place, and scrolls into view in a long panel.
    private func reveal() {
        let wasHidden = resultCard.isHidden
        resultCard.isHidden = false
        layoutIfNeeded()
        if theme.animates {
            let rise = CASpringAnimation(keyPath: "transform.translation.y")
            rise.fromValue = wasHidden ? 12 : 6
            rise.toValue = 0
            rise.damping = 22
            rise.stiffness = 260
            rise.duration = rise.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.2
            results.layer.add(rise, forKey: "rise")
            results.layer.add(fade, forKey: "fade")
        }
        scrollView.scrollRectToVisible(resultCard.convert(resultCard.bounds, to: scrollView), animated: theme.animates)
    }

    private enum EngineChoice {
        case ready(AIEngine)
        case unavailable(Outcome)
    }

    /// The engine for the chosen provider, or why it can't answer.
    private var engine: EngineChoice {
        switch provider {
        case .claude:
            return .ready(ClaudeAIEngine(apiKey: claudeAPIKey))
        case .apple:
#if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard AIAssistant.isAvailable else {
                    return .unavailable(.problem("Apple Intelligence isn't available. It needs an iPhone 15 Pro or newer with Apple Intelligence turned on, or switch to Claude below."))
                }
                return .ready(AppleAIEngine())
            }
#endif
            return .unavailable(.problem("Apple Intelligence needs iOS 26 on a supported iPhone. Switch to Claude below to use your Claude API key instead."))
        }
    }

    private static func perform(_ action: Action, input: String, engine: AIEngine, showsRomaji: Bool) async -> Outcome {
        func reading(_ text: String?) -> String {
            guard let text else { return "" }
            return showsRomaji ? text + "  ·  " + KanaConverter.romaji(from: text) : text
        }
        do {
            switch action {
            case .grammar:
                switch try await engine.checkGrammar(input) {
                case .noMistakes:
                    return Outcome(main: "No mistakes found", kind: .noMistakes)
                case .unreliable:
                    return .problem("The answer didn't look like a fix, so it isn't shown.")
                case .corrected(let text, let corrections):
                    return Outcome(main: text, fixes: corrections, replacement: text)
                }
            case .explain:
                guard let explanation = try await engine.explain(input) else {
                    return .problem("The answer didn't look like an explanation, so it isn't shown.")
                }
                return Outcome(main: explanation.meaning, extra: [reading(explanation.reading)] + explanation.notes)
            case .kanji:
                guard let converted = try await engine.convertToKanji(input) else {
                    return .problem("The conversion changed the words, so it isn't shown.")
                }
                return Outcome(main: converted, replacement: converted)
            case .casual, .polite, .honorific:
                let target: Politeness = action == .casual ? .casual : action == .polite ? .polite : .honorific
                guard let rewritten = try await engine.rewrite(input, as: target) else {
                    return .problem("Already in that style, or the answer didn't look right.")
                }
                return Outcome(main: rewritten, replacement: rewritten)
            case .toEnglish:
                guard let english = try await engine.translateToEnglish(input) else {
                    return .problem("The answer didn't look like a translation, so it isn't shown.")
                }
                return Outcome(main: english, replacement: english)
            case .formal, .friendly, .shorter:
                let style: EnglishStyle = action == .formal ? .formal : action == .friendly ? .casual : .shorter
                guard let rewritten = try await engine.rewriteEnglish(input, as: style) else {
                    return .problem("The answer didn't look right, so it isn't shown.")
                }
                return Outcome(main: rewritten, replacement: rewritten)
            case .toCasual, .toPolite, .toHonorific:
                // 敬語 is a polite translation, then a 敬語 rewrite.
                guard let translation = try await engine.translate(input, style: action == .toCasual ? .casual : .polite) else {
                    return .problem("The answer didn't look like a translation, so it isn't shown.")
                }
                if action == .toHonorific, let honorific = try await engine.rewrite(translation.japanese, as: .honorific) {
                    return Outcome(main: honorific, replacement: honorific)
                }
                return Outcome(main: translation.japanese, extra: [reading(translation.reading)], replacement: translation.japanese)
            }
        } catch let failure as ClaudeAIEngine.Failure {
            return .problem(failure.localizedDescription)
        } catch let failure as LocalizedError where failure.errorDescription?.hasPrefix("Apple's on-device safety filter") == true {
            return .problem(failure.localizedDescription)
        } catch {
            if engine is ClaudeAIEngine {
                return .problem("Couldn't reach Claude. Check your connection, and that Full Access is on.")
            }
            return .problem("Apple Intelligence couldn't answer here (\(error.localizedDescription)). Try the Apple Intelligence test in the RomaKey app, or switch to Claude below.")
        }
    }
}

/// A rounded placeholder line with a highlight sweeping across it, while the model thinks.
private final class ShimmerBar: UIView {
    private let fraction: CGFloat
    private let fill = UIView()
    private let shine = CAGradientLayer()
    private let animates: Bool

    init(theme: KeyboardTheme, fraction: CGFloat) {
        self.fraction = fraction
        animates = theme.animates
        super.init(frame: .zero)
        fill.backgroundColor = theme.text.withAlphaComponent(0.1)
        fill.layer.cornerRadius = 6
        fill.clipsToBounds = true
        addSubview(fill)
        let glow = theme.text.withAlphaComponent(0.14).cgColor
        shine.colors = [UIColor.clear.cgColor, glow, UIColor.clear.cgColor]
        shine.startPoint = CGPoint(x: 0, y: 0.5)
        shine.endPoint = CGPoint(x: 1, y: 0.5)
        fill.layer.addSublayer(shine)
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        shine.frame = CGRect(x: -fill.bounds.width, y: 0, width: fill.bounds.width, height: bounds.height)
        guard animates, shine.animation(forKey: "sweep") == nil, fill.bounds.width > 0 else { return }
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -fill.bounds.width / 2
        sweep.toValue = fill.bounds.width * 1.5
        sweep.duration = 1.3
        sweep.repeatCount = .infinity
        shine.add(sweep, forKey: "sweep")
    }
}
