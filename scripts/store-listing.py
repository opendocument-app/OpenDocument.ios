#!/usr/bin/env python3
#
# The App Store listing: where it is kept, and the deliver tree built out of it.
#
# App Store Connect keeps only the notes of the submission in flight, so the
# history it throws away is kept here instead: one file per locale per marketing
# version, `fastlane/metadata/<locale>/changelogs/1.41.txt`.
#
# deliver reads none of that. It reads `release_notes.txt` beside it, one per
# locale, and uploads every metadata file it finds - so it is pointed at a
# staged directory rather than at fastlane/metadata itself, and what is copied
# in is named here rather than being whatever happens to be lying around.
#
#   scripts/store-listing.py --version 1.41                     check the notes
#   scripts/store-listing.py --version 1.41 --stage DIR         notes alone
#   scripts/store-listing.py --version 1.41 --stage DIR --full  the whole listing
#
# A release run checks before it builds, so a version missing a translation
# fails in seconds rather than once both apps are uploaded.
# `scripts/store-copy.py` writes the release notes this reads.

import argparse
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane" / "metadata"

# what App Store Connect takes in one locale's "What's New"
LIMIT = 4000

# The text of the listing, per locale, as deliver names it. Listed rather than
# globbed so that adding a file here is a decision: everything in this set is
# pushed over whatever App Store Connect currently says.
LOCALISED = (
    "name.txt",
    "subtitle.txt",
    "description.txt",
    "keywords.txt",
    "promotional_text.txt",
    "marketing_url.txt",
    "support_url.txt",
    "privacy_url.txt",
)

# Attached to the version rather than to a locale.
NON_LOCALISED = ("copyright.txt",)

# Left behind deliberately, though deliver would take them: `review_information`
# is the account's own contact details and the note to the reviewer, and the
# category files say where the app sits in the store. Neither is release copy,
# and a release is a poor moment to discover either had drifted.


def locales(metadata=METADATA):
    """The locales the listing has, in order."""
    # `review_information` and the loose category files sit beside them, so a
    # description is what makes a directory one of them
    found = sorted(d.name for d in metadata.iterdir() if (d / "description.txt").is_file())
    if not found:
        raise ValueError(f"{metadata} holds no locale directories")
    return found


def copy_path(locale, version, metadata=METADATA):
    """Where one locale's copy for one version lives."""
    return metadata / locale / "changelogs" / f"{version}.txt"


def collect(version, metadata=METADATA):
    """The copy of every locale. Returns (texts by locale, reasons it is not usable)."""
    texts = {}
    problems = []

    for locale in locales(metadata):
        path = copy_path(locale, version, metadata)
        display = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path

        if not path.is_file():
            problems.append(f"{locale}: no {display}")
            continue

        text = path.read_text(encoding="utf-8").strip()
        if not text:
            problems.append(f"{locale}: {display} is empty")
        elif len(text) > LIMIT:
            problems.append(f"{locale}: {display} is {len(text)} characters, over the store's {LIMIT}")
        else:
            texts[locale] = text

    return texts, problems


def stage(texts, directory, full=False, metadata=METADATA):
    """Write the metadata tree deliver uploads.

    The release notes of this version always. With `full`, the rest of the
    listing text beside them - which is what makes this repository, rather than
    App Store Connect, the place the listing is written.
    """
    directory = Path(directory)

    for locale, text in texts.items():
        folder = directory / locale
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "release_notes.txt").write_text(text + "\n", encoding="utf-8")

        if not full:
            continue

        for name in LOCALISED:
            source = metadata / locale / name
            # an empty file would say nothing to deliver anyway, which reads it
            # as "leave this be" rather than "clear it"
            if source.is_file() and source.read_text(encoding="utf-8").strip():
                shutil.copyfile(source, folder / name)

    if full:
        for name in NON_LOCALISED:
            source = metadata / name
            if source.is_file() and source.read_text(encoding="utf-8").strip():
                shutil.copyfile(source, directory / name)

    return directory


def fail(message):
    if os.environ.get("GITHUB_ACTIONS"):
        # also surfaces as an annotation on the run, not only inside the step log
        print(f"::error::{message}")
    else:
        print(message, file=sys.stderr)
    return 1


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Check the store copy of one release, and stage it for deliver."
    )
    parser.add_argument("--version", required=True, help="marketing version, e.g. 1.41")
    parser.add_argument(
        "--stage",
        metavar="DIR",
        help="also write the deliver metadata tree into DIR",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="stage the whole listing, not the release notes alone",
    )
    args = parser.parse_args(argv)

    version = args.version.strip().removeprefix("v")

    try:
        texts, problems = collect(version)
    except (OSError, ValueError) as reason:
        return fail(str(reason))

    if problems:
        return fail(
            f"no store copy to release {version} with:\n  "
            + "\n  ".join(problems)
            + f"\nRun scripts/store-copy.py {version} to write it."
        )

    if args.stage:
        try:
            stage(texts, args.stage, full=args.full)
        except OSError as reason:
            return fail(str(reason))
        what = "the listing and notes" if args.full else "the notes"
        print(f"staged {what} of {len(texts)} locales for {version} in {args.stage}")
    else:
        print(f"{version} has store copy in all {len(texts)} locales: {', '.join(texts)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
