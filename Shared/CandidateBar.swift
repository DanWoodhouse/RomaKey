import UIKit

/// Horizontal strip of conversion choices (ひらがな / カタカナ for now).
final class CandidateBar: UIView {
    var onSelect: ((String) -> Void)?

    var candidates: [String] = [] {
        didSet { if candidates != oldValue { rebuild() } }
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for candidate in candidates {
            var title = AttributedString(candidate)
            title.font = .systemFont(ofSize: 18)
            var configuration = UIButton.Configuration.plain()
            configuration.attributedTitle = title
            configuration.baseForegroundColor = .label
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.onSelect?(candidate)
            })
            stack.addArrangedSubview(button)
        }
    }
}
