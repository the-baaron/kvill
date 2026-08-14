# Privacy

Kvill collects nothing.

There is no analytics, no crash reporting, no account, no sync, and no
telemetry of any kind. Nothing about you or your documents is gathered, stored
or transmitted, because Kvill makes no network connections at all.

This is not only a promise. The app is sandboxed, and its entitlements are:

- read and write access to files you choose, through Open, a double-click in
  the Finder, or a drag onto the icon
- app-scope bookmarks, so macOS can reopen a document you had open

There is no network entitlement. macOS itself would refuse a connection if the
app tried to make one, so this cannot change by accident in a future version
without that being visible in the app's signature.

## Your documents

Your files stay where you put them. Kvill reads the document you open and
writes it back to the same place. Images you drag in are copied next to the
document. Nothing is copied anywhere else.

## Preferences

Your palette, typeface, text size and reading options are stored on your Mac
in the standard macOS preferences for the app, and nowhere else.

## Questions

Kvill is open source: https://github.com/the-baaron/kvill

Ronald Baars, BAARS DESIGN (org.nr 938 054 037), Norway.
