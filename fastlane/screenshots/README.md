# Store screenshots

The pictures App Store Connect shows of the app. Nothing here is committed. A
capture run writes the raw pictures to this directory and the framed set to
`fastlane/framed`, and the release run archives both as artifacts. Screenshots
are taken during the release run, from the build that goes out.

```sh
bundle exec fastlane ios screenshots      # capture, then frame
scripts/frame-screenshots.py              # frame again, without a capture
```

The lane does these steps:

1. `scripts/make-screenshot-documents.py` writes the localized sample
   documents. They are build output and go into Debug builds only.
2. `fastlane snapshot` builds the `ODR Screenshots` scheme once and launches
   the app once per screen and locale, with `-ODRScreenshot <screen>`. See
   `OpenDocumentReader/ScreenshotMode.swift`.
3. `scripts/frame-screenshots.py` puts each capture on a device frame with a
   headline from `fastlane/frames/frames.json`. It needs Pillow.
4. `scripts/store_screenshots.py` checks the framed set against the sizes the
   store accepts.

## The set

Six screens per device, in store order:

| | |
| --- | --- |
| `01-browser` | the document browser, with one file of each format |
| `02-text` | a text document |
| `03-sheet` | a spreadsheet, with its sheet tabs |
| `04-edit` | a document in edit mode, keyboard up |
| `05-pdf` | a PDF, with a search under way |
| `06-office` | a Word file |

Two devices: a 6.9" iPhone and a 13" iPad. `Fastfile` lists the simulator
names to look for, newest first. `scripts/store_screenshots.py` lists the
pixel sizes the store accepts.

## Locales

The store has eleven locales and the app has nine. `hi` and `sv` get the
English pictures, because the app has no Hindi or Swedish UI.
`scripts/store_screenshots.py --languages` prints the locales to capture.

## Both apps

The set is taken once, with the `ODR Screenshots` scheme. That scheme builds
the Pro target, which links no ad sdk, so no consent form can appear. Both
listings get the same pictures.
