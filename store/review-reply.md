# Reply to App Review

Guideline 2.1, Information Needed, submission
00d065b0-b89d-47e8-aa83-5235eeed4e51, version 1.0 build 3.

Nothing in Apple's message reports a bug or a crash. It is the standard request
for information about a new app, and the App Review Information section on the
rejected submission was empty: no contact name, no email, no phone, no notes.
Verified by reading `appStoreReviewDetail` for version 1.0, which returned zero
characters in every field.

**Send in this order:**

1. `node store/push-review-notes.mjs --apply` to fill the App Review
   Information section. Points 2 to 7 are answered there, which is where Apple
   asked for them.
2. Attach the screen recording and the sample files to the Resolution Center
   reply below.

---

## Message

Hello,

Thank you for the review. The App Review Information section has been filled
in, and answers points 2 to 7 there as you asked. Attached to this message are
a screen recording and a folder of sample Markdown files.

**1. Screen recording.** Recorded on a physical Mac, a MacBook Pro (Mac17,8,
Apple M5 Pro) running macOS 26.6.1, the current release. It starts with the app
not running and shows a typical session end to end: launching by opening a
Markdown file, reading the formatted document, putting the cursor in a line to
see its Markdown reappear in the margin, ticking a checkbox, inserting a table
from the insert menu, changing the colour scheme and text size, opening a folder
to switch between documents, an image beside a document loading, and saving.

None of the flows in your list exist in Kvill, so none appear in the recording:
there is no account registration, login or deletion, no paid content,
subscription or purchase of any kind, no user-generated content shared between
users and so nothing to report or block, and no request for location, contacts,
camera, tracking or any other sensitive data or device capability. The app is a
text editor for files already on the user's own disk.

**2. Devices and operating systems tested.** MacBook Pro (Mac17,8), Apple M5
Pro, macOS 26.6.1 (25G76). The build requires macOS 14.0 or later.

**3. Purpose and audience.** Kvill opens one Markdown file in one window and
lets you read and edit it. It is for people who keep notes, README files and
documentation as plain Markdown on their own disk. It solves the gap between a
plain text editor, which shows Markdown as raw symbols, and a notes app, which
takes your writing into its own database: Kvill formats the document while
leaving the file exactly as typed, moving the Markdown symbols into the left
margin and dimming them rather than hiding them, and bringing them back the
moment the cursor enters that line.

**4. Setting up and reaching the main features.** No account, no login, no
credentials, and nothing to configure. Open any .md file by double-clicking it,
dragging it onto the app icon, or File > Open. Sample files are attached. Click
into a line to see its syntax in the margin. Press / on an empty line for the
insert menu. File > Open Folder lists the Markdown files in that folder down
the side of the window, and is also what permits the app to load images stored
next to a document, since the sandbox grants only what the user selects.
Editing saves automatically.

**5. External services, tools and platforms.** None. No data provider, no
authentication service, no payment processor, no analytics and no AI service.
There are no third-party dependencies at all; the app is built only against
AppKit and Foundation. It ships without any network entitlement, so the sandbox
refuses a connection even if one were attempted. Everything happens on the
user's own machine, against files the user chose.

**6. Regional differences.** None. The app behaves identically everywhere. It
ships in English only, with no region-specific features, content or pricing,
and no content served from anywhere.

**7. Regulated industry or protected third-party material.** Neither applies.
Kvill is a general-purpose text editor providing no regulated service, and it
contains no third-party content, trademarks or licensed material. We publish
the source ourselves under the MIT licence at github.com/the-baaron/kvill.

Please tell me if any part of the app was unclear or unreachable and I will send
a recording of that on its own.

Best regards,
Ronald Baars
BAARS DESIGN
