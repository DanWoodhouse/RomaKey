import KeyboardCore
import PhotosUI
import SwiftUI

/// Theme, custom colours and background photo, with a live preview of the keyboard.
struct AppearanceView: View {
    @ObservedObject var store: SettingsStore
    @State private var photo: PhotosPickerItem?
    @State private var photoError: String?

    private var settings: KeyboardSettings { store.settings }

    var body: some View {
        Form {
            Section {
                KeyboardPreview(settings: settings, image: store.backgroundImage)
                    .listRowInsets(EdgeInsets())
            }

            Section("テーマ · Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(KeyboardSettings.Theme.allCases, id: \.self) { theme in
                        ThemeSwatch(theme: theme, custom: settings.customColors, isSelected: settings.theme == theme) {
                            store.settings.theme = theme
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(ThemeColors.fields.indices, id: \.self) { index in
                    let field = ThemeColors.fields[index]
                    ColorPicker(Self.label(for: field.name), selection: colorBinding(field.keyPath), supportsOpacity: false)
                }
                Menu("Start from a preset…") {
                    ForEach(KeyboardSettings.Theme.allCases.filter { $0 != .custom }, id: \.self) { theme in
                        Button("\(ThemeSwatch.name(of: theme)) · light") { copyPreset(theme, dark: false) }
                        if theme != .sumi {
                            Button("\(ThemeSwatch.name(of: theme)) · dark") { copyPreset(theme, dark: true) }
                        }
                    }
                }
            } header: {
                Text("カスタム · Custom colours")
            } footer: {
                Text("Changing a colour switches to the Custom theme. Custom colours stay the same in light and dark mode.")
            }

            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(store.backgroundImage == nil ? "Choose a photo" : "Choose a different photo",
                          systemImage: "photo")
                }
                if store.backgroundImage != nil {
                    Button("Remove photo", role: .destructive) {
                        store.removeBackgroundImage()
                    }
                    LabeledSlider(title: "Darken", value: $store.settings.backgroundDim, range: 0...0.8)
                    Toggle("Blur", isOn: $store.settings.backgroundBlur)
                }
                LabeledSlider(title: "Key opacity", value: $store.settings.keyOpacity, range: 0.3...1)
                if let photoError {
                    Text(photoError).foregroundStyle(.red)
                }
            } header: {
                Text("背景 · Background photo")
            } footer: {
                Text("Lower key opacity lets the photo show through the keys. Darken keeps the labels readable on bright photos.")
            }

            Section("サイズ · Height") {
                Picker("Height", selection: $store.settings.height) {
                    Text("Compact").tag(KeyboardSettings.Height.compact)
                    Text("Standard").tag(KeyboardSettings.Height.standard)
                    Text("Tall").tag(KeyboardSettings.Height.tall)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Font", selection: $store.settings.keyFont) {
                    Text("System").font(.system(size: 17)).tag(KeyboardSettings.KeyFont.system)
                    Text("Rounded 丸").font(.system(size: 17, design: .rounded)).tag(KeyboardSettings.KeyFont.rounded)
                    Text("Serif 明朝").font(.system(size: 17, design: .serif)).tag(KeyboardSettings.KeyFont.serif)
                    Text("Mono").font(.system(size: 17, design: .monospaced)).tag(KeyboardSettings.KeyFont.mono)
                }
                Picker("Text size", selection: $store.settings.textSize) {
                    Text("Small").tag(KeyboardSettings.TextSize.small)
                    Text("Standard").tag(KeyboardSettings.TextSize.standard)
                    Text("Large").tag(KeyboardSettings.TextSize.large)
                }
                .pickerStyle(.segmented)
                Toggle("Bold keys", isOn: $store.settings.boldKeys)
            } header: {
                Text("文字 · Font")
            } footer: {
                Text("For the keys and suggestions. Japanese uses the matching Hiragino font: Maru Gothic for rounded, Mincho for serif.")
            }
        }
        .navigationTitle("見た目 · Look")
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    try store.setBackgroundImage(data)
                    photoError = nil
                } catch {
                    photoError = "Couldn't use that photo. Try another one."
                }
                photo = nil
            }
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ThemeColors, UInt32>) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(hex: store.settings.customColors[keyPath: keyPath])) },
            set: { color in
                store.settings.customColors[keyPath: keyPath] = UIColor(color).hexValue
                store.settings.theme = .custom
            }
        )
    }

    private func copyPreset(_ theme: KeyboardSettings.Theme, dark: Bool) {
        store.settings.customColors = ThemePalette.colors(for: theme, dark: dark)
        store.settings.theme = .custom
    }

    private static func label(for field: String) -> String {
        switch field {
        case "background": return "Background"
        case "key": return "Keys"
        case "specialKey": return "Function keys (⇧ ⌫ 123)"
        case "pressedKey": return "Pressed key"
        case "text": return "Text"
        case "secondaryText": return "Readings and meanings"
        case "accent": return "Accent"
        default: return field
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

/// A preset or the custom theme, drawn as a tiny keyboard.
private struct ThemeSwatch: View {
    let theme: KeyboardSettings.Theme
    let custom: ThemeColors
    let isSelected: Bool
    let action: () -> Void

    static func name(of theme: KeyboardSettings.Theme) -> String {
        switch theme {
        case .system: return "System"
        case .ai: return "藍 Ai"
        case .sakura: return "桜 Sakura"
        case .matcha: return "抹茶 Matcha"
        case .sumi: return "墨 Sumi"
        case .custom: return "Custom"
        }
    }

    var body: some View {
        let colors = KeyboardTheme(theme: theme, custom: custom)
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(uiColor: index == 3 ? colors.specialKey : colors.key))
                            .frame(width: 12, height: 16)
                    }
                }
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme == .system ? Color(uiColor: .systemGray4) : Color(uiColor: colors.background))
                )
                Text(Self.name(of: theme))
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A non-interactive picture of the keyboard in the chosen look.
struct KeyboardPreview: View {
    let settings: KeyboardSettings
    let image: UIImage?

    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        let theme = KeyboardTheme(settings)
        GeometryReader { geometry in
            // Same proportions as the real keyboard: ten key-widths per row.
            let unit = (geometry.size.width - 8) / 10
            ZStack {
                Color(uiColor: settings.theme == .system ? .systemGray5 : theme.background)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: settings.backgroundBlur ? 14 : 0)
                        .clipped()
                    Color.black.opacity(settings.backgroundDim)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        candidate("猫", reading: "ねこ", meaning: "cat", theme: theme)
                        candidate("ネコ", reading: nil, meaning: nil, theme: theme)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 0) {
                            if index == 2 { key("⇧", unit: unit, width: 1.5, special: true, theme: theme) }
                            ForEach(Array(rows[index]), id: \.self) { letter in
                                key(String(letter), unit: unit, theme: theme)
                            }
                            if index == 2 { key("⌫", unit: unit, width: 1.5, special: true, theme: theme) }
                        }
                    }
                    HStack(spacing: 0) {
                        key("123", unit: unit, width: 1.25, special: true, theme: theme)
                        key("あ", unit: unit, width: 1.25, special: true, theme: theme)
                        key("空白", unit: unit, width: 4.75, theme: theme)
                        key("ー", unit: unit, theme: theme)
                        key("改行", unit: unit, width: 1.75, special: true, theme: theme)
                    }
                }
            }
        }
        .frame(height: 40 + 4 * 46)
        .clipped()
    }

    private func key(_ label: String, unit: CGFloat, width: CGFloat = 1, special: Bool = false, theme: KeyboardTheme) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(uiColor: special ? theme.specialKey : theme.key))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            .overlay(
                Text(label)
                    .font(.system(size: label.count == 1 ? 18 : 13))
                    .foregroundStyle(Color(uiColor: theme.text))
            )
            .padding(.horizontal, 2.5)
            .padding(.vertical, 4)
            .frame(width: unit * width, height: 46)
    }

    private func candidate(_ word: String, reading: String?, meaning: String?, theme: KeyboardTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(word).font(.system(size: 17)).foregroundStyle(Color(uiColor: theme.text))
                if let reading, settings.showMeanings {
                    Text(reading).font(.system(size: 10)).foregroundStyle(Color(uiColor: theme.secondaryText))
                }
            }
            if let meaning, settings.showMeanings {
                Text(meaning).font(.system(size: 10)).foregroundStyle(Color(uiColor: theme.secondaryText))
            }
        }
    }
}
