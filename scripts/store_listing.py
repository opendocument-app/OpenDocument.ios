#!/usr/bin/env python3
# Validate and stage versioned store notes and app-specific listing metadata.
# Usage: scripts/store_listing.py --version VERSION [--stage DIR --app pro|lite]

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane" / "metadata"

# Apply app-wide overrides before locale-specific overrides.
APPS = ("pro", "lite")
EVERY_LOCALE = "all"

# Require every supported storefront locale, even if its directory is missing.
LOCALES = (
    "de-DE",
    "en-US",
    "es-ES",
    "fr-FR",
    "hi",
    "it",
    "pl",
    "pt-BR",
    "ru",
    "sv",
    "tr",
)

# what App Store Connect takes in one locale's "What's New"
LIMIT = 4000

# Required deliver metadata fields; missing fields would retain stale store values.
REQUIRED = (
    "name.txt",
    "subtitle.txt",
    "description.txt",
    "keywords.txt",
)

# The rest, which a locale may genuinely not have.
OPTIONAL = (
    "promotional_text.txt",
    "marketing_url.txt",
    "support_url.txt",
    "privacy_url.txt",
)

LOCALISED = REQUIRED + OPTIONAL

# Attached to the version rather than to a locale.
NON_LOCALISED = ("copyright.txt",)

# Keep review contact details and store categories out of listing uploads.

# Validate final text after app overrides and placeholders are applied.
LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "description.txt": LIMIT,
    "release_notes.txt": LIMIT,
}

# The names a `${...}` may have. Declared, so that a misspelt one is an error
# rather than a sentence that quietly disappears from the store.
FILL_INS = ("ads", "editing")

# the space in front comes with it, so a fill-in the app leaves empty does not
# leave a double space in the middle of a sentence
FILL_IN = re.compile(r"( ?)\$\{([a-z_]+)\}")


def locales(metadata=METADATA):
    """The locales the listing has, in order. Every one of LOCALES, or an error."""
    # `review_information` and the loose category files sit beside them, so a
    # description is what makes a directory one of them
    found = sorted(d.name for d in metadata.iterdir() if (d / "description.txt").is_file())

    lost = [locale for locale in LOCALES if locale not in found]
    strange = [locale for locale in found if locale not in LOCALES]
    if lost or strange:
        reasons = []
        if lost:
            reasons.append(f"nothing to read in {', '.join(lost)} under {metadata}")
        if strange:
            reasons.append(
                f"{', '.join(strange)} is not one of the languages the store sells in - "
                f"add it to LOCALES in {Path(__file__).name} if it now is"
            )
        raise ValueError("the listing is not in the languages it should be:\n  " + "\n  ".join(reasons))

    return sorted(LOCALES)


def shown(path):
    """A path as it is worth reading in an error: from the repository, where it is in it."""
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


def copy_path(locale, version, metadata=METADATA):
    """Where one locale's copy for one version lives."""
    return metadata / locale / "changelogs" / f"{version}.txt"


def sources(app, locale, metadata=METADATA):
    """Where one locale's text is read from, least specific first."""
    places = [metadata / locale]
    if app:
        own = metadata.parent / f"metadata-{app}"
        places += [own / EVERY_LOCALE, own / locale]
    return places


def read(name, places):
    """Read the last nonempty override; deliver treats empty fields as unchanged."""
    found = None
    for place in places:
        path = place / name
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        if text.strip():
            found = text
    return found


def fill_in(text, places, where):
    """Replace every `${name}` with what the app says, or with nothing."""

    def replace(match):
        space, name = match.groups()
        if name not in FILL_INS:
            raise ValueError(
                f"{where}: ${{{name}}} is not one of {', '.join(FILL_INS)} - "
                f"add it to FILL_INS in {Path(__file__).name} or fix the spelling"
            )
        said = (read(f"{name}.txt", places) or "").strip()
        return space + said if said else ""

    return FILL_IN.sub(replace, text)


def collect(version, metadata=METADATA):
    """The copy of every locale. Returns (texts by locale, reasons it is not usable)."""
    texts = {}
    problems = []

    for locale in locales(metadata):
        path = copy_path(locale, version, metadata)
        display = shown(path)

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


def stage(texts, directory, app=None, metadata=METADATA):
    """Stage version notes and, when app is set, its complete listing metadata."""
    directory = Path(directory)
    if app and app not in APPS:
        raise ValueError(f"no such app: {app} - one of {', '.join(APPS)}")

    oversized = []
    unsaid = []

    def write(folder, name, text, places):
        text = fill_in(text, places, where=f"{folder.name}/{name}")
        limit = LIMITS.get(name)
        if limit and len(text.strip()) > limit:
            oversized.append(f"{folder.name}/{name} is {len(text.strip())} characters, over the store's {limit}")
        (folder / name).write_text(text, encoding="utf-8")

    for locale, notes in texts.items():
        folder = directory / locale
        folder.mkdir(parents=True, exist_ok=True)
        places = sources(app, locale, metadata)

        write(folder, "release_notes.txt", notes + "\n", places)

        if not app:
            continue

        for name in LOCALISED:
            text = read(name, places)
            if text is not None:
                write(folder, name, text, places)
            elif name in REQUIRED:
                unsaid.append(f"{name}, in none of {', '.join(f'{shown(p)}/' for p in places)}")

    if app:
        for name in NON_LOCALISED:
            text = read(name, [metadata, metadata.parent / f"metadata-{app}"])
            if text is not None:
                (directory / name).write_text(text, encoding="utf-8")

    if unsaid:
        raise ValueError(
            "the listing does not say everything it has to:\n  "
            + "\n  ".join(unsaid)
            + "\nUnwritten is not blank: App Store Connect would keep what it already has."
        )

    if oversized:
        raise ValueError("the store would refuse this listing:\n  " + "\n  ".join(oversized))

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
        "--app",
        choices=APPS,
        help="stage the whole listing as this app says it, not the release notes alone",
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
            stage(texts, args.stage, app=args.app)
        except (OSError, ValueError) as reason:
            return fail(str(reason))
        what = f"the {args.app} listing and notes" if args.app else "the notes"
        print(f"staged {what} of {len(texts)} locales for {version} in {args.stage}")
    else:
        print(f"{version} has store copy in all {len(texts)} locales: {', '.join(texts)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
