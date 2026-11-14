#!/usr/bin/env python3
"""Generate reproducible localized samples for Debug screenshot builds.

The documents come from `sampledoc` (https://github.com/opendocument-app/sampledoc),
shared with the Android app and pinned in scripts/requirements.txt. This script
picks the languages from store_screenshots.LOCALES and writes them, with
screenshot-names.json, to OpenDocumentReader/Samples.

Usage:
    python3 -m pip install -r scripts/requirements.txt
    python3 scripts/make-screenshot-documents.py [--language en]
"""

import argparse
import json
import re
from pathlib import Path

import store_screenshots as store

SAMPLES = Path(__file__).resolve().parent.parent / "OpenDocumentReader" / "Samples"
REQUIREMENTS = Path(__file__).resolve().with_name("requirements.txt")


def pinned() -> str:
    """Return the sampledoc version requirements.txt pins."""
    for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines():
        found = re.fullmatch(r"sampledoc==(\S+)", line.strip())
        if found:
            return found.group(1)

    raise SystemExit(f"{REQUIREMENTS.name} pins no sampledoc==<version>")


def main(argv=None) -> None:
    # Only the languages the store is photographed in; locales mapped to None borrow English.
    spoken = sorted({language for language in store.LOCALES.values() if language})

    parser = argparse.ArgumentParser(description="Write the documents the store screenshots open.")
    parser.add_argument(
        "--language", action="append", choices=spoken,
        help="only this language, repeatable; default is all of them.")
    args = parser.parse_args(argv)

    wanted = pinned()
    try:
        import sampledoc
    except ImportError:
        raise SystemExit(
            f"sampledoc is not installed - python3 -m pip install -r scripts/{REQUIREMENTS.name}"
        ) from None

    # Another version writes other documents, so the screenshots would depend on who took them.
    if sampledoc.__version__ != wanted:
        raise SystemExit(
            f"sampledoc {sampledoc.__version__} is installed but {wanted} is pinned - "
            f"python3 -m pip install -r scripts/{REQUIREMENTS.name}"
        )

    missing = sorted(set(spoken) - set(sampledoc.languages()))
    if missing:
        raise SystemExit(f"store_screenshots.py photographs languages sampledoc lacks: {missing}")

    written = sampledoc.generate(SAMPLES, languages=args.language or spoken)

    details = sampledoc.manifest(store.LOCALES)
    details["languages"] = {language: details["languages"][language] for language in spoken}
    (SAMPLES / "screenshot-names.json").write_text(
        json.dumps(details, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8"
    )

    print(f"wrote {len(written)} documents in {len(args.language or spoken)} languages to {SAMPLES}")


if __name__ == "__main__":
    main()
