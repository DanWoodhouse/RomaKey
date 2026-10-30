import KeyboardCore
import UIKit

/// Sizes shared by both keyboards, so switching between them doesn't change the height.
enum KeyboardMetrics {
    static let candidateBarHeight: CGFloat = 40
    static let rowCount = 4

    static func rowHeight(compact: Bool, height: KeyboardSettings.Height) -> CGFloat {
        if compact { return 40 }
        switch height {
        case .compact: return 48
        case .standard: return 54
        case .tall: return 60
        }
    }

    static func height(compact: Bool, height: KeyboardSettings.Height) -> CGFloat {
        candidateBarHeight + CGFloat(rowCount) * rowHeight(compact: compact, height: height)
    }
}

/// Loads the bundled dictionary once per keyboard process, off the main thread.
enum DictionaryLoader {
    private static var dictionary: JapaneseDictionary?
    private static var isLoading = false
    private static var waiting: [(JapaneseDictionary?) -> Void] = []

    /// Calls back on the main thread.
    static func load(_ completion: @escaping (JapaneseDictionary?) -> Void) {
        if let dictionary {
            completion(dictionary)
            return
        }
        waiting.append(completion)
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = JapaneseDictionary.bundled()
            DispatchQueue.main.async {
                dictionary = loaded
                isLoading = false
                let callbacks = waiting
                waiting = []
                callbacks.forEach { $0(loaded) }
            }
        }
    }
}

/// Hosts a keyboard view and connects it to the text field being edited.
class KeyboardHostController: UIInputViewController {
    private(set) lazy var textOutput: TextOutput = ProxyTextOutput(controller: self)
    let feedback = KeyFeedback()
    private(set) var settings = KeyboardSettings()
    private var contentView: KeyboardViewBase!
    private var heightConstraint: NSLayoutConstraint?

    /// Settings are shared with the app through an App Group, which needs Full Access.
    /// Without it they fall back to the defaults.
    let sharedDefaults = UserDefaults(suiteName: KeyboardSettings.appGroup)

    /// Subclasses create their engine and view here.
    func makeContentView() -> KeyboardViewBase {
        fatalError("Subclasses must override makeContentView()")
    }

    /// Subclasses pass the dictionary to their engine.
    func dictionaryDidLoad(_ dictionary: JapaneseDictionary?) {}

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
        DictionaryLoader.load { [weak self] dictionary in
            self?.dictionaryDidLoad(dictionary)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-read every time the keyboard appears, so changes made in the app apply straight away.
        settings = sharedDefaults.map(KeyboardSettings.init(defaults:)) ?? KeyboardSettings()
        feedback.playsSounds = settings.keySounds
        feedback.playsHaptics = settings.haptics && hasFullAccess
        contentView.apply(settings)
        updateHeight()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Only valid once the view is on screen. Phones with a system globe below the
        // keyboard return false; this is per device, so it never changes with the language.
        contentView.update(showsGlobe: needsInputModeSwitchKey)
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        contentView.textDidChange()
    }

    private func updateHeight() {
        let height = KeyboardMetrics.height(
            compact: traitCollection.verticalSizeClass == .compact,
            height: settings.height
        )
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

    var textBeforeCursor: String? {
        proxy?.documentContextBeforeInput
    }
}
