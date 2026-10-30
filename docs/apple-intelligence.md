# Apple's on-device AI for the keyboard

Researched 30 Oct 2026. The app now includes a test (Settings → **Apple Intelligence test**) that answers the questions below that documentation can't.

## What it is

The **Foundation Models** framework (iOS 26+) gives apps the language model behind Apple Intelligence: about 3 billion parameters, compressed to 2 bits per weight, running on the phone. It's free, works offline, and needs no account or API key.

| | |
|---|---|
| Model versions | Updated with the OS: one for iOS 26.0–26.3, one for 26.4, and a model "rebuilt from the ground up" for iOS 27 ("better at logic and tool calling") |
| Context | `contextSize` reports it; **8,192 tokens** on the current model. That's thousands of characters, far more than a keyboard sees at once |
| Structured output | `@Generable` Swift types: the model is guaranteed to fill in your struct, e.g. `corrected` text plus a list of `explanations` |
| Other | Streaming, tool calling, token counting, and image input (iOS 27) |
| Languages | Multilingual, covering every Apple Intelligence language. **Japanese** has been supported since iOS 18.4 (April 2025) |
| Errors to handle | `rateLimited`, `guardrailViolation`, `refusal`, `unsupportedLanguageOrLocale`, `exceededContextWindowSize`, `assetsUnavailable`, `concurrentRequests` |

**New in iOS 27:** `PrivateCloudComputeLanguageModel` runs Apple's bigger server model through the same API, with a 32k-token context and adjustable reasoning. It's free for apps under 2 million first-time downloads, with daily per-user limits; iCloud+ subscribers get higher limits. It needs an entitlement and a network connection, so in a keyboard it needs Full Access, which ours already requests.

## Requirements

- **iPhone:** Apple Intelligence models only: iPhone 15 Pro / Pro Max, the iPhone 16 family and newer. Standard iPhone 15 and older are not supported. I couldn't load Apple's support page from this environment to check the latest list.
- Apple Intelligence turned on, the model downloaded, and a supported device/Siri language.
- Check at runtime with `SystemLanguageModel.default.availability`. The reasons it can be unavailable are `deviceNotEligible`, `appleIntelligenceNotEnabled` and `modelNotReady`.

**This matters for the "hand my phone to a Japanese friend" case:** AI features only work on newer iPhones, so they must stay optional extras. Typing must never depend on them.

## Speed

Apple's published figures are for the original 2024 model on an iPhone 15 Pro: about **0.6 ms per prompt token** before the first output token, then about **30 tokens per second**. For one sentence (about 200 tokens of instructions and input, about 60 tokens of output) that's roughly **0.1 s to start and about 2 s in total**. There are no published figures for the iOS 27 model; the test measures it on your phone.

So the model fits **on-demand actions** (tap a button, wait a second or two), not anything that runs on every keystroke.

## The keyboard-specific questions

| Question | What's known | The test measures |
|---|---|---|
| Does it run inside a keyboard extension? | **Not documented.** One developer reports it working inside a widget extension (no Apple reply) | Whether it works in the keyboard |
| Memory: keyboards get about 48 MB (third-party figure) | Apple says the OS loads and unloads the model to manage memory, which suggests it runs in a system process rather than ours. Unconfirmed | The keyboard's memory before and after |
| Rate limiting | `rateLimited` "will only happen if your app is running in the background". A visible keyboard should count as foreground. Unconfirmed | Whether a request fails |
| Network / Full Access | The on-device model needs none. Private Cloud Compute needs network, so Full Access | – |
| What text can it see? | The keyboard only sees text near the cursor (`documentContextBeforeInput`), usually the current sentence or paragraph | – |

## What it could add to this keyboard

All on demand, from a ✨ button at the end of the candidate bar. That keeps the keys where they are; the button would only appear when the model is available.

| Feature | What you'd see | Fit |
|---|---|---|
| **Grammar check, both languages** | The corrected sentence as a candidate; tap to replace. Long-press for explanations ("を → に: 行く takes に for destinations") | Best fit. This is the test's exact prompt |
| **Translate a sentence** (辞書 mode) | Type "where is the station", get 駅はどこですか as a candidate | Good: the dictionary does words, the model does sentences |
| **Politeness switch** | Rewrite what you typed as casual / です・ます / 敬語 | Good, and very useful when learning |
| **Explain what I typed** | English meaning and readings for Japanese you've written or received | Good |
| **Whole-sentence kanji conversion** | わたしはきのうがっこうにいきました → 私は昨日学校に行きました | Possible on an explicit 変換 tap; quality from a 3B model is unproven |
| Live suggestions on every keystroke | – | **No**: too slow |

## Risks

- **Device coverage:** only Apple Intelligence iPhones.
- **Quality:** a small model can over-correct or miss mistakes, especially subtle Japanese grammar. Always offer a suggestion, never auto-replace. Use Apple's new Evaluations framework with a set of real learner mistakes to measure it.
- **Model changes:** the model changes with iOS updates, so prompts need re-testing each year.
- **Refusals:** guardrails occasionally refuse harmless text.
- **Undocumented behaviour:** inside keyboard extensions. Hence the test.

## Plan

1. **Run the test on your iPhone** (Settings → Apple Intelligence test): once in the app, then once in the keyboard. It needs Xcode 26+ to build and Full Access for the keyboard.
2. **If it works inside the keyboard:** build the ✨ grammar check first (about a week), then translation and politeness (2–3 days each, reusing the same code).
3. **If it doesn't:** keyboards can't open their app, so offer the AI features as an **action extension** instead. You'd select text in any app → Share → "Check with 日本語キーボード". Action extensions get more memory (around 120 MB, a third-party figure). An in-app writing screen is the other fallback.

## Sources

- Apple: [Foundation Models](https://developer.apple.com/documentation/foundationmodels.md), [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel.md), [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models.md), [GenerationError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror.md), [rateLimited](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/ratelimited(_:).md), [WWDC26: What's new in Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/)
- Model details: [Apple Intelligence Foundation Language Models Tech Report 2025](https://arxiv.org/abs/2507.13575), [2024 speed figures (Apple)](https://machinelearning.apple.com/research/introducing-apple-foundation-models), [VentureBeat summary](https://venturebeat.com/ai/what-we-know-about-apples-on-device-ai)
- Model loading: [Foundation Models code-along Q&A notes](https://gist.github.com/stinger/81891077161002819c0ec233f73edc74)
- Extensions: [widget extension report](https://developer.apple.com/forums/thread/840737), [extension memory limits (React Native docs)](https://reactnative.dev/docs/app-extensions)
- Languages and devices: [Japanese in iOS 18.4 (TechCrunch)](https://techcrunch.com/2025/01/31/apple-intelligence-will-support-more-languages-starting-in-april), [MacTrast](https://www.mactrast.com/2025/01/apple-intelligence-to-add-support-for-eight-additional-languages-in-april/amp/)
