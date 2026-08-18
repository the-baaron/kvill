# TestFlight internal testing

What `push-testflight.mjs` sends. Internal testing only: an internal beta group,
the beta app localization TestFlight needs before it will hand a build to
anyone, and the one App Store Connect user on the account as a tester.

Nothing here reaches anyone outside the company. Internal testers have to be
users on the App Store Connect account already, there is no public link, and no
beta app review submission is created. External testing is a separate decision
and this script refuses to touch it.

The feedback email is a reference rather than a value, the same as in
`review-notes.md`: this repository is public. `push-testflight.mjs` expands
`$ASC_CONTACT_EMAIL` from `~/.appstoreconnect/env` and stops rather than sending
a blank, because TestFlight will not show a build without a feedback address.

The tester is not named here either. The script reads App Store Connect's own
user list and takes the account holder, so no address is written down.

| Field | Value |
| --- | --- |
| Group name | Internal Testing |
| Locale | en-US |
| Feedback email | $ASC_CONTACT_EMAIL |

---

## Description

Kvill is a Markdown editor for macOS. One file, one window, no account, no
network.

What to test in this build:

1. Double-click a .md file in the Finder. It should be a page and nothing else,
   no sidebar and no panels, in about a tenth of a second. That is the product,
   and anything appearing on its own is a bug.
2. Settings, then "Show document index". Open something long in a wide window:
   its headings appear in the right margin and the page shifts left to make room.
   Narrow the window and the index gets out of the way rather than squeezing the
   text. Click a heading to jump to it.
3. Turn on typewriter scrolling and press Return quickly at the end of a long
   document. The line you are typing should stay in the middle of the window.
   It used to pin itself to the bottom, and with focus mode on as well the page
   jumped by thousands of points mid-sentence.
4. Select a phrase and press Shift-Command-A. It becomes a highlight with a
   footnote at the end of the file, ready to type the note into. Open the same
   file anywhere else and it is ordinary Markdown.
5. If you have "Prefer tabs when opening documents" set in System Settings,
   documents open as tabs. If you have not, they open as windows, as before.
6. Live mode, in Settings. On, edits are written as you type and anything
   another program writes appears with the changed words lit. Off, Command-S
   saves and Command-R reloads, and saving over a file that changed asks first.

Editing saves itself. Anything that makes opening a file feel slow is worth
reporting even if nothing looks broken.
