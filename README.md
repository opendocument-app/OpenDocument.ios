# OpenDocument.ios ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/build_test.yml/badge.svg) ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/format.yml/badge.svg)
It's Android's first OpenOffice Document Reader... for iOS!

This is an iOS frontend for our C++ [OpenDocument.core](https://github.com/opendocument-app/OpenDocument.core) library.

## Setup

Open `OpenDocumentReader.xcodeproj` in Xcode. Everything comes from Swift
Package Manager and is resolved by Xcode — odrcore included, as the prebuilt
`OdrCoreObjC.xcframework` the
[OdrCore](https://github.com/opendocument-app/OpenDocument.core) package
downloads from its release. There is no conan step and no C++ toolchain to set
up.

To try an unreleased odrcore, point the package reference at a local checkout
and build the xcframework there:

```sh
cd ../OpenDocument.core
apple/build_xcframework.py slice && apple/build_xcframework.py assemble
```

Its `Package.swift` then takes `ODR_XCFRAMEWORK=OdrCoreObjC.xcframework` from the
environment of every `xcodebuild` invocation instead of the release artifact.

## How a document reaches the screen

`CoreWrapper` hands the file to odrcore, which returns an `HtmlService`: a
handle that knows which views the document has but has not rendered any of
them. That service is connected to odrcore's HTTP server, bound to `127.0.0.1`
on whichever port was free, and the web view is pointed at
`http://127.0.0.1:<port>/file/<prefix>/<page>.html`. odrcore renders a page when
the web view asks for it, on one of the server's threads.

The same thing OpenDocument.droid does, and for the same reasons: rendering
happens off the thread that opened the document, only the pages that are looked
at are rendered at all, and turning a page is a navigation rather than another
translation. The `<prefix>` changes on every translation, because the web view
caches by URL and a document re-translated after a password or an edit has to
land on an address it has not seen.

`kCoreWrapperServesOverHttp` in `CoreWrapper.mm` switches back to writing the
pages out as files, which is also what happens automatically if the socket
cannot be opened at all. It is there to keep that path working while the
migration finishes, not as a runtime option.

Nothing about this needs a capability or prompts the user. A listening socket on
loopback takes no entitlement, and the local network permission introduced in
iOS 14 covers the local subnet and multicast, not `127.0.0.1`. The one thing it
does need is an App Transport Security exception, since ATS blocks plain HTTP:
`NSAllowsLocalNetworking` in both `Info.plist`s, which is the narrow one for
local addresses and — unlike `NSAllowsArbitraryLoads` — needs no justification
in App Store review.

## Formatting

Swift sources are formatted with `swift-format` from the active Xcode
toolchain, configured in `.swift-format`. Run `scripts/format.sh` before
committing; CI runs `scripts/format.sh --check` and fails on any difference.

## Continuous integration

| workflow | what it does |
| --- | --- |
| `format` | `scripts/format.sh --check`, on every push and pull request |
| `build_test` | unit tests on the simulator plus a device build of both flavors |
| `release` | upload to App Store Connect on a version tag, see below |

`format` needs nothing but the Xcode toolchain and reports style breakage in a
minute, so it is kept apart from the build.

## Releasing

The `release` workflow uploads a build to App Store Connect. It runs on a
version tag or by hand (`workflow_dispatch`), and never submits for review, so
promoting a build stays a deliberate step in App Store Connect.

Nothing has to be committed to cut a release, and a release leaves no commit
behind either. Both halves of the version come from outside the tree:

| | where it comes from | what is checked in |
| --- | --- | --- |
| `MARKETING_VERSION` (`CFBundleShortVersionString`) | the git tag | `0.0.0` |
| `CURRENT_PROJECT_VERSION` (`CFBundleVersion`) | latest TestFlight build + 1 | `1` |

So a release is `git tag 1.36 && git push --tags`, and the version in
`project.pbxproj` is a placeholder that only local and CI builds ever see. The
tag has to be above what is live in the store - App Store Connect is the only
thing that knows what that is, and it rejects the upload otherwise.

`.github/scripts/resolve-version.py` decides which version a run builds and
refuses runs that cannot name one; run it by hand to see what a dispatch would
do. A dispatched run takes a `version` input instead of a tag, which is how a
release whose upload failed gets finished off the branch it was cut from.

The `dry_run` input builds, signs and archives the `.ipa` without uploading it -
the only way to exercise the signing path without putting a build on TestFlight.
It is also the only kind of run allowed to go without a version.

It needs these repository secrets:

| secret | what it is |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | issuer id of that key |
| `ASC_KEY_CONTENT` | the `.p8` private key, base64 encoded |
| `SIGNING_CERTIFICATE_P12` | Apple Distribution certificate + key as a base64 encoded `.p12` |
| `SIGNING_CERTIFICATE_PASSWORD` | password of that `.p12` |

The certificate is imported into a temporary keychain that is discarded with the
runner. Provisioning profiles are created on demand via
`-allowProvisioningUpdates`.

The same lanes work locally once those variables are exported, and take the
version and the dry run the same way the workflow hands them over:

```bash
ODR_VERSION=1.36 bundle exec fastlane deployPro
ODR_VERSION=1.36 bundle exec fastlane deployLite
ODR_DRY_RUN=true bundle exec fastlane deployPro   # build and sign only
```
