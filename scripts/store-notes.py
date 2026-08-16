#!/usr/bin/env python3
#
# The store copy of one release: where it is kept, and the deliver tree built
# out of it.
#
# App Store Connect keeps only the notes of the submission in flight, so the
# history it throws away is kept here instead: one file per locale per marketing
# version, `fastlane/metadata/<locale>/changelogs/1.41.txt`.
#
# deliver reads none of that. It reads `release_notes.txt` beside it, one per
# locale, and uploads every metadata file it finds - so the upload is pointed at
# a directory staged from these files and holding nothing else, which keeps the
# descriptions checked in here out of it.
#
#   scripts/store-notes.py --version 1.41              check every locale has copy
#   scripts/store-notes.py --version 1.41 --stage DIR  also write the deliver tree
#
# A release run checks before it builds, so a version missing a translation
# fails in seconds rather than once both apps are uploaded.
# `scripts/store-copy.py` writes the files this reads.

import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane" / "metadata"

# what App Store Connect takes in one locale's "What's New"
LIMIT = 4000


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


def stage(texts, directory):
    """Write the metadata tree deliver uploads: one release_notes.txt per locale."""
    directory = Path(directory)
    for locale, text in texts.items():
        folder = directory / locale
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "release_notes.txt").write_text(text + "\n", encoding="utf-8")
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
            stage(texts, args.stage)
        except OSError as reason:
            return fail(str(reason))
        print(f"staged {len(texts)} locales for {version} in {args.stage}")
    else:
        print(f"{version} has store copy in all {len(texts)} locales: {', '.join(texts)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
