import Foundation

/// The package's bundled data files (dictionary, emoji, word pairs).
///
/// `Bundle.module` stops the process if it can't find the resource bundle, which would take the
/// whole keyboard down, so the places Xcode puts it are checked first: inside the keyboard
/// extension, then inside the app that contains it. `Bundle.module` is the fallback, for
/// `swift test`.
enum CoreResources {
    private static let bundleName = "KeyboardCore_KeyboardCore.bundle"

    static let bundle: Bundle = {
        let main = Bundle.main
        // A keyboard is App.app/PlugIns/Keyboard.appex, so the app is two levels up.
        let app = main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let places = [main.resourceURL, main.bundleURL, app].compactMap { $0 }
        for place in places {
            if let bundle = Bundle(url: place.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        return Bundle.module
    }()

    static func url(_ name: String, _ fileExtension: String) -> URL? {
        bundle.url(forResource: name, withExtension: fileExtension)
    }
}
