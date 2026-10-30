# RomaKey · 日本語キーボード

An iOS app with two Japanese keyboards:

- **ローマ字**: QWERTY romaji input where **switching between Japanese, English and the dictionary never moves a key**.
- **かな**: the 12-key flick keyboard (フリック入力) most Japanese people use, laid out like the iPhone's built-in one.

Both boards live in one keyboard, and the **mode wheel** switches between them (see below). They're the same height and share the candidate bar, so switching doesn't make anything jump. The keyboard is listed twice in Settings, as ローマ字 and かな: the only difference is which board it opens on, so you can hand your phone to someone who types with flicks.

Both keyboards include a Japanese–English dictionary (about 22,000 common words from JMdict). It gives you:

- **辞書 mode** (ローマ字 keyboard): type English and the candidate bar shows the Japanese words like dictionary entries, with word, reading and meaning. Tap one to insert it.
- **Kanji suggestions** while typing Japanese: ねこ → 猫, with the English meaning underneath.
- **Full entries**: long-press any suggestion to see every meaning, with buttons to insert it as kanji, hiragana or katakana.

## ローマ字 keyboard

The built-in iOS Japanese romaji keyboard adds a `ー` key to the end of the `a s d … l` row. This shifts the whole row left and breaks muscle memory every time you switch language.

Here, both languages share one layout:

```
 q  w  e  r  t  y  u  i  o  p
   a  s  d  f  g  h  j  k  l
 ⇧    z  x  c  v  b  n  m    ⌫
123  あ/EN/辞      space      ー/-  return
```

- The letter rows are standard QWERTY, with the half-key stagger, in both modes.
- `ー` has a permanent slot in the bottom row. It types `ー` in Japanese and `-` in English.
- The candidate bar is there in English too, so the keyboard's height doesn't change either.
- Switching mode only changes labels (`space` ↔ `空白`, `-` ↔ `ー`, `return` ↔ `改行`/`確定`).

This is enforced in code. `KeyboardLayout` has no input-mode parameter at all, and a test checks that every key frame is identical in all three modes.

### Mode wheel

There's no 🌐 key: the mode key does its job, so the space bar is wider (4.5 key widths instead of 3.25).

- **Tap** the mode key to step through **あ → EN → 辞** (choose which in Settings).
- **Press and drag** to pick from a half wheel above the key. Hold to see the wheel first, or just swipe: a quick swipe picks without waiting.

```
              辞
        EN          かな
     あ                  🌐
           [mode key]
```

| Swipe | Picks |
|---|---|
| ← left | あ Japanese romaji |
| ↖ up-left | EN English |
| ↑ up | 辞 Dictionary |
| ↗ up-right | かな flick board |
| → right | 🌐 next keyboard |

