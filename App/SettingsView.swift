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
}

struct SettingsView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Turn on **Allow Full Access** for the keyboards so they can read these settings. They have no network code: nothing you type leaves your phone.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.footnote)
            }

            Section {
                NavigationLink {
                    AppearanceView(store: store)
                } label: {
                    HStack {
                        Label("見た目 · Look", systemImage: "paintpalette")
                        Spacer()
                        Text(lookSummary).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Themes, your own colours, a background photo and keyboard height.")
            }

            Section {
                Picker("Start in", selection: $store.settings.startingMode) {
                    Text("あ Japanese").tag(KeyboardSettings.StartingMode.japanese)
                    Text("EN English").tag(KeyboardSettings.StartingMode.english)
                    Text("辞 Dictionary").tag(KeyboardSettings.StartingMode.dictionary)
                    Text("Last used").tag(KeyboardSettings.StartingMode.lastUsed)
                }
                Toggle("あ Japanese", isOn: store.languageKeyIncludes(.japanese))
                Toggle("EN English", isOn: store.languageKeyIncludes(.english))
                Toggle("辞 Dictionary", isOn: store.languageKeyIncludes(.dictionary))
            } header: {
                Text("ローマ字 · Language key")
            } footer: {
                Text("The modes the language key steps through. Long-press the key to jump straight to any mode.")
            }

            Section("ローマ字 · Typing") {
                Toggle("Auto-capitalisation", isOn: $store.settings.autoCapitalization)
                Toggle("Double-space for full stop", isOn: $store.settings.doubleSpacePeriod)
                Toggle("Key popups", isOn: $store.settings.keyPopups)
            }

            Section {
                Toggle("Flick only", isOn: $store.settings.flickOnly)
                Picker("Flick sensitivity", selection: $store.settings.flickSensitivity) {
                    Text("Gentle").tag(KeyboardSettings.FlickSensitivity.gentle)
                    Text("Normal").tag(KeyboardSettings.FlickSensitivity.normal)
                    Text("Quick").tag(KeyboardSettings.FlickSensitivity.quick)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("かな · Flick")
            } footer: {
                Text("Flick only: tapping あ twice types ああ instead of い. Quick sensitivity needs a shorter slide.")
            }

            Section {
                Toggle("Show English meanings", isOn: $store.settings.showMeanings)
                Toggle("Full-width space in Japanese", isOn: $store.settings.fullWidthSpace)
                Toggle("Space bar moves cursor", isOn: $store.settings.spaceBarCursor)
                Toggle("Key sounds", isOn: $store.settings.keySounds)
                Toggle("Haptics", isOn: $store.settings.haptics)
            } header: {
                Text("両方 · Both keyboards")
            } footer: {
                Text("Meanings appear under kanji suggestions. Hold the space bar and slide to move the cursor. Haptics need Full Access.")
            }

            Section {
                NavigationLink {
                    AIProbeView()
                } label: {
                    Label("Apple Intelligence test", systemImage: "sparkles")
                }
            } footer: {
                Text("Checks whether Apple's on-device model can run inside the keyboard, for future grammar checking.")
            }

            Section {
                Button("Reset to defaults", role: .destructive) {
                    store.settings = KeyboardSettings()
                }
            }
        }
        .navigationTitle("設定 · Settings")
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
