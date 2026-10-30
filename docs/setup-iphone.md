# Putting RomaKey on your iPhone

This takes about 30–60 minutes the first time, most of it waiting for Xcode to download.

> **Expect a few build errors the first time.** The Swift code was written without a Mac, so it has never been compiled. Errors at step 4 or 8 are normal: copy them (or a screenshot) back to Claude and they'll get fixed.

## What you need

- **A Mac** that can run **Xcode 26** (needed for the Apple Intelligence framework; check the macOS requirement on the App Store page).
- **Your iPhone and its cable.** Any iPhone on iOS 16 or later runs the keyboards. The ✨ Apple Intelligence features need **iOS 26 on an iPhone 15 Pro or newer**, with Apple Intelligence turned on; otherwise you can use Claude for ✨ instead.
- **An Apple ID.** Two options:

| | Free Apple ID | Apple Developer Program (US$99 a year) |
|---|---|---|
| Install on your own iPhone | Yes | Yes |
| How long it lasts | 7 days, then re-run from Xcode | A year |
| Settings from the app reach the keyboards (App Groups) | Xcode may refuse App Groups for a free "Personal Team" (see step 6) | Yes |

Start with a free Apple ID to try it; join the programme later if you keep using it.

## 1. Install Xcode

1. Install **Xcode** from the Mac App Store and open it once. Let it install its extra components, and the **iOS** platform when asked.
2. **Xcode → Settings → Accounts → +** → Apple ID, and sign in. You'll see a team called "*Your Name* (Personal Team)", or your developer team if you've joined the programme.

## 2. Install XcodeGen

The Xcode project is generated from `project.yml`, so it never has merge conflicts. In **Terminal**:

```sh
# Homebrew, if you don't have it (instructions at https://brew.sh):
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install xcodegen
```

## 3. Get the code

The repository is private, so sign in to GitHub when asked (or use GitHub Desktop: **File → Clone repository → RomaKey**).

```sh
cd ~/Developer          # or wherever you keep projects (mkdir -p ~/Developer first)
git clone https://github.com/DanWoodhouse/RomaKey.git
cd RomaKey
```

## 4. Check the core logic builds

This compiles and tests the typing logic on its own, which is the quickest way to find errors:

```sh
cd Packages/KeyboardCore
swift test
cd ../..
```

If it prints errors, send them to Claude before going on. When it ends with `Executed … tests, with 0 failures`, the core is good.

## 5. Set your team

1. Find your **team ID**: Xcode → Settings → Accounts → select your Apple ID → the team → the 10-character ID (paid accounts can also see it at developer.apple.com → Membership).
2. Open `project.yml` in any text editor and fill it in:

   ```yaml
   DEVELOPMENT_TEAM: "ABCDE12345"
   ```

3. Generate the project and open it:

   ```sh
   xcodegen
   open JapaneseKeyboard.xcodeproj
   ```

Run `xcodegen` again whenever `project.yml` changes or you pull new code.

## 6. Signing (only if Xcode complains)

Select the project in the left sidebar, then each of the three targets (**JapaneseKeyboard**, **RomajiKeyboard**, **KanaKeyboard**) → **Signing & Capabilities**:

- **"Personal development teams … do not support the App Groups capability"** (free Apple ID): click the 🗑 next to **App Groups** in all three targets. Everything still works, except that settings, colours and the photo chosen in the app don't reach the keyboards (use the keyboard's own ⚙︎ panel instead), and the app's Apple Intelligence test can't check the keyboard. You'll need to do this again after each `xcodegen`.
- **"The app identifier … cannot be registered"** (someone else has the ID): change `bundleIdPrefix` in `project.yml` (for example to `com.yourname`), and change the App Group to match in two places: `group.com.danwoodhouse.JapaneseKeyboard` in `project.yml` and `appGroup` in `Packages/KeyboardCore/Sources/KeyboardCore/KeyboardSettings.swift`. Then run `xcodegen` again.

## 7. Get the iPhone ready

1. Plug it in and unlock it. Tap **Trust** on the phone when asked.
2. Turn on **Developer Mode**: Settings → Privacy & Security → **Developer Mode** → on, then restart when asked. (The option appears once Xcode has seen the phone; if it's missing, try step 8 first.)

## 8. Build and run

1. At the top of the Xcode window, choose the **JapaneseKeyboard** scheme and your iPhone as the destination.
2. Press **⌘R** (Product → Run). The first build takes a few minutes.
3. Errors are listed in the Issue navigator (⌘5). Copy them to Claude.
4. If the phone says **Untrusted Developer**: Settings → General → **VPN & Device Management** → your Apple ID → **Trust**, then run again.

The RomaKey app opens on the phone when it works.

## 9. Turn the keyboards on

1. Settings → General → Keyboard → **Keyboards** → **Add New Keyboard…** → **日本語キーボード** → add **ローマ字** (and **かな** if you like).
2. Tap **ローマ字** in the list → **Allow Full Access** → on (and the same for かな). Full Access lets the keyboards read the app's settings and use haptics, paste, GIFs and Claude. Nothing you type is sent anywhere unless you use GIFs or choose Claude for ✨.
3. Optional: remove Apple's own Japanese romaji keyboard from the list, so 🌐 doesn't cycle through it.

## 10. Try it

- Open Notes, tap in a note, and hold 🌐 (bottom left, below the keyboard) to pick **ローマ字**.
- Work through the test checklist in the web preview: it covers every feature.
- Clear the text and tap ⚙︎ in the keyboard's toolbar for its Control Centre-style settings. **Open RomaKey** there opens the app's Settings.
- In the RomaKey app: **Settings → Apple Intelligence test** checks whether Apple's model works inside the keyboard on your phone. Run it before trying ✨ with Apple. To use Claude instead, add your API key under **Settings → ✨ AI**.

## Debugging the keyboard

Keyboards run inside other apps, so to see their logs and stop at breakpoints:

1. Choose the **RomajiKeyboard** (or KanaKeyboard) scheme and press ⌘R.
2. Xcode asks which app to run it in: pick **Notes** (or any app with a text field).
3. Switch to the keyboard in that app. Logs appear in Xcode's console, and breakpoints work.

If the keyboard flicks back to another keyboard, it has probably crashed or run out of memory (keyboards get about 50 MB). Send Claude the crash from the console, or from the phone: Settings → Privacy & Security → Analytics & Improvements → Analytics Data.

## Updating

```sh
cd ~/Developer/RomaKey
git pull
xcodegen
```

Then ⌘R in Xcode. With a free Apple ID, do this at least every 7 days or the app stops opening.
