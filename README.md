# ローマ字キーボード (Romaji Keyboard)

An iOS custom keyboard for typing Japanese in romaji, where **switching between English and Japanese never moves a key**.

## The idea

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

## Project structure

```
project.yml                      XcodeGen spec (generates the .xcodeproj)
App/                             Container app: setup instructions + a test text field
KeyboardExtension/               The keyboard (UIKit)
  KeyboardViewController.swift   UIInputViewController, talks to the host text field
  KeyboardView.swift             Keys, candidate bar, touch handling
Packages/KeyboardCore/           UI-free logic, unit-tested with `swift test`
  KeyboardLayout.swift           Rows, key widths, frame calculation
  KeyboardEngine.swift           Mode / page / shift state, what each key does
  RomajiComposer.swift           romaji → ひらがな, ひらがな → カタカナ
  RomajiTable.swift              The romaji table
```

## Building

You need a Mac with Xcode 15 or later.

```sh
brew install xcodegen
cd JapaneseKeyboard
xcodegen
open JapaneseKeyboard.xcodeproj
```

To run on a real device, choose your team under *Signing & Capabilities* for both targets. You may also need to change the bundle IDs in `project.yml`.

Run the logic tests without Xcode:

```sh
cd Packages/KeyboardCore
swift test
```

## Enabling the keyboard

Settings → General → Keyboard → Keyboards → Add New Keyboard… → **ローマ字**. Then switch to it with 🌐 in any app.

## How typing works (Japanese mode)

| Input | Result |
|---|---|
| `konnichiha` / `konnnichiha` | こんにちは |
| `kitte`, `matcha` | きって, まっちゃ |
| `ra` `ー` `men` | らーめん |
| `kin'en` | きんえん |
| `, . [ ] / ~` on the 123 page | 、。「」・〜 |
| Shift + letter | typed as a capital letter, not converted |

While you type, the text is underlined (marked text). **Space** or **確定** confirms it. The candidate bar also offers the カタカナ version.

## Next steps

- Kanji conversion: a dictionary plus candidates in the existing bar
- Key-press popups, long-press alternates, swipe gestures
- Reset the composition when the user moves the cursor mid-composition
- Settings (e.g. full-width space, which language to start in)
