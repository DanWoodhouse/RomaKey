import KeyboardCore
import SwiftUI
import UIKit

/// Runs every AI mode's test cases on this device's model and scores them, so prompts can be
/// checked (and re-checked after each iOS update) in one tap.
struct AIPromptCheckView: View {
    @State private var results: [AIEvalResult] = []
    @State private var isRunning = false
    @State private var progress = 0
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runAll() }
                } label: {
                    HStack {
                        Text(isRunning ? "Checking \(progress) of \(AIEvaluation.cases.count)…" : "Check all prompts")
                        if isRunning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                if !results.isEmpty && !isRunning {
                    Button("Copy report") {
                        UIPasteboard.general.string = report
                        message = "Copied. Paste it into a message to share the results."
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Runs \(AIEvaluation.cases.count) test sentences through every mode, including correct sentences that must be left alone and questions that must be translated, not answered. Takes a minute or two.")
            }

            ForEach(AIMode.allCases, id: \.self) { mode in
                let modeResults = results.filter { $0.testCase.mode == mode }
                if !modeResults.isEmpty {
                    Section {
                        ForEach(modeResults) { result in
                            ResultRow(result: result)
                        }
                    } header: {
                        Text("\(Self.title(of: mode)) · \(modeResults.filter(\.passed).count)/\(modeResults.count) passed")
                    }
                }
            }
        }
        .navigationTitle("Prompt check")
    }

    private func runAll() async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), AIAssistant.isAvailable else {
            message = "Apple Intelligence isn't available on this device."
            return
        }
        isRunning = true
        message = nil
        results = []
        progress = 0
        for testCase in AIEvaluation.cases {
            progress += 1
            results.append(await AIAssistant.evaluate(testCase))
        }
        isRunning = false
        #else
        message = "This build doesn't include Foundation Models (needs Xcode 26 or later)."
        #endif
    }

    static func title(of mode: AIMode) -> String {
        switch mode {
        case .grammar: return "Grammar check"
        case .translate: return "Translate"
        case .politeness: return "Politeness"
        case .explain: return "Explain"
        case .kanji: return "Kanji conversion"
        case .englishRewrite: return "English rewrite"
        case .toEnglish: return "Japanese → English"
        }
    }

    /// Plain text with everything needed to improve a prompt: versions, device, every output.
    private var report: String {
        let device = UIDevice.current
        var lines = [
            "Prompt check · \(Date().formatted(date: .abbreviated, time: .shortened))",
            "\(device.systemName) \(device.systemVersion) · locale \(Locale.current.identifier)",
            "Passed \(results.filter(\.passed).count)/\(results.count)",
            "",
        ]
        for mode in AIMode.allCases {
            let modeResults = results.filter { $0.testCase.mode == mode }
            guard !modeResults.isEmpty else { continue }
            lines.append("== \(Self.title(of: mode)): \(modeResults.filter(\.passed).count)/\(modeResults.count)")
            for result in modeResults {
                let style = result.testCase.style.map { " [\($0.rawValue)]" } ?? ""
                lines.append("\(result.passed ? "PASS" : "FAIL") \(result.testCase.input)\(style) (\(result.testCase.note), \(String(format: "%.1f", result.seconds))s)")
                lines.append("  → " + result.raw.replacingOccurrences(of: "\n", with: "\n    "))
                for failure in result.failures {
                    lines.append("  ✗ \(failure)")
                }
            }
            lines.append("")
        }
        lines.append("Prompts: " + promptKeys.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    private var promptKeys: [String] {
        [AIPrompts.grammar(for: "日本語").key, AIPrompts.grammar(for: "English").key]
            + [Politeness.casual, .polite].map { AIPrompts.translate(style: $0).key }
            + Politeness.allCases.map { AIPrompts.politeness($0).key }
            + [AIPrompts.explain.key, AIPrompts.kanji.key, AIPrompts.toEnglish.key]
            + EnglishStyle.allCases.map { AIPrompts.englishRewrite($0).key }
    }
}

private struct ResultRow: View {
    let result: AIEvalResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)
                Text(result.testCase.input).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1fs", result.seconds)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(result.testCase.note + (result.testCase.style.map { " · \($0.rawValue)" } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.raw).font(.callout)
            ForEach(result.failures, id: \.self) { failure in
                Text("✗ " + failure).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
