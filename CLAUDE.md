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
| `./store/make-portfolio-assets.sh` | Builds all ten baars.design case-study images and the wordmark, from the app |
| `scripts/make-portfolio.swift` | Composes a rendered page in a window at any canvas size. `--wash HEX A` flat, `--fade HEX A0 A1 HOLD [END]` graded, `--drop F` |
| `scripts/make-motif.swift` | Draws the hanging-marker signature as an abstract. `--band F` composes inside the part that survives a centre crop |
| `scripts/make-logo.swift` | Writes the wordmark as SVG outlines; `--lockup` adds the icon, also as paths |
| `node store/push-listing.mjs` | Pushes listing text and screenshots from `store/listing.md` |
| `node store/submit.mjs` | Submits the current version for review |
| `./store/demo-setup.sh` | Builds the demo folder and prints the shot list for a review video |
| `./store/record-demo.sh` | Records the demo unattended. Needs Screen Recording and Accessibility |
| `node store/push-review-notes.mjs` | Fills App Review Information from `store/review-notes.md`; add `--apply` to send |
| `node store/push-testflight.mjs` | Sets up TestFlight **internal** testing from `store/testflight.md`; add `--apply` to send |

## Staying small

Kvill is 1.7MB, 52 Swift files, 13,558 lines and **no dependencies at all**.
That is the product, not an accident of it: the pitch is that a document opens
before you have finished letting go of the mouse, and every one of those numbers
is why it can.

### The budget

Measured on this machine, and worth re-measuring rather than trusting:

| | |
|---|---|
| Bundle | 1.8MB, binary 1.57MB |
| Source | 55 files, ~14,200 lines |
| Dependencies | none, and adding one is a decision rather than a convenience |
| Cold launch to a window on screen | ~280ms |
| Warm open, app already running | ~100ms |
| `--benchmark` to first screen | 65-85ms |
| `--benchmark` per keystroke | 32ms at 2KB, 94ms at 180KB |

**Anything that moves these is a change to the product.** A feature that adds a
megabyte, or ten milliseconds to a keystroke, has to be worth that on its own
terms, and the number goes in the commit message.

### How to know, rather than think

    ./build.sh && ./build/Kvill.app/Contents/MacOS/Kvill --benchmark file.md

Run it three times: the figures are stable to a few tenths, so a difference of
more than about a millisecond is real and anything smaller is not.

**To find out whether a change cost anything, build both.** A worktree at the
commit before it, built and benchmarked beside the current one, answers in two
minutes what an afternoon of reasoning will not:

    git worktree add /tmp/before <commit>
    cd /tmp/before && QUILL_SANDBOX=0 ./build.sh
    /tmp/before/build/Kvill.app/Contents/MacOS/Kvill --benchmark file.md
    git worktree remove --force /tmp/before

### The rules that keep it this size

**Nothing whole-document runs per keystroke.** This is the one that has actually
bitten: the word count split the entire document into substrings on every
keypress and cost 77ms in a large file. Work that scales with the document is
debounced, and `DocumentViewController.updateStats` is the pattern to copy, at
0.35 seconds. Anything hanging off `onTextChange` is suspect until it is shown
to be cheap.

**Parse once.** `EditorViewController.parsed` is already the document, in order,
with kinds and ranges. A feature that needs structure reads that. A feature that
re-scans the text has bought a second parser and will disagree with the first
one eventually.

**Reach for the AppKit component before writing one.** The sidebar was written by
hand once, with its own width, animation, collapsed state and hover tracking,
and every one of those is something `NSSplitViewItem` already does. Deleting it
removed more code than it added and fixed three bugs.

**A view that is not on screen does no work.** The contents list rebuilds when
the sidebar is open, not when it is collapsed.

**No dependency without a reason that survives being said out loud.** Every
library is bundle size, launch time, a supply chain and a thing to keep current.
The syntax highlighter here is language-agnostic on purpose: a real grammar per
language is a megabyte and a maintenance burden for a panel most documents do
not have.

**Features are refused, not deferred.** No preview pane, no tabs, no plugins, no
sync, no accounts. Each of those is defensible on its own and none of them is
why anyone opens this app. `README.md` keeps the list, and the list is a feature.

## What the interface is allowed to do

**Double-clicking a file gets a page and nothing else.** That is the product and
it is not up for negotiation by a feature. No sidebar, no index, no minimap, no
bar of any kind on a plain open.

**Everything else is off until asked for, and every one of them can be turned
off again.** A folder opened deliberately shows its files, because that is what
opening a folder means. Nothing else appears on its own.

