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
                    Label("Use 🌐 to switch between them in any app", systemImage: "3.circle")
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
            }
            .navigationTitle("日本語キーボード")
        }
    }
}
