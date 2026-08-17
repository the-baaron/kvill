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
network. This build is the same one that shipped as 1.0.

What to test:

1. Double-click a .md file in the Finder and count how long it is before you can
   type. It should be about a tenth of a second, and that is the whole product.
2. Click into a line. Its Markdown symbols appear in the left margin and fade
   again when you click elsewhere. The file on disk never changes.
3. Press / on an empty line for the insert menu: headings, tables, code blocks,
   callouts, lists.
4. File > Open Folder puts the Markdown files in that folder down the side of
   the window.
5. Control-Command-] changes the colour scheme, Command-+ the text size,
   Command-. hides every piece of interface.

Editing saves itself. Anything that makes opening a file feel slow is worth
reporting even if nothing looks broken.
