# Changelog

Developer-facing changes to OpenDocument Reader for iOS, in [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/) format. Changes to the shared
OpenDocument core are listed under the release that shipped them. The shorter
"What's New" copy the store shows lives in
`fastlane/metadata/en-US/changelogs/`.

Entries go under `Unreleased` in the pull request that makes the change. The
heading is cut when the release is **submitted**, in one pull request that also
writes the store copy for that version.

A release run refuses a version with no section here, and makes that section the
body of the GitHub release it drafts. Until the release is out the section stays
open: **a second build under the same version goes under the already cut
heading, not back under `Unreleased`.** Date the heading and add its compare link
once the version tag exists.

## [Unreleased]

### Changed

- PDFs are rendered by odrcore, like every other document, instead of being
  handed to the web view. Their text is in the page rather than behind the
  system viewer, so they will be searchable as soon as odrcore writes the
  search script for a pdf page as it does for a document. A password protected
  one is asked for its password by the same prompt the other formats use.
- The search button leaves the tool bar when the document on screen cannot be
  searched, rather than sitting there greyed out - the same as the edit button.
  Whether a page can be searched is asked of the page itself.

## [1.40]

### Changed

- A document wider than the screen opens fitted to it rather than running off
  the edge, which is what it has always done on Android.
- The way out of a document is a back chevron, not the words "Back to
  documents".
- Documents that can be edited offer a pencil next to the search button.
  Editing has left the menu, which is where it used to hide.

### Fixed

- The buttons above an open document no longer sit on the status bar, and the
  empty band below them is gone.

## [1.39]

### Changed

- The engine is odrcore 6.6.0, up from 6.5.0. Everything below is what it
  renders differently.
- Slides show text that was there all along but drawn in no font at all.
- Pictures sit where the document puts them: centred where the file centres
  them, inside their frame, and in the box a letter pins them to rather than
  adrift in the running text.
- Documents built on a template keep the margins that template leaves free, such
  as the room a letterhead needs.
- Spreadsheet cells are set in the font the file names, rather than the sheet's
  own throughout.
- Large documents take less memory to open.

### Fixed

- A document whose styles are built on one another many levels deep opens
  instead of taking the app down with it.

## [1.38] - 2026-08-10

### Added

- The Lite app offers the ad-free version in the banner slot when no ad fills
  it, rotating through three wordings, instead of leaving a gap.
- The Lite app asks for advertising consent before it shows its first ad, in
  the regions where Google's EU user consent policy requires a consent form.
  The form is Google's own (UMP), the same one the Android app uses.
- A "Privacy" entry in the document browser reopens that choice, and leads to
  the system tracking permission.
- CSV files open as spreadsheets. The separator is worked out from the file,
  quoted fields stay whole, and a value that only looks like a number is left as
  text. They used to be handed to the web view as plain text.

### Changed

- The tracking permission is asked after the consent form, and only where the
  answer allows an ad to carry an advertising identifier. Refusing consent
  leaves limited ads, which carry none, rather than no ads at all.
- Documents keep the side margins of a printed page, which is what they were
  written to look like.
- Documents with pictures open faster and hold less memory: the images are
  fetched as the page needs them instead of being built into it.
- Edit is offered only for a document the engine holds open for editing, rather
  than for anything it managed to render.
- Pro no longer contains the Google ad and consent SDKs. It is built as its own
  target now and links neither, taking its executable from 4.4 MB to 0.5 MB.
- The engine is odrcore 6.5.0, up from 6.2.0. Everything below is what it
  renders differently.
- Word documents break onto the pages they were written for, and numbered lists
  keep their markers when you copy text out of one.
- Spreadsheets are drawn in a quieter grid, under a row and column ruler that
  stays put while scrolling.
- XML files open properly laid out instead of as one long line.

### Fixed

- **Editing a document no longer destroys it.** The save is written to a file
  beside the original and moved into place once it is whole; it used to be
  written over the document it was still reading from, which left an unopenable
  file behind.
- The ad in the Lite app is resized when the device is rotated, instead of
  keeping the shape it was requested at.
- The ad slot in the Lite app no longer shows a brown bar. It was a placeholder
  colour left on the view, showing until an ad loaded and around any banner
  narrower than the screen.
- The promotion in the Lite app advances one wording per showing rather than
  two, so all three are seen.

## [1.37]

No user-facing changes. This release only changes how the app is built and
submitted.

## [1.36] - 2026-08-02

### Added

- Legacy Microsoft formats (.doc, .xls, .ppt) are read by our own
  implementation: character formatting, cell fonts and fills, embedded
  pictures, real slide sizes and slide names.
- OOXML documents: PowerPoint slide size and tables, Excel merged cells and
  value types, Word table merges and line breaks.
- ODF documents: subscript and superscript, percentage line height, first-line
  indent.
- Documents with fixed-size content open fit-to-width on phones.

### Changed

- Requires iOS 15 or later.
- The app no longer collects analytics and no longer reports crashes. All
  Firebase components were removed.
- Pages are rendered when you open them instead of all at once. Documents with
  many pages, slides or sheets open faster, and switching between them no
  longer re-reads the file.
- The page tabs were rewritten: they follow light and dark appearance, each tab
  takes only the width of its own title so one long sheet name no longer pushes
  the others off screen, and they are reachable with VoiceOver.
- File type detection is more reliable, so documents with a wrong or missing
  extension open more often.

### Fixed

- Failures are reported instead of ending the app. Documents where no page
  could be shown, failed imports and a few other states previously crashed.
- Saving an edited document no longer stalls for 30 seconds when the save
  fails; the error is reported right away.
- Word documents: line breaks inside paragraphs are kept.
- PowerPoint documents: read-only files are reported as read-only, and text
  split across several runs is no longer broken apart.

## [1.35] - 2025-06-12

### Added

- Support for the newer ODF encryption scheme, so encrypted documents that
  previously failed to open now open.
- Documents follow the system light and dark appearance.

### Changed

- Colors in OOXML documents are closer to the original.
- General improvements to page styling.

### Fixed

- An incorrect password is now reported as such instead of a generic failure.
- Page handling and decryption fixes when opening protected documents.

[Unreleased]: https://github.com/opendocument-app/OpenDocument.ios/compare/v1.39...HEAD
[1.39]: https://github.com/opendocument-app/OpenDocument.ios/compare/v1.38...v1.39
[1.38]: https://github.com/opendocument-app/OpenDocument.ios/compare/v1.37...v1.38
[1.37]: https://github.com/opendocument-app/OpenDocument.ios/compare/v1.36...v1.37
[1.36]: https://github.com/opendocument-app/OpenDocument.ios/compare/v1.35...v1.36
[1.35]: https://github.com/opendocument-app/OpenDocument.ios/compare/v1.34...v1.35
