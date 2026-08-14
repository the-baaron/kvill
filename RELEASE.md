# Releasing Foldout to the Mac App Store

Everything that can be automated is. What is left needs a person, and this says
exactly which parts and why.

## Done, and repeatable

| | how |
|---|---|
| Sandboxed build | `./build.sh` signs with `Resources/Foldout.entitlements` |
| Development build | `QUILL_SANDBOX=0 ./build.sh` (the sandbox blocks `--render`, `--benchmark` and `--selftest` reading a path from the command line) |
| Distribution package | `./package.sh` produces a signed `build/Foldout.pkg` |
| Upload | `./package.sh --upload` once the app record exists |
| Screenshots | `./store/make-screenshots.sh`, five at 2880×1800 |
| Listing copy | `store/listing.md` |
| Privacy policy | `PRIVACY.md` |

Registered with Apple already: bundle ID `design.baars.Foldout` (26FH4WRJ6D), a
Mac App Store provisioning profile, a Mac App Distribution certificate and a Mac
Installer Distribution certificate, both in the login keychain and both chaining
through Apple's WWDR G3 intermediate.

## What needs a person, and why

**1. Create the app record.** appstoreconnect.apple.com → Apps → **+**

| field | value |
|---|---|
| Platform | macOS |
| Name | Foldout |
| Primary language | English (U.S.) |
| Bundle ID | design.baars.Foldout |
| SKU | Foldout_1 |

This cannot be scripted. The App Store Connect API answers a create with
`403 FORBIDDEN_ERROR: "The resource 'apps' does not allow 'CREATE'. Allowed
operations are: GET_COLLECTION, GET_INSTANCE, UPDATE"`. The web interface uses
an internal endpoint rather than the public API. Same category of blocker as
Yellendar's DSA trader declaration.

**2. Age rating questionnaire.** UI only. Every answer is None; the app has no
content of its own.

**3. Submit for Review.** UI only.

**4. Apple reviews it.** Days, not minutes, and the answer is theirs.

Steps 2 and 3 come after the build has uploaded and finished processing, which
takes roughly a quarter of an hour on Apple's side.

## After the record exists

    ./package.sh --upload

Then the listing text, keywords, category and support URLs can be pushed
through the API from `store/listing.md`; screenshots and the privacy label are
uploaded through the web interface.

## Things worth knowing

- **The upload needs Transporter or Xcode.** `altool` ships with Xcode, not with
  the Command Line Tools. Transporter is free on the Mac App Store and much
  smaller. `package.sh` looks for either and says which to install if neither is
  there. The standalone `InstallTransporter.pkg` Apple used to publish now
  serves an HTML page, so the Mac App Store is the only route.
- **Images beside a document do not load under the sandbox.** Opening a file
  grants access to that file, not to its neighbours, so `![](picture.png)` next
  to a document is denied. Opening a *folder* grants its whole tree, which is
  the fix, and is the folder-tree feature already on the roadmap.
- **The bundle identifier is permanent after the first submission.**
  `design.baars.Foldout` is reverse-DNS for baars.design. Yellendar uses
  `com.baarsdesign.yellendar`, which implies a different domain; the two
  conventions do not have to match and cannot be reconciled after submission.
