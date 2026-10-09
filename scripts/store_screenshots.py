#!/usr/bin/env python3
# Validate screenshot locales, screens and sizes; optionally stage them for deliver.
# Usage: scripts/store_screenshots.py [--languages] [--screenshots DIR] [--stage DIR --app APP]

import argparse
import os
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCREENSHOTS = ROOT / "fastlane" / "screenshots"

# Map store locales to app languages; None uses English screenshots.
LOCALES = {
    "de-DE": "de",
    "en-US": "en",
    "es-ES": "es",
    "fr-FR": "fr",
    "hi": None,
    "it": "it",
    "pl": "pl",
    "pt-BR": "pt-BR",
    "ru": "ru",
    "sv": None,
    "tr": "tr",
}

FALLBACK = "en-US"

# What one device shows, in the order the store shows them. The same names the
# screenshot test writes - see `OpenDocumentReaderUITests/ScreenshotTests.swift`.
SCREENS = (
    "01-browser",
    "02-text",
    "03-sheet",
    "04-edit",
    "05-pdf",
    "06-office",
)

# The Lite screen that replaces a Pro screen: Lite dims the Pro edit tools.
LITE = {
    "04-edit": "04-edit-lite",
}

APPS = ("pro", "lite")

# Longest name first, so a name that ends another one never matches in its place.
CAPTURED = tuple(sorted(SCREENS + tuple(LITE.values()), key=len, reverse=True))

# Accepted portrait screenshot sizes, grouped by device.
SIZES = {
    "iphone": {
        (1320, 2868),  # 6.9", iPhone 16 Pro Max and later
        (1290, 2796),  # 6.9"/6.7", iPhone 15 Pro Max and 16 Plus
        (1284, 2778),  # 6.5", iPhone 12/13 Pro Max
        (1242, 2688),  # 6.5", iPhone 11 Pro Max
    },
    "ipad": {
        (2064, 2752),  # 13", iPad Pro M4
        (2048, 2732),  # 12.9", iPad Pro
    },
}


def languages():
    """The locales worth capturing: the ones the app can be photographed in."""
    return [locale for locale, language in LOCALES.items() if language]


def borrowed():
    """The locales that read another one's pictures."""
    return [locale for locale, language in LOCALES.items() if not language]


def size(path):
    """The pixel size of a PNG, off its header rather than through a library."""
    with path.open("rb") as file:
        header = file.read(24)

    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path.name} is not a PNG")

    return struct.unpack(">II", header[16:24])


def device(width, height):
    """Which device a picture that size belongs to, or None."""
    for name, sizes in SIZES.items():
        if (width, height) in sizes:
            return name

    return None


def collect(directory):
    """Collect screenshots by locale and device, returning files and validation errors."""
    directory = Path(directory)
    found = {}
    problems = []

    for locale in languages():
        folder = directory / locale
        if not folder.is_dir():
            problems.append(f"{locale}: no {folder}")
            continue

        pictures = {}
        for path in sorted(folder.glob("*.png")):
            screen = next((name for name in CAPTURED if path.stem.endswith(name)), None)
            if screen is None:
                problems.append(f"{locale}: {path.name} is not one of {', '.join(CAPTURED)}")
                continue

            try:
                width, height = size(path)
            except (OSError, ValueError) as reason:
                problems.append(f"{locale}: {reason}")
                continue

            kind = device(width, height)
            if kind is None:
                # Ignore extra simulator sizes; required devices are checked below.
                continue

            pictures.setdefault(kind, {})[screen] = path

        for kind in SIZES:
            missing = [screen for screen in CAPTURED if screen not in pictures.get(kind, {})]
            if missing:
                problems.append(f"{locale}: no {kind} {', '.join(missing)}")

        found[locale] = pictures

    return found, problems


def stage(found, directory, app):
    """Stage screenshots of `app` for deliver, copying English images for fallback locales.

    Lite images take the name of the Pro screen they replace, so they keep its store position.
    """
    directory = Path(directory)

    for locale, pictures in found.items():
        folder = directory / locale
        folder.mkdir(parents=True, exist_ok=True)
        for kind, screens in pictures.items():
            for screen in SCREENS:
                picture = LITE.get(screen, screen) if app == "lite" else screen
                shutil.copyfile(screens[picture], folder / f"{kind}-{screen}.png")

    for locale in borrowed():
        source = directory / FALLBACK
        target = directory / locale
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(source, target)

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
        description="Check a run of App Store screenshots, and stage it for deliver."
    )
    parser.add_argument(
        "--languages",
        action="store_true",
        help="print the locales to capture, one per line, and do nothing else",
    )
    parser.add_argument(
        "--screenshots",
        metavar="DIR",
        default=SCREENSHOTS,
        help=f"where the capture run wrote (default {SCREENSHOTS.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--stage",
        metavar="DIR",
        help="also write the deliver screenshot tree into DIR",
    )
    parser.add_argument(
        "--app",
        choices=APPS,
        help="the app whose set --stage writes; the two differ in the edit",
    )
    args = parser.parse_args(argv)

    if args.stage and not args.app:
        parser.error("--stage needs --app, because Pro and Lite show a different edit")

    if args.languages:
        print("\n".join(languages()))
        return 0

    found, problems = collect(args.screenshots)

    if problems:
        return fail(
            "no full set of screenshots to release with:\n  "
            + "\n  ".join(problems)
            + "\nRun `bundle exec fastlane ios screenshots` to take them."
        )

    if args.stage:
        try:
            stage(found, args.stage, args.app)
        except OSError as reason:
            return fail(str(reason))
        print(
            f"staged {args.app}'s {len(SCREENS)} screenshots per device for "
            f"{len(found) + len(borrowed())} locales in {args.stage}"
        )
    else:
        pictures = sum(len(screens) for locale in found.values() for screens in locale.values())
        print(f"{pictures} screenshots in all {len(found)} captured locales: {', '.join(found)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
