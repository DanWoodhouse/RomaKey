import KeyboardCore
import SwiftUI

// The pages behind each row of the settings hub.

struct TypingSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
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
                Toggle("Left-handed mode wheel", isOn: $store.settings.leftHandedWheel)
            } header: {
                Text("モードキー · Mode key")
            } footer: {
                Text("The modes a tap on the mode key steps through. Drag from the key for the mode wheel: ← あ, ↖ EN, ↑ 辞, ↗ かな, → other keyboards. Left-handed mirrors it: → あ, ← other keyboards.")
            }

            Section {
                Toggle("Auto-capitalisation", isOn: $store.settings.autoCapitalization)
                Toggle("Double-space for full stop", isOn: $store.settings.doubleSpacePeriod)
                Toggle("Key popups", isOn: $store.settings.keyPopups)
                Toggle("Space bar moves cursor", isOn: $store.settings.spaceBarCursor)
                Toggle("Full-width space in Japanese", isOn: $store.settings.fullWidthSpace)
            } header: {
                Text("入力 · Typing")
            } footer: {
                Text("Hold the space bar and slide to move the cursor.")
            }
        }
        .navigationTitle("入力 · Typing")
    }
}

/// Each letter's second character (q → 1, a → @ …) and the ー/- key's punctuation, with a switch
/// per key so the ones you never want stay out of the way.
struct KeyExtrasView: View {
    @ObservedObject var store: SettingsStore
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }

    var body: some View {
        Form {
            Section {
                Toggle("Key extras", isOn: $store.settings.keySecondaries)
                Toggle("Swipe up for them", isOn: $store.settings.swipeUpSecondaries)
                    .disabled(!store.settings.keySecondaries)
            } footer: {
                Text("Swipe up on a key for the small character in its corner, or hold it. Keys with more than one choice (like ー/-) still show them all when you hold.")
            }

            Section {
                VStack(spacing: 8) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 5) {
                            ForEach(row, id: \.self) { letter in
                                keyToggle(letter, label: letter, extra: KeyboardLayout.secondary(for: letter) ?? "")
                            }
                        }
                    }
                    HStack {
                        keyToggle(KeyboardLayout.longVowelKeyName, label: "ー",
                                  extra: KeyboardLayout.punctuation(japanese: true).map(\.label).joined())
                            .frame(maxWidth: 140)
                    }
                }
                .padding(.vertical, 6)
                .disabled(!store.settings.keySecondaries)
                .opacity(store.settings.keySecondaries ? 1 : 0.4)
                Button("Turn all on") { store.settings.disabledSecondaryKeys = [] }
                    .disabled(store.settings.disabledSecondaryKeys.isEmpty)
            } header: {
                Text("キーごと · Each key")
            } footer: {
                Text("Tap a key to turn its extra on or off. Faded keys type only their letter, even when swiped or held.")
            }
        }
        .navigationTitle("キー · Key extras")
    }

    private func keyToggle(_ key: String, label: String, extra: String) -> some View {
        let isOn = store.secondaryEnabled(key)
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 1) {
                Text(extra)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                Text(label)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemFill))
            )
            .opacity(isOn.wrappedValue ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(extra)")
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }
}

struct FlickSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Flick only", isOn: $store.settings.flickOnly)
                Picker("Flick sensitivity", selection: $store.settings.flickSensitivity) {
                    Text("Gentle").tag(KeyboardSettings.FlickSensitivity.gentle)
                    Text("Normal").tag(KeyboardSettings.FlickSensitivity.normal)
                    Text("Quick").tag(KeyboardSettings.FlickSensitivity.quick)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Flick only: tapping あ twice types ああ instead of い. Quick sensitivity needs a shorter slide.")
            }
        }
        .navigationTitle("かな · Flick")
    }
}

struct SuggestionSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Autocorrect", isOn: $store.settings.autocorrect)
                Toggle("Word suggestions", isOn: $store.settings.wordSuggestions)
                Toggle("Predictive text", isOn: $store.settings.predictiveText)
                Toggle("Emoji suggestions", isOn: $store.settings.emojiSuggestions)
            } footer: {
                Text("English suggestions and autocorrect use Apple's built-in spell checker, your text replacements and words you type often. Press delete straight after an autocorrection to undo it. Predictive text offers the next word after each word you finish, learning the pairs you type (in Japanese too). All of this stays on your phone.")
            }

            Section {
                Toggle("Show English meanings", isOn: $store.settings.showMeanings)
                Toggle("Show romaji readings", isOn: $store.settings.showRomaji)
            } header: {
                Text("読み方 · Readings")
            } footer: {
                Text("Meanings appear under kanji suggestions. Romaji readings add the spelling after the kana (猫 ねこ neko), in suggestions and dictionary entries.")
            }

            Section {
                Button("Forget learned words and kanji choices", role: .destructive) {
                    store.settings.learningResetID = UUID().uuidString
                }
            } footer: {
                Text("The keyboard remembers which kanji you pick for each reading and the words you type often.")
            }
        }
        .navigationTitle("候補 · Suggestions")
    }
}

struct AISettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Answered by", selection: $store.settings.aiProvider) {
                    Text("Apple Intelligence").tag(KeyboardSettings.AIProvider.apple)
                    Text("Claude").tag(KeyboardSettings.AIProvider.claude)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(store.settings.aiProvider == .apple
                     ? "Apple Intelligence runs on your iPhone, so nothing you type leaves it. It needs iOS 26 on an iPhone 15 Pro or newer with Apple Intelligence on. Finish a sentence and tap ✨ in the keyboard."
                     : "Claude answers with the same instructions, using your own API key and the Claude Opus 5.5 model. The text you ask about is sent to Anthropic, and the keyboard needs Allow Full Access. You can switch back to Apple in the ✨ panel at any time.")
            }

            if store.settings.aiProvider == .claude {
                Section("Claude") {
                    SecureField("Claude API key", text: $store.settings.claudeAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a key at platform.claude.com", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                }
            }
        }
        .navigationTitle("✨ AI")
    }
}

struct GIFSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                SecureField("GIPHY API key", text: $store.settings.giphyAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Content rating", selection: $store.settings.gifRating) {
                    Text("G").tag("g")
                    Text("PG").tag("pg")
                    Text("PG-13").tag("pg-13")
                    Text("R").tag("r")
                }
                Link("Get a free key at developers.giphy.com", destination: URL(string: "https://developers.giphy.com/dashboard/")!)
            } footer: {
                Text("GIFs are off until you add a key. When on, what you search for is sent to GIPHY (the keyboard needs Allow Full Access). Tap a GIF to copy it, then paste it into your message: iOS doesn't let keyboards insert images directly. Free keys allow about 100 searches an hour.")
            }
        }
        .navigationTitle("GIF")
    }
}

struct FeelSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Key sounds", isOn: $store.settings.keySounds)
                Toggle("Haptics", isOn: $store.settings.haptics)
            } footer: {
                Text("Haptics need Allow Full Access.")
            }
            Section {
                Toggle("Animations", isOn: $store.settings.animations)
            } footer: {
                Text("Keys press in, the keyboard dips gently when the mode changes, and panels rise into place. Reduce Motion in the iPhone's Accessibility settings turns them off too.")
            }
        }
        .navigationTitle("感触 · Sound & motion")
    }
}
