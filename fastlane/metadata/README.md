# Store metadata

What App Store Connect shows about the app, one directory per locale.

Only the release notes are ever uploaded from here. Everything else -
descriptions, keywords, names - is a snapshot of the listing taken with
`deliver init`, kept for reading, and never pushed.

## Release notes

`<locale>/changelogs/1.41.txt`, one file per marketing version per locale,
holding the "What's New" text of that submission. Written for people using the
app, not for this repository - the developer-facing record of the same release
is `CHANGELOG.md` at the root.

Named by marketing version, not by build number. The build number is a live
query of what TestFlight already has, so it is not known until a release run
starts and cannot name a file committed ahead of it.

App Store Connect keeps only the notes of the version being submitted, so these
files are the history the store does not keep. The limit is 4000 characters per
locale.

`deliver` does not read this layout. It reads one `release_notes.txt` per
locale, so `scripts/store-notes.py` stages those into a throwaway directory at
upload time - holding nothing else, which is what keeps the descriptions beside
them out of the upload.

## Writing them

```sh
scripts/store-copy.py 1.41
```

The English text comes from the `CHANGELOG.md` section of that version, or from
`Unreleased` while the heading is still open; a file already written by hand is
left alone. Every other locale is then translated by an agent of its own, given
that locale's `description.txt` and the release before it, so the notes reach
for the words the listing already uses in that language.

A second agent then reads that draft against the English, in the same language,
because what a first draft gets wrong is not something it can see: a word
borrowed for its sound rather than its sense reads fine to whoever wrote it.

It writes; it does not upload, and it does not judge. Read the diff before
committing it - it goes to the store as written.

The release run refuses a version any locale has no copy for, before it builds
anything.
