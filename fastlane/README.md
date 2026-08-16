fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios buildPro

```sh
[bundle exec] fastlane ios buildPro
```

Build a signed .ipa of the paid app

### ios buildLite

```sh
[bundle exec] fastlane ios buildLite
```

Build a signed .ipa of the ad supported app

### ios uploadPro

```sh
[bundle exec] fastlane ios uploadPro
```

Upload an already built Pro .ipa to App Store Connect

### ios uploadLite

```sh
[bundle exec] fastlane ios uploadLite
```

Upload an already built Lite .ipa

### ios uploadListingPro

```sh
[bundle exec] fastlane ios uploadListingPro
```

Write the paid app's listing, and ODR_VERSION's release notes, to the store

### ios uploadListingLite

```sh
[bundle exec] fastlane ios uploadListingLite
```

Write the ad supported app's listing, and ODR_VERSION's release notes, to the store

### ios deployPro

```sh
[bundle exec] fastlane ios deployPro
```

Build and upload the paid app

### ios deployLite

```sh
[bundle exec] fastlane ios deployLite
```

Build and upload the ad supported app

### ios resolveBuildNumber

```sh
[bundle exec] fastlane ios resolveBuildNumber
```

Print the build number both apps would get

### ios tests

```sh
[bundle exec] fastlane ios tests
```



----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
