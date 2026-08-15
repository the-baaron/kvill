# Reply to App Review

Guideline 2.1, Information Needed, submission
00d065b0-b89d-47e8-aa83-5235eeed4e51, version 1.0 build 3.

Nothing in Apple's message reports a bug or a crash. It is the standard request
for information about a new app, and the App Review Information section on the
rejected submission was empty: no contact name, email, phone or notes, confirmed
by reading `appStoreReviewDetail`, which returned zero characters in every
field. That section is now filled in, which is where Apple asked for the answers
to points 2 to 7.

**Send with:** the screen recording and `kvill-samples.zip`, attached through
**Attach File**.

The Reply field holds 4000 characters. The message below is inside that, and
does not repeat the six written answers, because those are in App Review
Information already and repeating them would push it over.

---

## Message

Hello,

Thank you for the review. The App Review Information section is now filled in
and answers points 2 to 7 there. A screen recording and a folder of sample
Markdown files are attached to this message.

The recording was made on a physical Mac, a MacBook Pro (Mac17,8, Apple M5 Pro)
running macOS 26.6.1, the current release. It begins with the app being launched
and shows a normal session end to end: opening a Markdown file, the document
formatted for reading, typing into it, headings, a table squaring itself up, a
code block, and the panel that changes typeface, text size and measure.

None of the flows in your list exist in Kvill, so none appear in the recording.
There is no account registration, login or deletion. There is no paid content,
subscription or purchase of any kind, and no in-app purchases are configured.
There is no user-generated content shared between users, so there is nothing to
report or block. The app requests no location, contacts, camera, microphone or
tracking permission, and declares no usage description strings at all. It is a
text editor for files already on the user's own disk.

Reaching everything in the app needs no setup: no account, no login, no
credentials, and nothing to configure on first launch. Open any .md file by
double-clicking it in the Finder, dragging it onto the app icon, or File > Open.
Sample files are attached. Click into any line to see its Markdown syntax appear
in the left margin and fade again when you click away, which is the idea the
editor is built around. Press / on an empty line for the insert menu.
File > Open Folder lists the Markdown files in that folder down the side of the
window, and is also what permits the app to load images stored next to a
document, since the sandbox grants only what the user selects. Editing saves
automatically; Command-S is there but is not needed.

One prompt you may see is macOS's own, asking whether the app may read the
folder a document is in when that folder is the Desktop, Documents or Downloads.
The system raises that for any app and Kvill can neither trigger nor suppress
it.

Kvill has no third-party dependencies, no analytics and no network entitlement,
so the sandbox refuses a connection even if one were attempted. Everything it
does happens on the user's own machine against files the user chose.

Please tell me if any part of the app was unclear or unreachable and I will send
a recording of that on its own.

Best regards,
Ronald Baars
BAARS DESIGN
