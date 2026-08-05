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
| `release` | upload to App Store Connect, by hand, see below |

`format` needs nothing but the Xcode toolchain and reports style breakage in a
minute, so it is kept apart from the build.

## Releasing

The `release` workflow uploads a build to App Store Connect. It is dispatched by
hand, and never submits for review, so promoting a build stays a deliberate step
in App Store Connect:

```sh
gh workflow run release.yml -f version=1.38
```

It runs as three jobs:

| job | what it does |
| --- | --- |
| `build` | one run producing both signed `.ipa`s, archived on the run |
| `upload` | one job per app, uploading its `.ipa` |
| `record` | once both landed: tag the build, draft the GitHub release |

Both apps always go out together, and nothing chooses one. Pro and Lite are the
same app - the target switches ads and tracking off, nothing else - so anything
worth rebuilding one for is worth rebuilding the other for.

**If one app's upload fails, press "Re-run failed jobs".** Only that upload runs
again, against the `.ipa` already built and signed - build number included, since
it is baked in at archive time - and `record` runs behind it once it lands.

Nothing has to be committed to cut a release, and a release leaves no commit
behind either. Both halves of the version come from outside the tree:

| | where it comes from | what is checked in |
| --- | --- | --- |
| `MARKETING_VERSION` (`CFBundleShortVersionString`) | the `version` input | `0.0.0` |
| `CURRENT_PROJECT_VERSION` (`CFBundleVersion`) | one above the highest build either app has | `1` |

The version in `project.pbxproj` is a placeholder that only local and CI builds
ever see. Nobody bumps it: a commit on `main` is not a release, and `0.0.0` says
so. The version has to be above what is live in the store - App Store Connect is
the only thing that knows what that is, and it rejects the upload otherwise.

The build number is resolved once and given to both apps, so one `(version, build)`
pair names one commit in both listings. App Store Connect only requires the number
to increase, not to be contiguous, so whichever app was behind simply skips ahead.

`.github/scripts/resolve-version.py` decides which version a run builds and
refuses runs that cannot name one. Before building, the run also refuses a version
with no `CHANGELOG.md` section - that section becomes the release body, and finding
it missing afterwards leaves nothing to fix but the version number;
`changelog-section.py` is what reads it. Run either by hand to see what a dispatch
would do.

The `dry_run` input builds, signs and archives both `.ipa`s without uploading
either - the only way to exercise the signing path without putting a build on
TestFlight. It is also the only kind of run allowed to go without a version, and
the only one that leaves neither tag nor draft.

It needs these repository secrets:

| secret | what it is |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | issuer id of that key |
| `ASC_KEY_CONTENT` | the `.p8` private key, base64 encoded |
| `SIGNING_CERTIFICATE_P12` | Apple Distribution certificate + key as a base64 encoded `.p12` |
| `SIGNING_CERTIFICATE_PASSWORD` | password of that `.p12` |

The certificate is imported into a temporary keychain that is discarded with the
runner, and signing is manual: fastlane downloads the App Store provisioning
profile for the bundle id, and both the archive and the export use that
certificate and profile. Automatic signing would instead have Xcode mint
distribution assets of its own, which only an Admin key may do - anything less
fails the export with "Cloud signing permission error".

Downloading a profile is something any key may do; creating one wants an Admin
key. So a lesser key works as long as both apps have an App Store profile
already - the run says so in its first seconds otherwise, and either an Admin key
or a profile made by hand in the developer portal gets past it. Profiles expire
after a year, which is the other moment this matters.

The same lanes work locally once those variables are exported, and take the
version and the dry run the same way the workflow hands them over:

```bash
ODR_VERSION=1.36 bundle exec fastlane deployPro
ODR_VERSION=1.36 bundle exec fastlane deployLite
ODR_DRY_RUN=true bundle exec fastlane deployPro   # build and sign only
```

`deployPro` is `buildPro` followed by `uploadPro`, which the workflow runs as
separate jobs. `uploadPro` takes the `.ipa` already in `build/` rather than making
one, and `resolveBuildNumber` prints the number both apps would get.

### Tags

Nothing is triggered by a tag, and no tag is pushed before a build. A version
often takes more than one build to get through review, so a tag pushed up front
names a commit that may never ship - which is what happened to `1.37`, whose tag
points at a commit that was superseded before submission.

Tags are written afterwards instead, in two kinds:

| tag | who writes it | what it means |
| --- | --- | --- |
| `build/<version>/<build>` | the workflow, once both apps are up | this commit was uploaded as that build |
| `<version>` | publishing the drafted release | this is what shipped |

One build tag, not one per app: both share a build number, so there is one
`(version, build)` pair and one commit to name. It is never moved, and a rebuild
simply gets the next number - a version that takes three builds to clear review
leaves three build tags, which is the point of having the number in there. A half
uploaded release gets no tag at all, and a lane run locally leaves none either, so
an upload made by hand off a laptop is not recorded.

**The version tag is written neither by hand nor by the workflow.** `record` drafts
a GitHub release named `<version>` pointing at the built commit. A draft creates no
tag; publishing it does, at exactly that commit:

```sh
gh release edit 1.38 --draft=false
```

That is the whole manual step, and it stays human because App Store Connect is the
only thing that knows a build passed review and went live. A rebuild re-points the
same draft rather than making a second one.

The release body is the version's `CHANGELOG.md` section with the generated list of
pull requests below it.

If Pro clears review and Lite does not, wait - the build tags already record
what went out, so nothing is lost by leaving the version tag until both are
through.
