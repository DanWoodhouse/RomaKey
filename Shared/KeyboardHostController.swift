import KeyboardCore
import UIKit

/// Sizes shared by both keyboards, so switching between them doesn't change the height.
enum KeyboardMetrics {
    static let candidateBarHeight: CGFloat = 40
    static let rowCount = 4

    static func rowHeight(compact: Bool) -> CGFloat {
        compact ? 40 : 54
    }

    static func height(compact: Bool) -> CGFloat {
        candidateBarHeight + CGFloat(rowCount) * rowHeight(compact: compact)
    }
}

protocol KeyboardContentView: UIView {
    func update(showsGlobe: Bool)
}

/// Hosts a keyboard view and connects it to the text field being edited.
class KeyboardHostController: UIInputViewController {
    private(set) lazy var textOutput: TextOutput = ProxyTextOutput(controller: self)
    private var contentView: KeyboardContentView!
    private var heightConstraint: NSLayoutConstraint?

    /// Subclasses create their engine and view here.
    func makeContentView() -> KeyboardContentView {
        fatalError("Subclasses must override makeContentView()")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentView = makeContentView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Only valid once the view is on screen. Phones with a system globe below the
        // keyboard return false; this is per device, so it never changes with the language.
        contentView.update(showsGlobe: needsInputModeSwitchKey)
        updateHeight()
    }

    private func updateHeight() {
        let height = KeyboardMetrics.height(compact: traitCollection.verticalSizeClass == .compact)
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }
}

/// Sends an engine's output to the host app's text field.
private final class ProxyTextOutput: TextOutput {
    private weak var controller: UIInputViewController?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    func insertText(_ text: String) {
        proxy?.insertText(text)
    }

    func deleteBackward() {
        proxy?.deleteBackward()
    }

    func setMarkedText(_ text: String) {
        proxy?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
    }

    func unmarkText() {
        proxy?.unmarkText()
    }

    func moveCursor(by offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
    }
}
