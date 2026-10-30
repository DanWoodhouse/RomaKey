import UIKit

/// Liquid Glass on iOS 26, and the thinnest blur material before it.
enum Glass {
    static func effect(tint: UIColor? = nil) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = tint
            return glass
        }
        return UIBlurEffect(style: .systemUltraThinMaterial)
    }

    /// Before iOS 26 the blur has no tint of its own, so a coloured layer stands in for it.
    static var tintsItself: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    static func view(cornerRadius: CGFloat, tint: UIColor? = nil) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect(tint: tint))
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }
}

/// A Control Centre module: a rounded pane of glass, with an optional small title above its content.
final class GlassCard: UIView {
    private let glass: UIVisualEffectView
    private let rim = CAShapeLayer()
    private let cornerRadius: CGFloat

    init(theme: KeyboardTheme, title: String?, content: UIView, cornerRadius: CGFloat = 24,
         insets: UIEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 9, right: 8)) {
        self.cornerRadius = cornerRadius
        glass = Glass.view(cornerRadius: cornerRadius)
        super.init(frame: .zero)
        addSubview(glass)
        if !Glass.tintsItself {
            // A bright edge and a soft shadow, as Liquid Glass draws on iOS 26.
            glass.contentView.backgroundColor = theme.panel.withAlphaComponent(0.28)
            rim.fillColor = nil
            rim.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
            rim.lineWidth = 0.5
            layer.addSublayer(rim)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.14
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 6)
        }
        let stack = UIStackView(arrangedSubviews: [content])
        stack.axis = .vertical
        stack.spacing = 8
        if let title {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = theme.text.withAlphaComponent(0.62)
            let inset = UIView()
            label.translatesAutoresizingMaskIntoConstraints = false
            inset.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: inset.trailingAnchor),
                label.topAnchor.constraint(equalTo: inset.topAnchor),
                label.bottomAnchor.constraint(equalTo: inset.bottomAnchor),
            ])
            stack.insertArrangedSubview(inset, at: 0)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        rim.path = path
        layer.shadowPath = path
    }
}
