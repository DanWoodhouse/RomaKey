# 日本語キーボード (Japanese Keyboard)

An iOS app with two Japanese keyboards:

- **ローマ字**: QWERTY romaji input where **switching between Japanese, English and the dictionary never moves a key**.
- **かな**: the 12-key flick keyboard (フリック入力) most Japanese people use, laid out like the iPhone's built-in one.

Each appears as its own keyboard in Settings and you switch with 🌐, the same as the system keyboards. Both are the same height and share the candidate bar, so switching between them doesn't make anything jump.

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
123  🌐  あ/EN/辞  space  ー/-  return
```

- The letter rows are standard QWERTY, with the half-key stagger, in both modes.
- `ー` has a permanent slot in the bottom row. It types `ー` in Japanese and `-` in English.
- The candidate bar is there in English too, so the keyboard's height doesn't change either.
- Switching mode only changes labels (`space` ↔ `空白`, `-` ↔ `ー`, `return` ↔ `改行`/`確定`).

This is enforced in code. `KeyboardLayout` has no input-mode parameter at all, and a test checks that every key frame is identical in all three modes.

The language key steps through **あ → EN → 辞**. Long-press it to jump straight to one, or choose which modes it steps through in Settings.

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
  🌐  ゛゜小   わ  、。?!  改行
```

- **Flick**: press a key and slide. Left, up, right and down give the rest of its row (あ → い う え お). A guide shows where you'll land.
- **Tap repeatedly** to cycle (あ → い → う …). **→** ends the cycle so you can type the same kana twice (ああ), and **↺** steps back.
- **゛゜小** turns the last kana into its voiced, semi-voiced or small form (は → ば → ぱ, つ → っ → づ).
- **ABC** cycles through the alphabet and ☆123 pages. On the alphabet page, **a/A** flips the case of the last letter.

## Typing and confirming

In both keyboards, Japanese text is underlined while you type (marked text). **Space** or **確定** confirms it as hiragana; tap a suggestion for kanji or katakana instead.

In 辞書 mode the English you type is underlined instead. Space adds a space (for lookups like "thank you"), and **確定** keeps the English as typed.

## Quality of life

- **Space-bar trackpad**: hold the space bar, then slide to move the cursor.
- **Faster delete**: hold delete and after about a second it deletes whole words.
- **Key popups** on the QWERTY keyboard.
- **Auto-capitals** at the start of English sentences, and **double-space** for a full stop.
- The 123 page goes back to letters after a space.
- Settings are re-read every time the keyboard appears, so changes in the app apply straight away.

## Customisation

The app's **設定 · Settings** screen has the following. Theme, colours, photo and height are on its **見た目 · Look** page, which has a live preview:

| Setting | Options |
|---|---|
| Theme | System, 藍 Ai (indigo), 桜 Sakura, 抹茶 Matcha, 墨 Sumi (ink), all adapting to light and dark mode; or Custom |
| Custom colours | Background, keys, function keys, pressed key, text, readings, accent. Start from any preset's light or dark colours |
| Background photo | Any photo from your library, with darken, blur and key opacity (so it shows through the keys) |
| Height | Compact, Standard, Tall |
| Start in | あ, EN, 辞, or the last mode used |
| Language key | Which of あ / EN / 辞 it steps through (at least two) |
| Typing | Auto-capitalisation, double-space full stop, key popups |
| Flick | Flick only (no tap cycling), sensitivity: gentle / normal / quick |
| Both | English meanings under suggestions, full-width space, space-bar cursor, key sounds, haptics |

Settings are stored in an App Group shared by the app and both keyboards. The app scales the photo down to 1400 px and saves it there as a JPEG; the keyboards load an even smaller copy, to stay within a keyboard's tight memory limit. iOS only lets a keyboard use that shared storage, and haptics, with **Allow Full Access** turned on. Without it the keyboards still work, using the default settings. The keyboards contain no networking code.

## Project structure

```
project.yml                      XcodeGen spec (generates the .xcodeproj)
App/                             Container app: setup, a test text field, Settings, Look (theme/colours/photo)
Shared/                          UI shared by both keyboards
  KeyboardHostController.swift   UIInputViewController base: settings, dictionary loading, text proxy
  KeyboardViewBase.swift         Candidate bar + key area + dictionary entry panel
  KeyButton.swift                Keys, popups, delete repeat, space-bar trackpad, haptics
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
  Resources/dictionary.tsv       ~22,000 common JMdict entries, most frequent first
tools/build_dictionary.py        Rebuilds dictionary.tsv from JMdict
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

## Enabling the keyboards

Settings → General → Keyboard → Keyboards → Add New Keyboard… → **日本語キーボード**, then turn on **ローマ字** and/or **かな**. Tap each one and turn on **Allow Full Access** so it can use your settings. Switch between them with 🌐 in any app.

## Next steps

- Full kanji conversion: whole phrases and verb forms (食べた, 食べます), not just dictionary words
- Learn from what you pick, so your choices move up the candidate list
- Reset the composition when the user moves the cursor mid-composition
- A bigger dictionary (all of JMdict) in SQLite, if the common words aren't enough
- Grammar checking: see [docs/grammar-checker.md](docs/grammar-checker.md) for the options and a recommended order
- Apple Intelligence features (grammar check, sentence translation, politeness switch): see [docs/apple-intelligence.md](docs/apple-intelligence.md). Run Settings → **Apple Intelligence test** on your iPhone first; it checks whether the on-device model works inside the keyboard. The prompts for each mode, and the test that scores them, are described in [docs/ai-prompts.md](docs/ai-prompts.md)

## Dictionary licence

The dictionary is built from [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html), the property of the [Electronic Dictionary Research and Development Group](https://www.edrdg.org/), and is used in conformance with the Group's [licence](https://www.edrdg.org/edrdg/licence.html) (Creative Commons Attribution-ShareAlike 3.0). `Packages/KeyboardCore/Sources/KeyboardCore/Resources/dictionary.tsv` is a derived file and is under the same licence; a copy of the licence is next to it. The data came from the `jamdict-data` package (JMdict 1.08, 2020 snapshot).
