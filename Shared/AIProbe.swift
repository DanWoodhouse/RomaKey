import Foundation
import KeyboardCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A one-off test of Apple's on-device model (Foundation Models), run in the app or inside a
/// keyboard. It answers the questions the documentation doesn't: does the model work inside a
/// keyboard extension, how fast is it here, and how much of the keyboard's memory does it use.
struct AIProbeResult: Codable, Equatable {
    struct Test: Codable, Equatable {
        var input: String
        var output: String
        var seconds: Double
    }

    var date: Date
    /// "App" or "Keyboard".
    var process: String
    var availability: String
    var supportsJapanese: Bool?
    var contextSize: Int?
    var tests: [Test] = []
    var memoryBeforeMB: Double
    var memoryAfterMB: Double
}

enum AIProbe {
    /// Set by the app; the next keyboard to appear runs the test and clears it.
    static let requestKey = "aiProbeRequested"

    /// One deliberate mistake in each: を should be に, and go/buy/a should be went/bought/an.
    static let samples = [
        "私は昨日学校を行きました。",
        "Yesterday I go to the park and buy a apple.",
    ]

    static func run(process: String) async -> AIProbeResult {
        let before = memoryFootprintMB()
        var result = AIProbeResult(
            date: Date(),
            process: process,
            availability: "Needs iOS 26 or later",
            memoryBeforeMB: before,
            memoryAfterMB: before
        )
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            result = await runModel(result)
        }
        #else
        result.availability = "Built without Foundation Models (needs Xcode 26 or later)"
        #endif
        result.memoryAfterMB = memoryFootprintMB()
        return result
    }

    // MARK: - Saving results for the app to show

    private static func key(for process: String) -> String {
        "aiProbeResult.\(process)"
    }

    static func save(_ result: AIProbeResult, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: key(for: result.process))
        }
    }

    static func load(process: String, from defaults: UserDefaults) -> AIProbeResult? {
        guard let data = defaults.data(forKey: key(for: process)) else { return nil }
        return try? JSONDecoder().decode(AIProbeResult.self, from: data)
    }

    /// A one-line summary, for the keyboard's candidate bar.
    static func summary(of result: AIProbeResult) -> String {
        let times = result.tests.map { String(format: "%.1fs", $0.seconds) }.joined(separator: ", ")
        var parts = ["Apple Intelligence: \(result.availability)"]
        if !times.isEmpty {
            parts.append(times)
        }
        parts.append(String(format: "%.0f→%.0f MB", result.memoryBeforeMB, result.memoryAfterMB))
        return parts.joined(separator: " · ")
    }

    /// This process's memory use, as counted against the extension memory limit.
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func runModel(_ result: AIProbeResult) async -> AIProbeResult {
        var result = result
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            result.availability = "Available"
        case .unavailable(.deviceNotEligible):
            result.availability = "This device doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            result.availability = "Apple Intelligence is turned off in Settings"
        case .unavailable(.modelNotReady):
            result.availability = "The model isn't ready yet (still downloading?)"
        case .unavailable(let reason):
            result.availability = "Unavailable: \(reason)"
        }
        result.supportsJapanese = model.supportsLocale(Locale(identifier: "ja_JP"))
        if #available(iOS 26.4, *) {
            result.contextSize = model.contextSize
        }
        guard model.isAvailable else { return result }

        // The same grammar check the keyboard will use, prompts and validation included.
        for sample in samples {
            let start = Date()
            do {
                let output: String
                switch try await AIAssistant.checkGrammar(sample) {
                case .noMistakes:
                    output = "No mistakes found"
                case .corrected(let text, let corrections):
                    output = ([text] + corrections.map { "• \($0.original) → \($0.fix): \($0.reason)" }).joined(separator: "\n")
                case .unreliable:
                    output = "Rejected: the model rewrote the text instead of fixing it"
                }
                result.tests.append(.init(input: sample, output: output, seconds: Date().timeIntervalSince(start)))
            } catch {
                result.tests.append(.init(
                    input: sample,
                    output: "Error: \(error.localizedDescription)",
                    seconds: Date().timeIntervalSince(start)
                ))
            }
        }
        return result
    }
    #endif
}