**The sidebar is about which file. The index is about where in it.** Those are
different questions, so they are different things: the sidebar holds the folder,
and the document's headings float in the page's own right margin the way a
documentation site puts them there. The index appears only when the window is
wide enough to have a margin to spare and the document is long enough to need
one, and the page's column moves left to make room rather than the index sitting
on top of it.

**Native components, no custom rendering.** The sidebar is `NSSplitViewItem`,
the lists are `NSOutlineView` and `NSTableView` in `.sourceList` style, the find
bar is `NSTextFinder`, tabs are the system's window tabbing. Drawing is for the
page itself, where the typography is the product. Anywhere else, a hand-drawn
control is a bug waiting for the next macOS release.

**Written to the current Swift and AppKit**, targeting the macOS in
`Package.swift` rather than the oldest one that might work.

## Feature parity, and what we refuse

MarkViewer is the nearest thing to this app: free, native, macOS, aimed at
reading and reviewing Markdown, and closed source. Its list is worth answering
one item at a time rather than as a whole.

| Theirs | Ours |
|---|---|
| WYSIWYG editing | Yes, and the source is never rewritten |
| GitHub-flavoured Markdown | Yes, every construct GitHub renders |
| Runs offline | Yes, and no network entitlement exists to remove |
| Launches instantly | Yes, measured: see the budget above |
| Native app | Yes |
| Search highlighting | Yes, `NSTextFinder` |
| File explorer | Yes, the folder sidebar |
| Detects external changes | Yes, and marks the words that changed |
| Auto table of contents | Yes, floating in the page's margin, off by default |
| Multi-tab | Yes, the system's own window tabbing |
| Inline annotations | Yes, as a highlight and a footnote, in the file |
| Built-in terminal | **Refused**, see below |
| Diff view | Ours marks changes in place; theirs is a panel |

**The terminal is not a preference, it is not possible.** This app is sandboxed
for the App Store and the sandbox has no entitlement that lets it run another
program. Anyone who wants a terminal has one.

**Annotations go in the file, in Markdown.** `==highlight==` already parses, so
an annotation is text the user can read in any other editor, in a diff and on
GitHub. A sidecar file of comments would be a private format that only this app
understands, which is the thing this app exists not to be.

**Tabs are the system's.** `window.tabbingMode` moves from `.disallowed` to
`.automatic`, which respects the "Prefer tabs" setting in System Settings, so
tabs are off unless someone has asked the whole system for them. Nothing is
drawn and nothing is maintained.

## Never put a window in front of the person at the machine

**Testing must not take over the screen.** Someone is using this computer while
the checks run, and a window that appears over their work is a bug in the
checks, not a side effect of them.

- `--selftest` builds its windows off screen and asserts at the end that it left
  nothing visible. Any check that needs a window uses `OffscreenWindow`, which
  overrides `constrainFrameRect` so AppKit cannot drag it back onto the display,
  or hides the document it opened.
- A check that genuinely needs a window to count as on screen, because the code
  under test asks `isVisible`, sets `alphaValue = 0` and moves it off screen
  instead. Visible to AppKit, invisible to a person.
- **Launching the real app for a screenshot uses `open -g`**, which opens it
  behind whatever is in front. `screencapture -l <window id>` photographs a
  window that is not frontmost perfectly well, so there is no reason to steal
  focus. Quit the app when the picture is taken.

The one thing that does need the screen awake is `screencapture` itself: a
sleeping display makes it fail on a window and return solid black for the whole
screen, which reads as a permission problem and is not one. `caffeinate -u`
first.

## When the layout changes, the pictures are wrong

**Anything that changes what a window looks like makes the App Store
screenshots stale.** A new sidebar, a moved button, a changed margin, a palette
that was removed: the store is still showing the old one, and the store is what
people decide on.

    ./store/make-screenshots.sh        # regenerates all five
    open store/screenshots             # look at them, do not assume

Shot 2 is a photograph of the real window through `store/capture-window.sh`, so
it picks up interface changes on its own. The other four are composed around a
rendered page and pick up typography and palette changes but not chrome.

Pushing them is a separate, deliberate act: `node store/push-listing.mjs` sends
text **and** screenshots immediately, with no dry run and no `--apply` flag,
unlike every other script here. Regenerate freely; push when you mean to.

## What's new, in the About window

`Resources/ReleaseNotes.md` is what the About window's right column shows, and
it ships inside the bundle. **Add an entry whenever a feature lands**, in the
same sitting, because a feature nobody is told about may as well not have
shipped and nobody reconstructs this list later.

