import KeyboardCore
import SwiftUI

/// Keeps the settings in the App Group the keyboards read from, saving on every change.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults(suiteName: KeyboardSettings.appGroup) ?? .standard

    @Published var settings: KeyboardSettings {
        didSet { settings.save(to: defaults) }
    }

    init() {
        settings = KeyboardSettings(defaults: defaults)
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

            Section("見た目 · Look") {
                Picker("Theme", selection: $store.settings.theme) {
                    ForEach(KeyboardSettings.Theme.allCases, id: \.self) { theme in
                        ThemeRow(theme: theme).tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Picker("Height", selection: $store.settings.height) {
                    Text("Compact").tag(KeyboardSettings.Height.compact)
                    Text("Standard").tag(KeyboardSettings.Height.standard)
                    Text("Tall").tag(KeyboardSettings.Height.tall)
                }
                .pickerStyle(.segmented)
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
                Button("Reset to defaults", role: .destructive) {
                    store.settings = KeyboardSettings()
                }
            }
        }
        .navigationTitle("設定 · Settings")
    }
}

/// A theme's name with a tiny keyboard drawn in its colours.
private struct ThemeRow: View {
    let theme: KeyboardSettings.Theme

    private var name: String {
        switch theme {
        case .system: return "System"
        case .ai: return "藍 Ai (indigo)"
        case .sakura: return "桜 Sakura"
        case .matcha: return "抹茶 Matcha"
        case .sumi: return "墨 Sumi (ink)"
        }
    }

    var body: some View {
        let colors = KeyboardTheme.named(theme)
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(uiColor: index == 3 ? colors.specialKey : colors.key))
                        .frame(width: 10, height: 14)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme == .system ? Color(uiColor: .systemGray4) : Color(uiColor: colors.background))
            )
            Text(name)
        }
    }
}
