# Store metadata

What App Store Connect shows about the app, one directory per locale.

This is where the listing is written, and a release run uploads it: name,
subtitle, description, keywords, the URLs, and the release notes of the version
going out. What the store says is what is committed here.

Two things are left out of the upload on purpose. `review_information` is the
account's contact details and the note to the reviewer, and the category files
say where the app sits in the store - neither is release copy.
`scripts/store-listing.py` names what is staged, so adding a file to that list is
a decision rather than an accident.

Only Pro's listing lives here. An app's name has to be unique in the store, so
pushing this to Lite would rename Lite to Pro; Lite takes the release notes and
nothing else until its own listing is checked in beside this one.

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
locale, so `scripts/store-listing.py` stages the version's file under that name
into a throwaway directory at upload time, with the rest of the listing beside
it.

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

## Name, subtitle, keywords

30 characters for the name, 30 for the subtitle, 100 for the keywords, counting
the commas. The App Store indexes name and subtitle as well as keywords, so a
word in one of those is wasted in the other: none of the keyword lists here
repeats a word from its own name or subtitle. Every listing leads with
`LibreOffice`, which is the strongest thing the app has to be found by, and says
somewhere that it edits and does not only read.