The format is fixed and the checks enforce it:

    **Feature name** - 18 August 2026
    Two lines at most, in plain language, about what it does for someone.
    Not how it works.

Newest first. The date is the day it landed, taken from the commit rather than
guessed. `--selftest` fails if an entry has no date, if one runs past two lines,
or if the file is missing from the built app.

It is a list of features and dates on purpose, not a list of version numbers. A
version number says nothing to anyone who was not watching the version numbers.

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

**CFBundleVersion has to be dotted, and has to exceed 3.** A plain integer is
legal and builds 1 to 3 used one, but uploading 1.0.1 as build `4` was refused
six times with `Info.plist value mismatch. CFBundleShortVersionString value of
1.0.1 does not match the value of 1.0.0 specified in the request`, which is a
lie: nothing anywhere held 1.0.0. Giving CFBundleVersion a dotted value made it
go away. It has to exceed the highest already uploaded, which Apple compares
component by component, so `1.0.1` is refused for having a leading 1 against a
previous `3`. 1.0.1 shipped as build `4.0.0`.

Found by comparing against Yellendar, which uploads from the same machine
without complaint and whose package differs in exactly that one way. Hours went
into reading the error literally and hunting for wherever 1.0.0 was cached.
**When one app uploads and another does not, diff the two packages before
theorising.**

**Fill in App Review Information before submitting.** 1.0 was rejected under
2.1 "Information Needed" with that whole section empty: no contact name, email,
phone or notes. Apple's own message says to put the answers in the Notes field.
`store/review-notes.md` holds the text and `push-review-notes.mjs` sends it.

The contact email and phone are **not in this repository**, because it is
public and a phone number on GitHub is indexed and cannot be taken back. The
table in `review-notes.md` holds `$ASC_CONTACT_EMAIL` and `$ASC_CONTACT_PHONE`,
which the pusher expands from `~/.appstoreconnect/env`. An unset variable stops
the script rather than sending an empty string, since a blank contact section is
the thing that caused the rejection in the first place.

**TestFlight internal testing is entirely scriptable, including the tester.**
`push-testflight.mjs` makes the internal group, attaches a build and adds the
account holder, and `POST /v1/betaTesters` accepted him without a browser. Two
things to know. A build can sit at `processingState` `VALID` while its
`buildBetaDetail` says `internalBuildState: PROCESSING_EXCEPTION`, which is what
build 1 does, so the build state is the one to check and it is on a different
endpoint. And the **What to Test** text a tester sees is not the beta app
localization at all: it is `betaBuildLocalizations.whatsNew` on the build, which
build 3 still carries from the reply written to App Review.

Everything external is off limits to that script by design. A public link, an
external group and a `betaAppReviewSubmission` all reach people outside the
company, so they are a decision rather than a script.

**App Review's actual words are not in the API.** Rejection reasons live in the
Resolution Center, which is web only; `appStoreVersions` gives you the state
(`REJECTED`) and nothing else, and the notification email is boilerplate. Ask
for the text rather than guessing at the guideline number.

**The app records its own demo.** `--demo` runs `DemoDriver`, which calls the
same methods the keyboard reaches, so no Accessibility permission is involved.
Only Screen Recording is, and `screencapture -x` to a temp file is the honest
probe for it. Four things ate an afternoon and are all handled in
`store/record-demo.sh`:

- **The other display.** `screencapture` records the primary display. The app
  opened on the external monitor and the first take was 75 seconds of an empty
  desktop, so `placeWindow` puts the window on the screen whose frame starts at
  the origin.
- **The Desktop is protected.** Opening a document there raises a macOS folder
  prompt that blocks the window until a human clicks it, every launch. The demo
  folder lives in the home folder instead.
- **The display going to sleep** produces a recording of solid black that looks
  exactly like a recording that failed to start. `caffeinate -u -d` for the
  length of the take.
- **`osascript -e 'quit app "X"'` launches X when it is not running**, and
  asking to control another app raises its own permission dialogue in the middle
  of the take. `pkill -x` instead.

Also: `defaults write` can wedge. `cfprefsd` hung every write for a stretch,
which is why the demo is triggered by a launch argument and not a preference.

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
outside the editor and neither was on anyone's list of suspects. That fix was
real and the styling step is cheap now, but **4ms was the wrong number to write
down**: measured end to end with `--benchmark`, a keystroke costs 32ms on a 2KB
document and 94ms at 180KB. Both figures are the same on the commit before a
day's work as after it, so they are the standing cost of the edit path, not a
regression. Quote the number the tool prints, not the one the fix felt like.
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
