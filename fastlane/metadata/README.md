# Store metadata

The text App Store Connect shows about the apps, one directory per locale. A
release run uploads what is committed here: name, subtitle, description,
keywords, the URLs and the release notes of the version. It does not upload
`review_information` or the category files.

## Layout

Pro and Lite say almost the same thing. `scripts/store_listing.py` reads these
places in order, and the last one wins:

| | |
| --- | --- |
| `fastlane/metadata/<locale>/` | what both apps say |
| `fastlane/metadata-<app>/all/` | what this app says instead, in every locale |
| `fastlane/metadata-<app>/<locale>/` | what this app says instead, in this locale |

`<app>` is `pro` or `lite`.

- The name differs, because a store name is unique. Each app has one
  `all/name.txt`, and this directory has none.
- The shared description holds `${ads}` and `${editing}`. Each app fills them
  from its own `ads.txt` and `editing.txt` in that locale. Lite has an
  `ads.txt`, Pro has none, and an empty fill-in leaves no space behind.
- `FILL_INS` in `scripts/store_listing.py` lists the allowed names, so a
  misspelt fill-in is an error.

## Limits

| file | limit |
| --- | --- |
| `name.txt`, `subtitle.txt` | 30 characters |
| `keywords.txt` | 100 characters, commas included |
| `changelogs/<version>.txt` | 4000 characters |

The name is the same in every locale. The local search words, `LibreOffice`
among them, go in the subtitle and the keywords.

## Release notes

`<locale>/changelogs/<version>.txt` holds the "What's New" text of one
marketing version. App Store Connect keeps only the notes of the current
submission, so these files are the history. `scripts/store_listing.py` stages
the version's file as `release_notes.txt` for `deliver`.

Write them with:

```sh
scripts/store-copy.py 1.41
```

1. The English comes from the `CHANGELOG.md` section of that version, or from
   `Unreleased` while the heading is open. An existing file is kept.
2. One agent per locale translates it, with that locale's `description.txt`
   and the previous notes as context.
3. A second agent reviews each draft against the English.
4. Read the diff, then commit it in the pull request that cuts the version.

Both apps get the same notes, so the notes never say "free" or "Pro". The
release run refuses a version that has no notes in some locale.
