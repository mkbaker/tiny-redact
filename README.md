# TinyRedact

A tiny macOS menu bar app (in the spirit of [Tiny Clips](https://github.com/jamesmontemagno/tiny-clips)) that takes a
screenshot, finds people's names and other PII, blacks them out, and puts the clean image on your clipboard — ready to
paste into Claude.

Everything runs on your Mac using Apple's built-in text recognition (Vision) and name detection (NaturalLanguage).
Nothing is uploaded, and the unredacted capture is deleted from disk as soon as it's read into memory.

## Use it

1. Press **⌃⌥⌘R** (or click the 👁‍🗨 eye-slash icon in the menu bar → *Capture Redacted Screenshot*).
2. Drag a region. Press **Space** to switch to picking a whole window, **Esc** to cancel.
3. A review window shows what was found:
   - **Click** a black box to un-redact it (it turns into a red dashed outline), click again to re-redact.
   - **Drag** anywhere to add a box by hand for anything it missed.
   - Toggle **Labels** to show or hide the `Person 1` / `Email` tags.
4. Press **Return** (*Copy Redacted*). Paste into Claude.

Also in the menu: **Redact Image on Clipboard** (for a screenshot you already took with ⌘⇧⌃4) and **Redact Image File…**

### Why labels?

Boxes are tagged `Person 1`, `Person 2`, … and the same person keeps the same number everywhere on screen — so if "Jane
Doe" appears in a header and "Jane" appears in a comment, both become `Person 1`. Claude can then reason about *who did
what* ("why does Person 2's row show a different status?") without ever seeing a name.

## What it catches

| Detector | Default | Notes |
| --- | --- | --- |
| Person names (NL tagger) | On | Apple's on-device named-entity model. Best on sentences; weaker on bare table cells. |
| Capitalized-name fallback | On | Any run of 2–4 Capitalized Words that aren't common UI words (`Jane Doe`, `Doe, Jane`, `Mary J. Smith`). Catches table cells and lists the model misses. May over-redact things like product names — fix with *Never redact*. |
| Propagate | On | Once a name is found, every other mention of its parts is hidden too. |
| Emails | On | |
| Phone numbers | On | |
| Street addresses | Off | Single-line only. |
| Always redact list | — | Exact terms, case-insensitive (a customer, a company, a username format). |
| Never redact list | — | Your app's labels that look like names ("Order Status", "Acme Cloud"). |

Redaction is a solid fill burned into a fresh bitmap — not a blur, which can sometimes be reversed — and the output has
no metadata from the original.

**Automatic detection will miss things.** Single first names with no context, names in odd fonts, ALL-CAPS names, and
usernames/handles are the usual gaps. That's why the review step is on by default — glance before you hit Return.

## Build

Requires macOS 14+ and Xcode or the Command Line Tools.

```bash
./build.sh
cp -R build/TinyRedact.app /Applications/
open /Applications/TinyRedact.app
```

TinyRedact lives only in the menu bar: no Dock icon, no window. Look for the eye-slash icon near the clock. If your menu
bar is full, macOS may hide it behind the notch; ⌃⌥⌘R still works.

On first capture macOS asks for **Screen Recording** permission (System Settings → Privacy & Security → Screen & System
Audio Recording). Turn it on, then quit and reopen TinyRedact.

**Updating:** quit TinyRedact, pull, run `./build.sh`, then copy it to `/Applications` again.

### "TinyRedact needs Screen Recording permission" even though it's switched on

`build.sh` signs ad-hoc by default, so every rebuild gets a new code signature, and macOS ties the permission to the
signature. The toggle you see belongs to the previous build. Reset it and grant it again:

1. Quit TinyRedact.
2. Run `tccutil reset ScreenCapture com.local.tinyredact`, or select TinyRedact in that list and click **–**.
3. Open TinyRedact, press ⌃⌥⌘R, and allow the prompt.
4. Quit and reopen TinyRedact.

To stop this happening after every rebuild, sign every build with the same identity. Any Apple Development certificate
works (list yours with `security find-identity -p codesigning`), and so does a free self-signed one: in Keychain Access,
choose *Certificate Assistant → Create a Certificate…*, set Identity Type to *Self Signed Root* and Certificate Type to
*Code Signing*, then build with `SIGN_ID="<certificate name>" ./build.sh`. Do the reset once after the first signed build;
later rebuilds keep the permission.

To open it in Xcode instead: `open Package.swift`.

Run the tests with `swift test`. They use XCTest, so they need full Xcode, not just the Command Line Tools. CI runs
them on every pull request.

## Test the detector without the UI

```bash
.build/release/TinyRedact --redact sample.png sample-redacted.png
```

Prints each detection (label, kind, matched text, box) and writes the redacted PNG. It uses the same settings as the
app, so it's a quick way to tune *Always / Never redact* against a screenshot of your app.

## Files

```
Sources/TinyRedact/
  main.swift            entry point (+ CLI switch)
  AppDelegate.swift     menu bar item, hotkey, capture → detect → review → clipboard
  PIIDetector.swift     OCR + name/email/phone detection, person labels
  Redactor.swift        burns boxes into a new image, PNG export
  ReviewWindow.swift    the click-to-toggle / drag-to-add review window
  Settings.swift        preferences + settings window
  HotKey.swift          global ⌃⌥⌘R via Carbon (no Accessibility permission needed)
  CLI.swift             --redact mode
Tests/TinyRedactTests/  redaction pixels, labels, and end-to-end detection on rendered text
```

Region selection uses macOS's own `screencapture -i`, so it behaves exactly like ⌘⇧4 (including Space for window mode).
