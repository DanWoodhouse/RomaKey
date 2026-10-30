import KeyboardCore
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let engine = KeyboardEngine(mode: .japanese)
    private lazy var proxyOutput = ProxyTextOutput(controller: self)
    private var keyboardView: KeyboardView!
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        engine.output = proxyOutput

        keyboardView = KeyboardView(engine: engine, globeTarget: self)
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        engine.onChange = { [weak self] in self?.keyboardView.reload() }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Only valid once the view is on screen. Phones with a system globe below the
        // keyboard return false; this is per device, so it never changes with the language.
        engine.showsGlobe = needsInputModeSwitchKey
        updateHeight()
    }

    private func updateHeight() {
        let height = keyboardView.preferredHeight(compact: traitCollection.verticalSizeClass == .compact)
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

/// Sends the engine's output to the host app's text field.
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
}
