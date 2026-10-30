# On-device grammar checking: how hard is it?

Researched 30 Oct 2026. Nothing here is built yet.

## The constraint that decides everything

A keyboard extension runs in its own process with a small memory allowance. Apple doesn't publish the number; developers report roughly 30–70 MB, and going over it kills the keyboard mid-typing. The keyboard already uses some of that for the dictionary. So "on device" really means one of:

1. **Inside the keyboard**: must be small.
2. **In the app** (a "check my writing" screen): no real memory limit, but you leave the app you're typing in.
3. **In a system process**: Apple's on-device model runs outside our process, so it may not count against the keyboard's allowance.

## Options

| Option | English | Japanese | Fits in the keyboard? | Effort |
|---|---|---|---|---|
| Apple `UITextChecker` | Spelling only | No | Yes | 1–2 days |
| Small Japanese rules using our dictionary | – | A few common mistakes | Yes | 2–4 days |
| Harper (open-source grammar checker) | Good | No | Probably not (memory) | 1–2 weeks |
| Apple Foundation Models (on-device LLM) | Good | Good | Unknown: needs a device test | ~1 week to prototype |
| Japanese morphological analyser (MeCab, Sudachi) | – | Foundation for real rules | No: dictionaries are tens of MB or more | Weeks |

### 1. `UITextChecker`: spelling, today

Built into UIKit, tiny, works offline. It gives misspelled ranges and guesses, which could appear in the candidate bar in EN mode. It doesn't check grammar, and it doesn't support Japanese. A cheap first step.

### 2. Harper: real English grammar, but heavy

[Harper](https://github.com/Automattic/harper) (Automattic, Apache-2.0, written in Rust) is the best offline English grammar checker that's practical to embed. I ran its WebAssembly build (`harper.js` 3.0.0) on test sentences:

| Sentence | Harper's suggestion |
|---|---|
| I **has** **a** apple | has → have, a → an |
| **Their** going to the store **tomorow** | Their → They're, tomorow → tomorrow |
| She **don't** like it | don't → doesn't |
| I **could of** done it | could of → could have |
| This is a **very very** good idea | very very → very |
| Yesterday I go to the park | *(missed the tense)* |
| I am interesting in anime | *(missed interesting → interested)* |

- **Speed:** 4–50 ms per sentence, fast enough to check as you type.
- **Memory:** about **170 MB** of WebAssembly memory once loaded, and 1.9 s to set up. A native Rust build would avoid the WebAssembly overhead, but most of that is its English dictionary and rule data. That makes it very unlikely to fit in a keyboard extension.
- **Work:** compile the Rust crate for iOS (an XCFramework via UniFFI or cbindgen), write a Swift wrapper, and build the UI. The crate downloads were blocked in this environment, so I couldn't measure a native build.

**Verdict:** a good fit for a "Check my writing" screen in the app, not for live checking inside the keyboard.

### 3. Apple Foundation Models: the only route that covers Japanese well

iOS 26 gives apps Apple's on-device language model through the Foundation Models framework. A prompt plus guided generation, e.g. `@Generable struct Correction { var original: String; var suggestion: String; var reason: String }`, could check both English and Japanese, including tense, particles (は/が, に/で) and politeness consistency.

- **Unknowns, so test on a device first:**
  - Apple's documentation doesn't say whether the framework works inside a keyboard extension.
  - The model runs in a system process, which may avoid the memory problem, but that's unconfirmed.
  - The model is loaded and unloaded by the system and can report itself as not ready.
- **Requirements:** an Apple Intelligence iPhone (15 Pro or later) with Apple Intelligence turned on, and a supported language. Japanese is supported by Apple Intelligence.
- **Latency:** seconds rather than milliseconds, so it would be a **Check** button that shows corrections in the candidate bar, not live checking.
- **Context:** the keyboard only sees the text near the cursor (`documentContextBeforeInput`), usually the current sentence or paragraph. That's enough for sentence-level checks.

### 4. Japanese rules without an LLM

Apple's NaturalLanguage framework splits Japanese into words, but developers report that it doesn't tag Japanese parts of speech, so proper grammar rules would need a morphological analyser, and their dictionaries are too big for a keyboard. A few useful checks are still cheap with what we have:

- Doubled particles: をを, はは, がが
- ら抜き言葉: 見れる → 見られる, using the dictionary's verb entries
- Mixing です/ます with だ/である in the same text
- Wrong small kana from flick typing, e.g. つ where っ was meant: low precision, so maybe not

## Recommendation

1. **Now (a few days):** English spelling suggestions with `UITextChecker` in EN mode, plus the cheap Japanese checks.
2. **Next (about a week):** prototype a Foundation Models **Check** button inside the keyboard on a real Apple Intelligence iPhone. If it works in the extension, it's the best option for a Japanese learner, because it covers both languages and can explain *why*.
3. **Optional:** Harper behind a "Check my writing" screen in the app, if strong English checking matters more than staying in the keyboard.

## Sources

- Harper: [README](https://raw.githubusercontent.com/Automattic/harper/master/README.md), [Automattic acquisition](https://techcrunch.com/2024/11/21/wordpress-com-owner-automattic-snaps-up-grammar-checker-harper); measurements above are my own, from `harper.js` 3.0.0 on npm
- Foundation Models: [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel.md), [WWDC26: What's new](https://developer.apple.com/videos/play/wwdc2026/241/), [code-along Q&A notes on model loading](https://gist.github.com/stinger/81891077161002819c0ec233f73edc74), [forum thread on language availability](https://developer.apple.com/forums/thread/805378)
- Keyboard memory: [developer report of a ~30–48 MB limit](https://developer.apple.com/forums/topics/machine-learning-and-ai/machine-learning-and-ai-foundation-models?page=2&sortBy=created&sortOrder=ASC) (one developer's figure, not official)
- Japanese part-of-speech tagging: [Apple developer forum thread](https://developer.apple.com/forums/thread/116377), [zenn.dev article](https://zenn.dev/h1d3mun3/articles/22deddbabee46d)
