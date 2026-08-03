# Changelog

User-facing changes to OpenDocument Reader for iOS. Changes to the shared
OpenDocument core that the app picked up are listed under the release that
shipped them.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Entries go under `Unreleased` as the change lands, in the same pull request.
Cutting a release renames that heading to the version and adds its compare
link; nothing in the build reads this file, so `project.pbxproj` keeps its
`0.0.0` and the version still comes from the tag.

The copy that App Store Connect shows under "What's New" is a different, shorter
register, and lives in `fastlane/metadata/en-US/changelogs/<version>.txt`. It is
pasted into App Store Connect at submission time; see the README there.

## [Unreleased]

## [1.37] - 2026-08-02

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

[Unreleased]: https://github.com/opendocument-app/OpenDocument.ios/compare/1.37...HEAD
[1.37]: https://github.com/opendocument-app/OpenDocument.ios/compare/1.36...1.37
[1.36]: https://github.com/opendocument-app/OpenDocument.ios/compare/1.35...1.36
[1.35]: https://github.com/opendocument-app/OpenDocument.ios/compare/1.34...1.35
