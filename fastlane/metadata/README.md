# Store metadata

What App Store Connect shows about the apps, one directory per locale.

This is where the listing is written, and a release run uploads it: name,
subtitle, description, keywords, the URLs, and the release notes of the version
going out. What the store says is what is committed here.

Two things are left out of the upload on purpose. `review_information` is the
account's contact details and the note to the reviewer, and the category files
say where the app sits in the store - neither is release copy.
`scripts/store_listing.py` names what is staged, so adding a file to that list is
a decision rather than an accident.

## The two apps

Pro and Lite are the same app, and they say almost the same thing about
themselves. What is here is what they share. Where they have to differ:

| | |
| --- | --- |
| `fastlane/metadata/<locale>/` | what both say |
| `fastlane/metadata-<app>/all/` | what this app says instead, in every locale |
| `fastlane/metadata-<app>/<locale>/` | what this app says instead, here |

Read in that order, last one wins. `<app>` is `pro` or `lite`.

Only the name differs outright, and it has to: an app's name is unique in the
store, so one file each, `OpenDocument Reader Pro` and `OpenDocument Reader`.
There is no `name.txt` in this directory - the apps own their names.

One sentence differs inside otherwise shared text, which is the advertising
line: Lite shows ads and Pro does not. Rather than keep two descriptions per
locale and let them drift, the shared one holds `${ads}` and each app fills it
in from its own `ads.txt` - Lite has one per locale, Pro has none, and a
fill-in nobody answers leaves nothing behind, the space in front of it
included. `FILL_INS` in `scripts/store_listing.py` lists the names one may
have, so a misspelt `${adds}` is an error rather than a sentence that quietly
vanishes from the store.

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
locale, so `scripts/store_listing.py` stages the version's file under that name
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
the commas. `scripts/store_listing.py` checks all three against what it stages
rather than against what is written here, since an app's own name is what
finally has to fit.

The name is the same in every storefront and is not translated: `OpenDocument`
is the format's own name and goes untranslated in every language anyway, and one
name is one app that people can pass to each other. Nothing is lost to search by
it, because the App Store indexes name, subtitle and keywords alike - so the
local words, `LibreOffice` among them, live in the subtitle and the keywords
instead. That also means a keyword repeating a word from the name or from its
own subtitle is a wasted slot; none of these do.

None of it sells the app as an editor. It edits text, but that is young and does
not reach every document, so the listing says so once and calls itself a reader.
