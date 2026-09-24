# OpenDocument.ios ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/build_test.yml/badge.svg) ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/format.yml/badge.svg)

The iOS app of [OpenDocument.core](https://github.com/opendocument-app/OpenDocument.core).
It opens and edits office documents and PDFs.

## Setup

Open `OpenDocumentReader.xcodeproj` in Xcode. Swift Package Manager resolves
everything, including odrcore as the prebuilt `OdrCoreObjC.xcframework`. There
is no conan step and no C++ toolchain.

To use an unreleased odrcore, point the package reference at a local checkout
and build the xcframework there:

```sh
cd ../OpenDocument.core
apple/build_xcframework.py slice && apple/build_xcframework.py assemble
```

Then set `ODR_XCFRAMEWORK=OdrCoreObjC.xcframework` in the environment of every
`xcodebuild` call.

## The two apps

| target | scheme | bundle id | ad sdk |
| --- | --- | --- | --- |
| `OpenDocumentReader` | `ODR Full` | `at.tomtasche.reader` | no |
| `OpenDocumentReader Lite` | `ODR Lite` | `at.tomtasche.reader.lite1` | yes |

They are two targets, not two configurations, because a linked package cannot
be removed by a build setting. Each folder is a synchronized group, so a new
file joins the build on its own:

| folder | in |
| --- | --- |
| `OpenDocumentReader/` | both |
| `Ads/` | Lite |
| `NoAds/` | Full |
| `OpenDocumentReaderTests/` | the test bundle |
| `configs/full`, `configs/lite` | `Info.plist` and privacy manifest of each app |

Rules:

- Only `Ads/` names a type from an ad sdk. `AdSlot` and `AdPrivacy` have a
  no-op twin in `NoAds/`. Build both schemes after you change one of them.
- Code asks `Features.withAds` or `Features.advancedEditing`, never the bundle
  id. The constants behind them live in `Ads/Linked.swift` and
  `NoAds/Linked.swift`.
- Lite edits with the scope `paragraph`. odrcore refuses a larger change with
  `outOfScope`, and the app offers Pro.
- The gate is on the tool, not on the mode. Both apps open every editable
  document, and a locked `EditToolBar` dims the Pro tools. The highlighter
  works in both apps. Do not gate the whole edit mode.
- `scripts/make-test-fixtures.py` writes the test documents. It stays outside
  the test folder, because everything in there goes into the test bundle.

## How a document reaches the screen

`CoreWrapper` gives the file to odrcore and gets an `HtmlService`. odrcore's
HTTP server binds to `127.0.0.1` on a free port, and the web view loads
`http://127.0.0.1:<port>/file/<prefix>/<page>.html`. odrcore renders a page
only when the web view asks for it. The `<prefix>` changes on every
translation, because the web view caches by URL.

If the socket cannot open, the translate fails. There is no file fallback.
`file:` URLs are used only for formats odrcore does not handle.

This needs no entitlement and no permission prompt. It needs
`NSAllowsLocalNetworking` in both `Info.plist`s, because App Transport
Security blocks plain HTTP.

## Editing

- The pencil calls `odr.editing.enable()`. The page stays in place. The same
  pencil marks up a PDF.
- The bar holds undo, redo and save. The strip (`EditToolBar`) holds the text
  formatting. A sheet or a plain text file shows no strip.
- A tap uses a tool. A long press opens its colours. Do not add chevrons.
- Redo is hidden over a PDF. The magnifier is hidden during an edit.
- A PDF tool is armed by the page (`odr.annotation.press`), and the app never
  disarms it.
- A save reads `odr.editing.getOperations()` or
  `odr.annotation.getAnnotations()`. odrcore writes the file next to the open
  one and then moves it into place.
- The page talks to the app through one `WKScriptMessageHandler`.

## Formatting

`scripts/format.sh` runs `swift-format` from the active Xcode toolchain, with
`.swift-format` as its configuration. Run it before you commit. CI runs
`scripts/format.sh --check`.

## Continuous integration

| workflow | what it does |
| --- | --- |
| `format` | `scripts/format.sh --check` on every push and pull request |
| `build_test` | unit tests on the simulator, plus a device build of both apps |
| `release` | upload to App Store Connect, started by hand |

## Releasing

```sh
gh workflow run release.yml -f version=1.38
```

The run uploads both apps and never submits for review. Its jobs:

| job | what it does |
| --- | --- |
| `build` | builds and signs both `.ipa`s |
| `screenshots` | one job per device, takes the store screenshots in every locale |
| `screenshot-set` | joins the two device halves, checks the set, archives it as `framed` |
| `upload` | one job per app, uploads its `.ipa` |
| `listing` | one job per app, writes the store text and screenshots |
| `record` | tags the build and drafts the GitHub release |

Before the run, do these steps in the pull request that cuts the version:

1. Cut the `Unreleased` heading in `CHANGELOG.md`.
2. Run `scripts/store-copy.py <version>` and read the diff. See
   `fastlane/metadata/README.md`.

The run refuses a version without a changelog section or without release notes
in every locale. `scripts/resolve-version.py` and
`scripts/changelog_section.py` show what a dispatch would do.

Inputs:

| input | what it does |
| --- | --- |
| `version` | the marketing version, without `v` |
| `dry_run` | builds and signs, uploads nothing, needs no version |
| `screenshots_from_run` | runs the `listing` jobs alone, with the `framed` artifact of that run |

Common cases:

- One upload fails: press "Re-run failed jobs". The `.ipa` and its build number
  are kept.
- A `listing` job says the screenshots are not listed: they are up. App Store
  Connect was slow. Look, then re-run the job if a locale is short.

### Version and build number

Nothing in the tree changes for a release:

| | comes from | checked in |
| --- | --- | --- |
| `MARKETING_VERSION` | the `version` input | `0.0.0` |
| `CURRENT_PROJECT_VERSION` | one above the highest build of either app in App Store Connect | `1` |

Both apps get the same build number, so one `(version, build)` pair names one
commit.

### Tags

| tag | who writes it | what it means |
| --- | --- | --- |
| `build/v<version>/<build>` | the workflow, after both uploads | this commit went up as that build |
| `v<version>` | you, when you publish the draft release | this is what shipped |

No tag is pushed before a build, and no tag starts a build. Publish the draft
after App Store Connect shows the build as live:

```sh
gh release edit v1.38 --draft=false
```

### Secrets

| secret | what it is |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | issuer id of that key |
| `ASC_KEY_CONTENT` | the `.p8` private key, base64 encoded |
| `SIGNING_CERTIFICATE_P12` | Apple Distribution certificate and key, base64 encoded `.p12` |
| `SIGNING_CERTIFICATE_PASSWORD` | password of that `.p12` |

Signing is manual. The run downloads the App Store provisioning profile of
each bundle id, so both apps need one. A key below Admin cannot create a
profile, and the run stops in its first seconds if one is missing. Profiles
expire after a year.

### Local lanes

```sh
ODR_VERSION=1.36 bundle exec fastlane deployPro
ODR_VERSION=1.36 bundle exec fastlane deployLite
ODR_DRY_RUN=true bundle exec fastlane deployPro   # build and sign only
bundle exec fastlane uploadListingPro              # text, plus screenshots if present
bundle exec fastlane screenshots                   # see fastlane/screenshots/README.md
```

`deployPro` is `buildPro` and then `uploadPro`. `fastlane/README.md` lists all
lanes.

## License

[Mozilla Public License 2.0](LICENSE).
