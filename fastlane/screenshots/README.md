# Store screenshots

What App Store Connect shows of the app, one directory per locale - written
here by a capture run, and not committed. This directory is empty in the
repository on purpose.

The store copy next door is text somebody wrote, so it lives in git and the
release uploads what is committed. A screenshot is not written, it is taken:
it is only worth what the build it was taken from is worth, and a picture of
1.38 sitting in git through 1.41 is a picture of an app nobody can install any
more. So they are taken during the release run, from the build going out.

```sh
bundle exec fastlane ios screenshots
```

That drives the app on both devices in every locale and writes them here.
`.gitignore` keeps what it wrote out of commits, and the release run archives
the same set as the `screenshots` artifact - which is how you look at what went
to the store, before it does on a dry run and after it on a real one.

## What is in a set

Four pictures per device, taken by relaunching the app onto one screen at a
time rather than by tapping through it. The screens, in the order the store
shows them:

| | |
| --- | --- |
| `01-intro` | the onboarding pages, which is the app's own words |
| `02-text` | a text document open |
| `03-sheet` | a spreadsheet, with the sheet tabs under the tool bar |
| `04-slides` | a presentation |

Two devices, because an app that runs on iPhone and iPad has to hand in both: a
6.9" iPhone and a 13" iPad. `scripts/store-screenshots.py` holds the sizes App
Store Connect accepts and checks the set against them; `Fastfile` holds the
simulators to look for, newest first, because what a simulator is called
changes with every Xcode and what it is worth does not.

## Locales

Eleven in the store, nine in the app. `de-DE`, `en-US`, `es-ES`, `fr-FR`, `it`,
`pl`, `pt-BR`, `ru` and `tr` are photographed in their own language. `hi` and
`sv` are given the English pictures, because the app has no Hindi or Swedish UI
either - that is what those storefronts would show whatever we upload.

The documents in the pictures are localized too, which is most of what a reader
has to show: `scripts/make-screenshot-documents.py` writes them, they are
bundled into Debug builds only, and `-ODRScreenshot <screen>` is how the app is
asked to open one. See `OpenDocumentReader/ScreenshotMode.swift`.

## Both apps get the same pictures

Pro and Lite are one app built twice, and the one thing that differs on screen -
the banner Lite carries - is not in a screenshot either way. The set is taken
once, with the Pro scheme, which links no ad sdk and so cannot raise a consent
form in front of the camera. Both listings are then given it.
