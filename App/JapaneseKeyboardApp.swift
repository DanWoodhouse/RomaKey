import SwiftUI

@main
struct JapaneseKeyboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var text = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("セットアップ · Setup") {
                    Label("Settings → General → Keyboard → Keyboards", systemImage: "1.circle")
                    Label("Add New Keyboard… → 日本語キーボード → ローマ字 and かな", systemImage: "2.circle")
                    Label("Tap each one and turn on Allow Full Access, so they can use your settings", systemImage: "3.circle")
                    Label("Use 🌐 to switch between them in any app", systemImage: "4.circle")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                Section("試してみる · Try it") {
                    TextField("ここに入力 · Type here", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("設定 · Settings", systemImage: "slider.horizontal.3")
                    }
                }
                Section {
                    Text("Dictionary data comes from JMdict, by the Electronic Dictionary Research and Development Group, used under the Creative Commons Attribution-ShareAlike 3.0 licence.")
                        .font(.footnote)
                    Link("JMdict project", destination: URL(string: "https://www.edrdg.org/jmdict/j_jmdict.html")!)
                    Link("Licence", destination: URL(string: "https://www.edrdg.org/edrdg/licence.html")!)
                    Text("Emoji names and keywords come from Emojibase (MIT licence). GIFs: Powered by GIPHY.")
                        .font(.footnote)
                    Link("Emojibase", destination: URL(string: "https://emojibase.dev")!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("日本語キーボード")
        }
    }
}
