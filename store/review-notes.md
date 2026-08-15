# App Review Information

The text below goes in the Notes field of App Review Information. It answers
points 2 to 7 of the Guideline 2.1 information request on submission
00d065b0-b89d-47e8-aa83-5235eeed4e51.

That section was **empty** on the rejected submission: no contact name, no
email, no phone, no notes. Apple's message asks for exactly that, so it is very
likely the whole of the problem. Verified by reading
`appStoreReviewDetail` for version 1.0.

Contact to set alongside it:

| Field | Value |
| --- | --- |
| First name | Ronald |
| Last name | Baars |
| Email | $ASC_CONTACT_EMAIL |
| Phone | $ASC_CONTACT_PHONE |
| Demo account required | No |

---

## Notes field

Kvill is an offline Markdown text editor for macOS. It has no accounts, no
in-app purchases or subscriptions, no advertising, no user-generated content
shared between users, and it asks for no sensitive data or device capabilities.
None of the flows listed in point 1 of your message exist in the app, so the
attached recording covers all of it: launching, opening a document, editing,
switching files, and saving.

DEVICES AND OPERATING SYSTEMS TESTED
Tested on a physical Mac before submission: MacBook Pro (Mac17,8), Apple M5 Pro,
macOS 26.6.1 (25G76), which is the current release. The build is arm64 and
requires macOS 14.0 or later.

PURPOSE AND AUDIENCE
Kvill opens a single Markdown file in a single window and lets you read and edit
it. It is for people who keep notes, README files and documentation as plain
Markdown on their own disk, and who want to change one line in a file without
opening a code editor and waiting for a project to load. The problem it solves
is the gap between a plain text editor, which shows Markdown as raw symbols, and
a notes app, which stores your writing in its own database. Kvill formats the
document as you read it while leaving the file on disk exactly as you typed it:
the Markdown symbols are moved into the left margin and dimmed rather than
hidden, and they return the moment the cursor enters that line. Nothing is added
to or removed from the file.

SETTING UP AND REACHING THE MAIN FEATURES
No account, no login and no credentials are needed, and there is nothing to
configure on first launch. Sample Markdown files are attached to this message.

1. Open any .md file: double-click it in the Finder, drag it onto the app icon,
   or use File > Open. The app also creates an empty untitled document if you
   launch it on its own.
2. Click into any line to see its Markdown syntax appear in the left margin, and
   click elsewhere to see it fade again.
3. Press / on an empty line for the insert menu: headings, tables, code blocks,
   callouts and lists.
4. File > Open Folder shows the Markdown files in that folder down the side of
   the window. Choosing a folder is also what permits the app to load images
   stored next to a document, as the sandbox grants only what the user selects.
5. Control-Command-] changes the colour scheme, Command-+ the text size, and
   Command-. hides all interface.
6. Editing saves automatically. Command-S is there but is not needed.

EXTERNAL SERVICES, TOOLS AND PLATFORMS
None. Kvill uses no data providers, no authentication service, no payment
processor, no analytics and no AI service. It has no third-party dependencies of
any kind and is built only against Apple's own frameworks, AppKit and
Foundation. The app ships without any network entitlement, so the sandbox will
refuse a connection even if one were attempted. Everything it does happens on
the user's own machine, against files the user selected.

REGIONAL DIFFERENCES
None. The app behaves identically in every region. It ships in English only,
with no region-specific features, content or pricing, and no content served from
anywhere.

REGULATED INDUSTRY OR PROTECTED THIRD-PARTY MATERIAL
Neither applies. Kvill is a general-purpose text editor. It provides no
regulated service, and it includes no third-party content, trademarks or
licensed material. The source is published by us under the MIT licence at
github.com/the-baaron/kvill.
