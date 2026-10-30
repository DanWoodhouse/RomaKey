# 日本語キーボード (Japanese Keyboard)

An iOS app with two Japanese keyboards:

- **ローマ字**: QWERTY romaji input where **switching between English and Japanese never moves a key**.
- **かな**: the 12-key flick keyboard (フリック入力) most Japanese people use, laid out like the iPhone's built-in one.

Each appears as its own keyboard in Settings and you switch with 🌐, the same as the system keyboards. Both are the same height and share the candidate bar, so switching between them doesn't make anything jump.

## ローマ字 keyboard

The built-in iOS Japanese romaji keyboard adds a `ー` key to the end of the `a s d … l` row. This shifts the whole row left and breaks muscle memory every time you switch language.

Here, both languages share one layout:

```
 q  w  e  r  t  y  u  i  o  p
   a  s  d  f  g  h  j  k  l
 ⇧    z  x  c  v  b  n  m    ⌫
123  🌐  あ/EN   space   ー/-  return
```

- The letter rows are standard QWERTY, with the half-key stagger, in both modes.
- `ー` has a permanent slot in the bottom row. It types `ー` in Japanese and `-` in English.
- The candidate bar is there in English too, so the keyboard's height doesn't change either.
- Switching language only changes labels (`space` ↔ `空白`, `-` ↔ `ー`, `return` ↔ `改行`/`確定`).

This is enforced in code. `KeyboardLayout` has no input-mode parameter at all, and a test checks that every key frame is identical before and after a language switch.

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

In both keyboards, Japanese text is underlined while you type (marked text). **Space** or **確定** confirms it. The candidate bar also offers the カタカナ version.

## Project structure

```
project.yml                      XcodeGen spec (generates the .xcodeproj)
App/                             Container app: setup instructions + a test text field
Shared/                          UI shared by both keyboards
  KeyboardHostController.swift   UIInputViewController base, talks to the host text field
  KeyButton.swift, CandidateBar.swift
RomajiKeyboard/                  ローマ字 keyboard extension
KanaKeyboard/                    かな flick keyboard extension
Packages/KeyboardCore/           UI-free logic, unit-tested with `swift test`
  KeyboardLayout.swift           QWERTY rows, key widths, frame calculation
  KeyboardEngine.swift           QWERTY mode / page / shift state, what each key does
  FlickLayout.swift              12-key grid and what each flick produces
  FlickKeyboardEngine.swift      Flick, tap cycle, ゛゜小, pages
  RomajiComposer.swift           romaji → ひらがな, ひらがな → カタカナ
  RomajiTable.swift              The romaji table
```

## Building

You need a Mac with Xcode 15 or later.

```sh
brew install xcodegen
xcodegen
open JapaneseKeyboard.xcodeproj
```

To run on a real device, choose your team under *Signing & Capabilities* for all three targets. You may also need to change the bundle IDs in `project.yml`.

Run the logic tests without Xcode:

```sh
cd Packages/KeyboardCore
swift test
```

## Enabling the keyboards

Settings → General → Keyboard → Keyboards → Add New Keyboard… → **日本語キーボード**, then turn on **ローマ字** and/or **かな**. Switch between them with 🌐 in any app.

## Next steps

- Kanji conversion: a dictionary plus candidates in the existing bar
- Key-press popups and long-press alternates on the QWERTY keyboard
- Reset the composition when the user moves the cursor mid-composition
- Settings (e.g. flick-only mode, full-width space, which language to start in)
