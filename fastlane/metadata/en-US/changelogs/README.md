# Release notes

One file per marketing version, holding the "What's New" text for that
submission. Written for users of the app, not for this repository: the
developer-facing record of the same release is in `CHANGELOG.md` at the root.

Named by marketing version (`1.37.txt`), not by build number. The build number
is a live query of what TestFlight already has, so it is not known until a
release run starts and cannot name a file committed ahead of it.

`deliver` does not read this directory. It reads one file per locale,
`fastlane/metadata/<locale>/release_notes.txt`, and the upload skips metadata
entirely (`skip_metadata: true` in `fastlane/Fastfile`), because promoting a
build is a deliberate step in App Store Connect rather than something a tag
push does. So the notes for a release are pasted into App Store Connect by
hand, from the file for that version.

App Store Connect keeps only the notes for the version being submitted, so
these files are the history that the store does not keep. The limit is 4000
characters.

Only en-US is kept, matching OpenDocument.droid. Other locales fall back to the
English text in the store.
