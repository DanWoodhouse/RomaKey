import KeyboardCore
import SwiftUI
import UIKit

/// Keeps the settings in the App Group the keyboards read from, saving on every change.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults(suiteName: KeyboardSettings.appGroup) ?? .standard

    @Published var settings: KeyboardSettings {
        didSet { settings.save(to: defaults) }
    }

    /// The saved background photo, for the preview.
    @Published private(set) var backgroundImage: UIImage?

    init() {
        settings = KeyboardSettings(defaults: defaults)
        if settings.backgroundImageID != nil, let url = KeyboardSettings.backgroundImageURL {
            backgroundImage = UIImage(contentsOfFile: url.path)
        }
    }

    enum PhotoError: Error {
        case unreadable
        case noSharedContainer
    }

    /// Saves a photo for the keyboards to use, scaled down so they can load it cheaply.
    func setBackgroundImage(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw PhotoError.unreadable }
        guard let url = KeyboardSettings.backgroundImageURL else { throw PhotoError.noSharedContainer }
        let scaled = image.scaledDown(toFit: 1400)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { throw PhotoError.unreadable }
        try jpeg.write(to: url, options: .atomic)
        backgroundImage = scaled
        // A new ID tells the keyboards to reload the file.
        settings.backgroundImageID = UUID().uuidString
    }

    func removeBackgroundImage() {
        if let url = KeyboardSettings.backgroundImageURL {
            try? FileManager.default.removeItem(at: url)
        }
        backgroundImage = nil
        settings.backgroundImageID = nil
    }

    /// Binding for one mode's toggle. At least two modes must stay on, so the key still switches.
    func languageKeyIncludes(_ mode: InputMode) -> Binding<Bool> {
        Binding(
            get: { self.settings.languageKeyModes.contains(mode) },
            set: { isOn in
                var modes = Set(self.settings.languageKeyModes)
                if isOn {
                    modes.insert(mode)
                } else if modes.count > 2 {
                    modes.remove(mode)
                }
                self.settings.languageKeyModes = InputMode.allCases.filter(modes.contains)
            }
        )
    }

    /// Whether one key's secondary character is on ("q" … "m", or "ー").
    func secondaryEnabled(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !self.settings.disabledSecondaryKeys.contains(key) },
            set: { isOn in
                var disabled = self.settings.disabledSecondaryKeys.filter { $0 != key }
                if !isOn {
                    disabled.append(key)
                }
                self.settings.disabledSecondaryKeys = disabled
            }
        )
    }
}

/// The settings hub, laid out like the iPhone's Settings app: one row per area, each opening
/// its own page. The keyboard's ⚙︎ panel opens straight here with Open RomaKey.
struct SettingsView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Turn on **Allow Full Access** for the keyboards so they can read these settings. Nothing you type leaves your phone, except GIF searches once you add a KLIPY key and ✨ requests if you choose Claude.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.footnote)
            }

            Section {
                page("見た目 · Look", icon: "paintpalette.fill", color: .pink, detail: lookSummary) {
                    AppearanceView(store: store)
                }
                page("入力 · Typing", icon: "keyboard.fill", color: .blue, detail: modeSummary) {
                    TypingSettingsView(store: store)
                }
                page("キー · Key extras", icon: "arrow.up.square.fill", color: .indigo,
                     detail: store.settings.keySecondaries ? (store.settings.swipeUpSecondaries ? "Swipe up" : "Hold") : "Off") {
                    KeyExtrasView(store: store)
                }
                page("かな · Flick", icon: "hand.draw.fill", color: .teal, detail: store.settings.flickSensitivity.rawValue.capitalized) {
                    FlickSettingsView(store: store)
                }
            }

            Section {
                page("候補 · Suggestions", icon: "text.badge.checkmark", color: .green,
                     detail: store.settings.autocorrect ? "Autocorrect on" : "Autocorrect off") {
                    SuggestionSettingsView(store: store)
                }
                page("✨ AI", icon: "sparkles", color: .purple,
                     detail: store.settings.aiProvider == .apple ? "Apple" : "Claude") {
                    AISettingsView(store: store)
                }
                page("GIF", icon: "photo.on.rectangle.angled", color: .orange,
                     detail: store.settings.klipyAPIKey.isEmpty ? "Off" : store.settings.gifRating.uppercased()) {
                    GIFSettingsView(store: store)
                }
                page("感触 · Sound & motion", icon: "speaker.wave.2.fill", color: .red, detail: feelSummary) {
                    FeelSettingsView(store: store)
                }
            }

            Section {
                page("Apple Intelligence test", icon: "cpu", color: .gray, detail: nil) {
                    AIProbeView()
                }
            } footer: {
                Text("Checks whether Apple's on-device model can run inside the keyboard on this iPhone.")
            }

            Section {
                Button("Forget learned words and kanji choices", role: .destructive) {
                    store.settings.learningResetID = UUID().uuidString
                }
                Button("Reset to defaults", role: .destructive) {
                    store.settings = KeyboardSettings()
                }
            }
        }
        .navigationTitle("設定 · Settings")
    }

    /// A row like the Settings app's: a white symbol on a coloured rounded square, the page's
    /// name, and a short summary of what's set.
    private func page<Destination: View>(_ title: String, icon: String, color: Color, detail: String?,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                Spacer()
                if let detail {
                    Text(detail).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension SettingsView {
    var lookSummary: String {
        var parts = [store.settings.theme == .custom ? "Custom" : store.settings.theme.rawValue.capitalized]
        if store.settings.backgroundImageID != nil {
            parts.append("photo")
        }
        return parts.joined(separator: " · ")
    }

    var modeSummary: String {
        switch store.settings.startingMode {
        case .japanese: return "あ"
        case .english: return "EN"
        case .dictionary: return "辞"
        case .lastUsed: return "Last used"
        }
    }

    var feelSummary: String {
        let on = [store.settings.keySounds ? "Sounds" : nil, store.settings.haptics ? "Haptics" : nil].compactMap { $0 }
        return on.isEmpty ? "Quiet" : on.joined(separator: " · ")
    }
}

extension UIImage {
    /// The image shrunk so its longer side is at most `maxDimension` pixels.
    func scaledDown(toFit maxDimension: CGFloat) -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let ratio = min(1, maxDimension / max(pixelWidth, pixelHeight))
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
