# Working on Kvill

A Markdown editor for macOS. One file, one window. Swift and AppKit, no
dependencies, no network. Free on the Mac App Store, MIT licensed, open source
at github.com/the-baaron/kvill.

The pitch is speed: about 0.09 seconds from double-click to a page you can type
on. Anything that makes opening a file slower is a regression in the product's
main claim, not just in a benchmark.

---

## Commands

| | |
|---|---|
| `./build.sh` | Sandboxed ad-hoc build into `build/Kvill.app`, then restarts a running copy onto it |
| `QUILL_SANDBOX=0 ./build.sh` | Same without the sandbox. **Needed for every CLI tool below**, because the sandbox refuses to read a path handed to the app on the command line |
| `./package.sh` | Distribution build into `build/dist/`, signed, wrapped in `build/Kvill.pkg` |
| `./package.sh --upload` | The same, then sends it to App Store Connect |
| `--selftest` | ~90 runtime checks. Run it after every change |
| `--benchmark file.md` | Startup, per-keystroke and second-window timings |
| `--render in.md out.png` | Draws a page headlessly. `--theme`, `--typography`, `--size`, `--geometry`, `--scale`, `--offset` |
| `--specimens out.png` | Draws the typography picker's buttons |
| `--tree folder out.png` | Draws the file-tree sidebar, `--theme` optional |
| `--login-item [status\|on\|off]` | Reads what macOS thinks of the login item, not what the setting claims |
| `./store/make-screenshots.sh` | Regenerates all five App Store screenshots |
| `scripts/make-portfolio.swift` | Composes a rendered page in a window at any canvas size, `--wash HEX A` to fade it behind text |
| `scripts/make-motif.swift` | Draws the hanging-marker signature as an abstract |
| `scripts/make-logo.swift` | Writes the wordmark as SVG outlines |
| `node store/push-listing.mjs` | Pushes listing text and screenshots from `store/listing.md` |
| `node store/submit.mjs` | Submits the current version for review |
| `./store/demo-setup.sh` | Builds the demo folder and prints the shot list for a review video |
| `node store/push-review-notes.mjs` | Fills App Review Information from `store/review-notes.md`; add `--apply` to send |

## Releasing

Bump `CFBundleVersion` in `Resources/Info.plist` (Apple refuses a repeated build
number), then:

    ./package.sh --upload
    node store/push-listing.mjs
    node store/submit.mjs

Only two things ever needed a browser, and both are done: creating the app
record (the API answers `403 "The resource 'apps' does not allow 'CREATE'"`) and
the age rating questionnaire.

**Identifiers.** App Apple ID 6801623848. Bundle ID `design.baars.Signet` —
the record was made under an earlier name and Apple will not repoint it, which
does not matter because users never see it. Team `496Y48L8AX`. Certificates are
`3rd Party Mac Developer Application` and `... Installer`, both issued from the
API against a local CSR and chaining through **WWDR G3**, not G5.

**Fill in App Review Information before submitting.** 1.0 was rejected under
2.1 "Information Needed" with that whole section empty: no contact name, email,
phone or notes. Apple's own message says to put the answers in the Notes field.
`store/review-notes.md` holds the text and `push-review-notes.mjs` sends it.

**App Review's actual words are not in the API.** Rejection reasons live in the
Resolution Center, which is web only; `appStoreVersions` gives you the state
(`REJECTED`) and nothing else, and the notification email is boilerplate. Ask
for the text rather than guessing at the guideline number.

**Recording the screen needs two grants a script cannot give itself.** Screen
Recording for the capture, Accessibility to drive the app. Probe them
honestly: `screencapture -x` to a temp file for the first, and reading a
window's *name* for the second, because `count processes` succeeds without the
grant and makes the check a lie.

**Nothing sensitive is in this repository and nothing ever has been**, checked
across the full history. Signing material stays in the keychain, the App Store
Connect `.p8` in `~/.appstoreconnect/private_keys/`, and the provisioning
profile is gitignored because it is issued per machine. The scripts read
credentials from the environment and embed none. `.gitignore` refuses `.p12`,
`.p8`, `.key`, `.pem`, `.cer`, `.csr`, `.mobileprovision` and `.env` outright,
so an accident has to be deliberate.

Credentials live in `~/.appstoreconnect/env`. Uploading needs Transporter from
the Mac App Store; `altool` ships with Xcode, which is not installed here, and
Apple's standalone Transporter download now serves an HTML page.

---

## Verify against the thing itself, never against your own copy of it

This is the rule that would have saved the most time today.

**A check that agrees with itself proves nothing.** The listing uploader parsed
`listing.md` with one regex while the length checks used another; the checks
said 2619 characters and Apple received 80, for hours. The scroll-past-end
checks called `NSClipView.scroll(to:)`, which does not clamp, so "can scroll
past the last line" passed by landing exactly where it was asked to. Read the
value back from App Store Connect. Scroll through `scrollToEndOfDocument`, the
call ⌘↓ makes.

