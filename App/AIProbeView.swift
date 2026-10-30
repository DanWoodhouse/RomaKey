import KeyboardCore
import SwiftUI

/// Tests Apple's on-device model in the app and inside the keyboard, so we know whether
/// AI features (grammar checking, translation) can live in the keyboard itself.
struct AIProbeView: View {
    private let defaults = UserDefaults(suiteName: KeyboardSettings.appGroup) ?? .standard
    @State private var appResult: AIProbeResult?
    @State private var keyboardResult: AIProbeResult?
    @State private var isRunning = false
    @State private var keyboardRequested = false

    var body: some View {
        List {
            Section {
                Text("Checks whether Apple Intelligence's on-device model works here, how fast it is, and how much memory it uses. It runs a grammar check on one Japanese and one English sentence.")
                    .font(.footnote)
            }

            Section("このアプリ · In the app") {
                Button {
                    Task {
                        isRunning = true
                        appResult = await AIProbe.run(process: "App")
                        isRunning = false
                    }
                } label: {
                    HStack {
                        Text("Run the test")
                        if isRunning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                if let appResult {
                    ResultRows(result: appResult)
                }
            }

            Section {
                Button(keyboardRequested ? "Waiting for the keyboard…" : "Test in the keyboard") {
                    defaults.set(true, forKey: AIProbe.requestKey)
                    keyboardRequested = true
                }
                if let keyboardResult {
                    ResultRows(result: keyboardResult)
                }
            } header: {
                Text("キーボード · In the keyboard")
            } footer: {
                Text("Tap the button, then open any app with a text field and switch to the ローマ字 or かな keyboard. It runs the test once and shows a summary in its suggestion bar. Come back here for the full result. Needs Allow Full Access.")
            }
        }
        .navigationTitle("Apple Intelligence")
        .onAppear(perform: refresh)
        .refreshable { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        keyboardResult = AIProbe.load(process: "Keyboard", from: defaults)
        keyboardRequested = defaults.bool(forKey: AIProbe.requestKey)
    }
}

private struct ResultRows: View {
    let result: AIProbeResult

    var body: some View {
        LabeledContent("Model", value: result.availability)
        if let supportsJapanese = result.supportsJapanese {
            LabeledContent("Japanese", value: supportsJapanese ? "Supported" : "Not supported")
        }
        if let contextSize = result.contextSize {
            LabeledContent("Context", value: "\(contextSize) tokens")
        }
        LabeledContent("Memory", value: String(format: "%.0f MB → %.0f MB", result.memoryBeforeMB, result.memoryAfterMB))
        ForEach(result.tests, id: \.input) { test in
            VStack(alignment: .leading, spacing: 4) {
                Text(test.input).font(.subheadline.weight(.semibold))
                Text(test.output).font(.callout)
                Text(String(format: "%.2f s", test.seconds)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        Text(result.date.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