The slots never move and never change with the current mode (it's only outlined), so each direction becomes muscle memory. Dragging below the key picks the nearest end. Let go without dragging out of the key to close the wheel.

| Input | Result |
|---|---|
| `konnichiha` / `konnnichiha` | こんにちは |
| `kitte`, `matcha` | きって, まっちゃ |
| `ra` `ー` `men` | らーめん |
| `kin'en` | きんえん |
| `, . [ ] / ~` on the 123 page | 、。「」・〜 |
| Shift + letter | typed as a capital letter, not converted |

## かな keyboard (flick)

```
  →    あ    か    さ    ⌫
  ↺    た    な    は   空白
 ABC   ま    や    ら
 かな  ゛゜小   わ  、。?!  改行
```

- **Flick**: press a key and slide. Left, up, right and down give the rest of its row (あ → い う え お). A guide shows where you'll land.
- **Tap repeatedly** to cycle (あ → い → う …). **→** ends the cycle so you can type the same kana twice (ああ), and **↺** steps back.
- **゛゜小** turns the last kana into its voiced, semi-voiced or small form (は → ば → ぱ, つ → っ → づ).
- **ABC** cycles through the alphabet and ☆123 pages. On the alphabet page, **a/A** flips the case of the last letter.
- **かな** (where 🌐 is on the system keyboard) is the mode key: tap it to go back to the ローマ字 board, or drag for the same mode wheel, with the same directions.

## Typing and confirming

In both keyboards, Japanese text is underlined while you type (marked text). **Space** or **確定** confirms it as hiragana; tap a suggestion for kanji or katakana instead.

In 辞書 mode the English you type is underlined instead. Space adds a space (for lookups like "thank you"), and **確定** keeps the English as typed.

## Everyday features

Made to be your only keyboard, without moving any key. When you're not typing, the suggestion bar becomes a **toolbar**:

| | |
|---|---|
| 😊 **Emoji** | Recents and every category in one continuous scroll (the tabs jump to a section and follow along as you scroll), and search in English or Japanese (ねこ, cat → 🐈). Long-press for skin tones; your choice is remembered. Only emoji your iOS version can draw are shown |
| (^_^) **顔文字** | Kaomoji by mood: 嬉しい, ありがとう, 悲しい, 驚き… |
| **GIF** | GIPHY search with your own free API key (Settings → GIF). Tap a GIF to copy it, then paste it; iOS doesn't let keyboards insert images. Off until you add a key, because searches go to GIPHY |
| 📋 **Paste** | Paste the clipboard (needs Full Access) |

While typing:

- **English suggestions and autocorrect** from Apple's spell checker, your iOS text replacements (omw → On my way!) and words you use. Press delete straight after an autocorrection to undo it; the keyboard then learns the word. Contact names are never "corrected".
- **Emoji suggestions:** type cat or ねこ and 🐈 is offered.
- **Predictive text:** after each word, the likely next words (thank → you, going → to), from common English word pairs and from the pairs you type, which come first. In Japanese, after a word you convert, what you usually type next, then particles (猫 → は, が, を…). A 😊 button stays in front of the predictions.
- **✨ AI (Apple Intelligence):** finish a sentence and tap ✨ in the toolbar. Japanese actions come first, English ones underneath. For Japanese text: check grammar, explain (reading, meaning and notes), rewrite as casual, です/ます or 敬語, convert hiragana to kanji, or translate into English. For English text: translate into casual, polite or 敬語 Japanese, check grammar, or rewrite it formal, casual or shorter. "Use this" swaps the result in. By default it runs on Apple's on-device model, so nothing leaves the phone and there's nothing to set up beyond building with Xcode 26: it needs iOS 26 on an iPhone 15 Pro or newer with Apple Intelligence on. Whether the model runs inside a keyboard isn't documented, so run the app's **Apple Intelligence test** first. You can switch to **Claude** in Settings → AI or in the ✨ panel: it uses your own API key and Claude Opus 5.5 with the same prompts, sends the text to Anthropic, and needs Full Access. ✨ sits in the toolbar and, between words, in front of the predictions next to 😊. Prompts and their test set: [docs/ai-prompts.md](docs/ai-prompts.md).
- **Dictation:** iOS doesn't let third-party keyboards use the microphone, so there's no dictation key. The system 🎤 below the keyboard (on iPhones with Face ID) still works while RomaKey is showing, in Japanese or English.
- **Quick settings:** clear the text and tap ⚙︎ in the toolbar. Laid out like Control Centre: round toggles for autocorrect, capitals, predictive text and the other typing settings, plus ✨ AI provider, height and text size, without leaving the app you're in. **Open RomaKey** jumps to the app's full settings (iOS gives keyboards no official way to open an app, so this uses a workaround that's fine on your own phone but App Review might not accept). Without Full Access the changes are saved on the keyboard only.
- **Learned kanji:** the word you picked last time for a reading comes first (きかい → 機会, if that's what you use).
- **Key extras:** every letter has a second character in its corner, as on Gboard (q–p → 1–0, a → @, s → #, … m → ?). **Swipe up** on the key for it straight away, or hold. ー/- holds 、。！？〜 (, . ! ? ~ in EN), and a swipe up gives the first. Each key can be turned off in Settings → Key extras.
- **Accents:** hold a letter (EN and 辞 modes) for é, ü, ñ…

Learned words and choices stay on your phone, in each keyboard's own storage. Settings → **Forget learned words** clears them.

## Quality of life

- **Space-bar trackpad**: hold the space bar, then slide to move the cursor.
- **Faster delete**: hold delete and after about a second it deletes whole words.
- **Key popups** on the QWERTY keyboard.
- **Auto-capitals** at the start of English sentences, and **double-space** for a full stop.
- The 123 page goes back to letters after a space.
- Settings are re-read every time the keyboard appears, so changes in the app apply straight away.
- **Animations**, kept quiet: keys press in, changing labels flash, the whole keyboard dips gently when the mode changes, panels rise into place (or fade, from one panel to another), the mode wheel's chips pop in, and in emoji the tab highlight slides along while the list scrolls smoothly to the section (顔文字 slides in from the side). Off in Settings → Sound & motion, or with Reduce Motion.

## Customisation

The app's **設定 · Settings** screen is laid out like the iPhone's Settings app: one row per area (Look, Typing, Key extras, Flick, Suggestions, ✨ AI, GIF, Sound & motion), each opening its own page. The keyboard's ⚙︎ panel opens it directly with **Open RomaKey** (a `romakey://settings` link). Theme, colours, photo and height are on the **見た目 · Look** page, which has a live preview:

| Setting | Options |
|---|---|
| Theme | System, 藍 Ai (indigo), 桜 Sakura, 抹茶 Matcha, 墨 Sumi (ink), all adapting to light and dark mode; or Custom |
| Custom colours | Background, keys, function keys, pressed key, text, readings, accent. Start from any preset's light or dark colours |
| Background photo | Any photo from your library, with darken, blur and key opacity (so it shows through the keys) |
| Height | Compact, Standard, Tall |
| Font | System, Rounded (Hiragino Maru Gothic), Serif (Hiragino Mincho) or Mono; small, standard or large text; bold keys |
| Background | Opacity, and a gradient into a colour you pick (down, diagonal or across) |
| Keys | Corner radius (square to pill), spacing (tight, standard, airy), shadows, outlines, accent-coloured return key |
| Start in | あ, EN, 辞, or the last mode used |
| Mode key | Which of あ / EN / 辞 a tap steps through (at least two); left-handed (mirrored) mode wheel |
| Typing | Auto-capitalisation, double-space full stop, key popups, space-bar cursor, full-width space |
| Key extras | On or off, swipe up for them or hold only, and each key on or off (q … m and ー) |
| Suggestions | Autocorrect, word suggestions, predictive text, emoji suggestions; forget learned words and kanji choices |
| AI | Apple Intelligence (default) or Claude with your API key |
| GIF | Your GIPHY API key and content rating |
| Flick | Flick only (no tap cycling), sensitivity: gentle / normal / quick |
| Readings | English meanings under suggestions, romaji readings (猫 ねこ neko) |
| Sound & motion | Key sounds, haptics, animations |

Settings are stored in an App Group shared by the app and both keyboards. The app scales the photo down to 1400 px and saves it there as a JPEG; the keyboards load an even smaller copy, to stay within a keyboard's tight memory limit. iOS only lets a keyboard use that shared storage, and haptics, with **Allow Full Access** turned on. Without it the keyboards still work, and the ⚙︎ quick settings are saved on the keyboard itself. The only network requests are GIF searches, once you add a GIPHY key, and ✨ requests if you choose Claude.

## Project structure

```
project.yml                      XcodeGen spec (generates the .xcodeproj)
App/                             Container app: setup, a test text field, Settings, Look (theme/colours/photo)
Shared/                          UI shared by both keyboards
  KeyboardHostController.swift   UIInputViewController base: settings, dictionary loading, text proxy
  KeyboardViewBase.swift         Candidate bar + key area + dictionary entry panel
  KeyButton.swift                Keys, popups, delete repeat, space-bar trackpad, haptics
  EmojiPanel.swift, GIFPanel.swift  Panels shown in place of the keys
  SystemSpellChecker.swift       UITextChecker, and the search field typing goes into
  CandidateBar.swift, DictionaryEntryView.swift, KeyboardTheme.swift
RomajiKeyboard/                  ローマ字 keyboard extension (with the long-press mode menu)
KanaKeyboard/                    かな flick keyboard extension
Packages/KeyboardCore/           UI-free logic, unit-tested with `swift test`
  KeyboardLayout.swift           QWERTY rows, key widths, frame calculation
  KeyboardEngine.swift           あ / EN / 辞 modes, shift, auto-capitals, what each key does
  FlickLayout.swift              12-key grid and what each flick produces
  FlickKeyboardEngine.swift      Flick, tap cycle, ゛゜小, pages
  JapaneseDictionary.swift       English → Japanese search, reading → kanji lookup
  KeyboardSettings.swift         Every customisable option, saved in the App Group
  ThemeColors.swift              Preset palettes and custom colours
  RomajiComposer.swift           romaji → ひらがな, ひらがな ↔ カタカナ
  RomajiTable.swift              The romaji table
  Emoji.swift, Kaomoji.swift     Emoji search and ranking, kaomoji, accented letters
  WordSuggester.swift            English suggestions and autocorrect (spell checker behind a protocol)
  Prediction.swift               Predictive text: next words in English and Japanese
  ModeWheel.swift                The mode wheel's slots and swipe directions
  Learning.swift                 Learned words, kanji choices, recent emoji
  Resources/emoji.tsv            Emoji with English and Japanese keywords (Emojibase, MIT)
  Resources/dictionary.tsv       ~22,000 common JMdict entries, most frequent first
  Resources/bigrams.tsv          Likely next words for ~14,500 English words
tools/build_dictionary.py        Rebuilds dictionary.tsv from JMdict
tools/build_emoji.py             Rebuilds emoji.tsv from Emojibase
tools/build_bigrams.py           Rebuilds bigrams.tsv (predictive text) from SymSpell's bigram list
```

## Building

You need a Mac with Xcode 26 or later (the project links the Foundation Models framework, which older Xcode versions don't have).

```sh
brew install xcodegen
xcodegen
open JapaneseKeyboard.xcodeproj
```

To run on a real device, choose your team under *Signing & Capabilities* for all three targets. You may also need to change the bundle IDs and the App Group (`group.com.danwoodhouse.JapaneseKeyboard`) in `project.yml` and `KeyboardSettings.swift`.

Run the logic tests without Xcode:

```sh
cd Packages/KeyboardCore
swift test
```

## Trying it on your iPhone

Step-by-step, from installing Xcode to typing with it: [docs/setup-iphone.md](docs/setup-iphone.md).

## Web preview

`preview/keyboard-preview.html` runs the keyboards' logic in a browser, with every setting and a test checklist. See [preview/README.md](preview/README.md).

## Enabling the keyboards

Settings → General → Keyboard → Keyboards → Add New Keyboard… → **日本語キーボード**, then turn on **ローマ字** and/or **かな**. Tap each one and turn on **Allow Full Access** so it can use your settings. Swipe right from the mode key to reach your other keyboards.

## Next steps

- Swipe (glide) typing
- Clipboard history
- Full kanji conversion: whole phrases and verb forms (食べた, 食べます), not just dictionary words
- Reset the composition when the user moves the cursor mid-composition
- A bigger dictionary (all of JMdict) in SQLite, if the common words aren't enough
- Grammar checking: see [docs/grammar-checker.md](docs/grammar-checker.md) for the options and a recommended order
- If Apple's model turns out not to run inside keyboards: offer the ✨ features as an action extension instead (see [docs/apple-intelligence.md](docs/apple-intelligence.md))

## Dictionary licence

The dictionary is built from [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html), the property of the [Electronic Dictionary Research and Development Group](https://www.edrdg.org/), and is used in conformance with the Group's [licence](https://www.edrdg.org/edrdg/licence.html) (Creative Commons Attribution-ShareAlike 3.0). `Packages/KeyboardCore/Sources/KeyboardCore/Resources/dictionary.tsv` is a derived file and is under the same licence; a copy of the licence is next to it. The data came from the `jamdict-data` package (JMdict 1.08, 2020 snapshot).

Emoji names and keywords come from [Emojibase](https://emojibase.dev) (MIT licence, copy next to `emoji.tsv`). English word pairs for predictive text come from [SymSpell](https://github.com/wolfgarbe/SymSpell)'s bigram list (MIT), built from [Google Books Ngrams](https://books.google.com/ngrams) (CC BY 3.0); rebuild with `tools/build_bigrams.py`. GIF search is powered by GIPHY.