**Never state a number you did not measure.** The promotional text claimed an
editor takes eleven seconds to start. That was invented for rhythm and went out
under the company name.

**A failed read is not a finding.** A contrast-ratio script once reported every
palette at 1.00 for secondary text, which meant the parser had matched one
colour twice. Numbers that are all the same, or implausible, are a broken read.

---

## Things that have actually gone wrong here

**Layout during editing.** A restyle runs inside the storage's `endEditing`,
where forcing layout is illegal. Asking for the visible line range there
sometimes returned nothing and left the window blank. The visible range is
cached and refreshed on scroll and at layout instead. Anything touching
`textContainerOrigin`, `usedRect`, `glyphRange(forBoundingRect:)` or the text
view's frame is forcing layout.

**Whole-document work per keystroke.** Typing in a 556KB file cost 77ms, almost
none of it in the editor: the word count split the entire document into
substrings, and the document copied the whole string into a cache. Both were
outside the editor and neither was on anyone's list of suspects. It is 4ms now.
Profile before optimising; the answer was not where it looked.

**`NSString.character(at:)` in the parser.** An Objective-C message per
character against a rope. Copying the document into a UTF-16 array once (`Scan`)
made parsing 4.8× faster.

**Off-screen windows never run a display pass.** The same trap twice. A blank
sidebar and a broken sidebar look identical, so `--tree` was reporting success
on an empty PNG. The row views do not exist until something asks for them
(`prepareForRender`), the views have to be told to draw themselves one by one
because the hierarchy is layer-backed, and the system-drawn parts, disclosure
triangle and symbol icons, resolve their colour against the current *drawing*
appearance, which off screen is the machine's rather than the window's. Without
that last bit the sidebar came out white on a white page and looked like a bug
in the app.

**Renders used to change the app.** `--render --theme nord` wrote nord into the
user's own preferences, so taking screenshots silently changed their editor.
`ThemeManager.settingsSnapshot` and `restore` put every display setting back,
in memory as well as on disk. A render is a read.

**Glass renders as nothing off screen.** `NSGlassEffectView` draws blank in a
headless render, so every screenshot of the options panel came out empty. Its
contents are ordinary views: `--specimens` draws those, and `--selftest`
interrogates the rest of the chrome.

**A distribution-signed app cannot launch.** A Mac App Store provisioning
profile lists no devices. `package.sh` used to sign `build/Kvill.app` in place
and the app stopped opening; it builds into `build/dist/` now.

**ITMS-90886.** Signing by hand skips two entitlements Xcode injects silently,
`com.apple.application-identifier` and `com.apple.developer.team-identifier`.
`package.sh` derives both from the Info.plist and the certificate.

**Tests with side effects.** A check toggled the background setting through the
property whose setter registers a login item, which quietly added one to the
machine. Tests write to defaults directly and assert afterwards that they left
nothing behind.

---

## Naming, if it ever comes up again

Every single dictionary word is taken on the App Store, in English and in
Norwegian, mostly by apps that never shipped. The iTunes Search API cannot see
reservations, so it cleared both Signet and Foldout and was wrong both times.
Compound words and coinages survive; single nouns do not. Only App Store Connect
can confirm a name.

## Architecture worth knowing before changing it

```
Sources/Kvill/
  Markdown/    line scanner, inline scanner, model types
  Editor/      styler (the gutter maths), text view, controller, commands
  Theme/       palettes, typography presets, derived metrics
  UI/          glass chrome: options bar, selection bar, insert menu, toasts
  App/         NSDocument, window, menu bar, delegate, PNG renderer
```

Every line's text starts on the same x position and its marker is pushed into
the space to the left, right-aligned, with two paragraph indents and one kerned
space:

```
firstLineHeadIndent = contentX - gap - markerWidth   where the marker starts
headIndent          = contentX                       where wrapped lines resume
kern on last gap char = gap - naturalGapWidth        pins content to contentX
```

Because the marker's width is measured and compensated for, `#`, `######`, `1.`
and `100.` all leave the text on the same column. Nothing is inserted into or
removed from the document to achieve it. Collapsing a run to zero width needs
the glyphs shrunk to 0.5pt first, because negative kerning is clamped per
glyph.

Tables are aligned by padding the source with spaces, not by measuring cells.
Two attempts at a drawn grid were deleted. If a table will not fit, it is set
smaller and then truncated; it never wraps.

Scroll-past-end is the text view being taller than its text (`minSize` and the
frame), not a constrained clip view. `constrainBoundsRect` is honoured on some
routes into scrolling and ignored on others.

Non-contiguous layout is on. It makes the document height provisional, so the
height is measured explicitly on a debounce rather than on every keystroke.
