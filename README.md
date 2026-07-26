# OpenDocument.ios ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/build_test.yml/badge.svg) ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/format.yml/badge.svg)
It's Android's first OpenOffice Document Reader... for iOS!

This is an iOS frontend for our C++ [OpenDocument.core](https://github.com/opendocument-app/OpenDocument.core) library.

## Setup

Our C++ dependencies come from [conan-odr-index](https://github.com/opendocument-app/conan-odr-index),
which is checked out as a submodule and exported into the local conan cache. No
private conan remote is involved.

The helper scripts in that submodule need python 3.12 or newer — they use PEP
701 f-strings, which are a syntax error on 3.11.

1. `git submodule update --init --depth 1 conan-odr-index`
2. `python3.12 -m venv .venv && source .venv/bin/activate`
3. install conan into that venv: `pip install -r conan-odr-index/requirements.txt`
4. `conan profile detect`
5. `conan/setup-all.sh` — exports the recipes and generates the xcconfigs for
   every configuration and architecture. The first run builds odrcore and its
   dependencies from source and takes a while.
6. open `OpenDocumentReader.xcodeproj` in Xcode

Everything else comes from Swift Package Manager and is resolved by Xcode.

`conan/setup-all.sh` has to be re-run whenever the odrcore version in
`conan/conanfile.py` or the `conan-odr-index` submodule changes.

## How a document reaches the screen

`CoreWrapper` hands the file to odrcore, which returns an `HtmlService`: a
handle that knows which views the document has but has not rendered any of
them. That service is connected to odrcore's HTTP server, bound to
`127.0.0.1:29665`, and the web view is pointed at
`http://127.0.0.1:29665/file/<prefix>/<page>.html`. odrcore renders a page when
the web view asks for it, on one of the server's threads.

The same thing OpenDocument.droid does, and for the same reasons: rendering
happens off the thread that opened the document, only the pages that are looked
at are rendered at all, and turning a page is a navigation rather than another
translation. The `<prefix>` changes on every translation, because the web view
caches by URL and a document re-translated after a password or an edit has to
land on an address it has not seen.

`kCoreWrapperServesOverHttp` in `CoreWrapper.mm` switches back to writing the
pages out as files, which is also what happens automatically if the port cannot
be bound. It is there to keep that path working while the migration finishes,
not as a runtime option.

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
| `release` | manual upload to App Store Connect, see below |

`format` needs nothing but the Xcode toolchain and reports style breakage in a
minute, so it is kept apart from the native build. Everything that does need
odrcore shares `.github/actions/setup-odrcore`, which resolves the C++
dependencies with conan and caches them per Xcode version and profile.

## Releasing

The `release` workflow uploads a build to App Store Connect. It is manual
(`workflow_dispatch`) and never submits for review, so
promoting a build stays a deliberate step in App Store Connect. Build numbers
come from whatever TestFlight already has, so nothing needs to be committed to
cut a release.

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

The same lanes work locally once those variables are exported:

```bash
bundle exec fastlane deployPro
bundle exec fastlane deployLite
```
