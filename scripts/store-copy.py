#!/usr/bin/env python3
#
# Writes the store copy of one release: the English "What's New" text, and one
# translation per locale the listing has.
#
#   scripts/store-copy.py 1.41              write whatever is missing
#   scripts/store-copy.py 1.41 --english    rewrite the English too
#   scripts/store-copy.py 1.41 --dry-run    print it, write nothing
#
# One `claude -p` per language rather than one call holding all of them. Each
# agent is given that locale's own description.txt and the notes of the release
# before it, so it reaches for the words the listing already uses in that
# language instead of translating the English afresh every release. They run at
# the same time, and a language that comes back wrong is retried on its own.
#
# A second agent then reads the draft against the English, in the same language,
# and rewrites what reads as English wearing that language's words. `--no-review`
# skips it.
#
# The English is written from the CHANGELOG.md section of that version, or from
# Unreleased while the heading is still open. A file that is already there is
# left alone and translated, since that is the copy that was reviewed.
#
# Nothing here uploads: `scripts/store-notes.py` checks and stages what this
# writes, and the release run uploads it.

import argparse
import concurrent.futures
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(path, name):
    """Import a sibling script, whose file name is not an identifier."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


notes = load(ROOT / "scripts" / "store-notes.py", "store_notes")
changelog = load(ROOT / ".github" / "scripts" / "changelog-section.py", "changelog_section")

SOURCE = "en-US"

# What each locale directory is asking to be written in. A locale with no name
# here is refused rather than guessed at, since the guess would be uploaded.
LANGUAGES = {
    "de-DE": "German",
    "en-US": "English",
    "es-ES": "Spanish, as written in Spain",
    "fr-FR": "French",
    "hi": "Hindi",
    "it": "Italian",
    "pl": "Polish",
    "pt-BR": "Portuguese, as written in Brazil",
    "ru": "Russian",
    "sv": "Swedish",
    "tr": "Turkish",
}

APP = (
    "OpenDocument Reader, an iOS app for reading and editing documents made with "
    "LibreOffice and OpenOffice"
)

ENGLISH_PROMPT = """You are writing the App Store "What's New" text for version {version} of {app}.

Below is the developer-facing changelog of this release, and the text that was written for the release before it.

Write the same release for the people who use the app:
- one line per change, each starting with "- "
- four lines at most; leave out anything nobody would notice from the outside
- plain words. No jargon, no version numbers, no names of internals, nothing that reads like marketing
- say what is different for them, not what was implemented
- no full stop at the end of a line, matching the sample

Reply with those lines and nothing else.

<changelog>
{section}
</changelog>

<previous-release>
{previous}
</previous-release>
"""

TRANSLATION_PROMPT = """You are translating the App Store "What's New" text of {app} into {language}, for its {locale} listing.

The app has said things in {language} before. Its store description is below, and so are the notes of an earlier release where there are any. Use the words they use for the parts of the app - document, page, search, edit, save - rather than translating the English afresh.

- one line out for every line in, in the same order
- keep the leading "- "
- write it as {language} is written, not as English word order carried over. Keep it as short as the English
- leave "OpenDocument Reader" and the format names (ODT, ODS, ODP, PDF) alone

Reply with the translated lines and nothing else.

<english>
{english}
</english>

<store-description>
{description}
</store-description>

<earlier-release>
{previous}
</earlier-release>
"""

REVIEW_PROMPT = """You are a {language} speaker reading the App Store "What's New" text of {app} before it goes out in the {locale} listing. It has been translated from the English below, and you are the last person to see it.

Change a line when it says something the English does not, when it drops something the English says, or when it reads like translated English rather than {language}: a word borrowed as it sounds rather than as it means, English word order carried over, an English word left standing where {language} has an ordinary one of its own, or a word nobody would use for that part of the app. The store description below is how the app already speaks {language}; a line should not contradict it.

This is read by someone using the app, not building it, so a word out of the workshop - engine, render, parser - is wrong even where it is accurate.

Leave alone a line that is already right. A rewrite that is only different is worse than no rewrite.

Reply with the lines as they should go out - the ones you changed and the ones you did not - and nothing else. One line for every line in the English, in the same order, each starting with "- ", no full stop at the end.

<english>
{english}
</english>

<translation>
{draft}
</translation>

<store-description>
{description}
</store-description>
"""


def version_key(name):
    return tuple(int(part) for part in name.split("."))


def previous_copy(locale, version):
    """The newest release before this one that has copy in this locale, or ""."""
    folder = notes.METADATA / locale / "changelogs"
    if not folder.is_dir():
        return ""

    earlier = []
    for path in folder.glob("*.txt"):
        try:
            key = version_key(path.stem)
        except ValueError:
            continue  # README.md and anything else not named after a version
        if key < version_key(version):
            earlier.append((key, path))

    if not earlier:
        return ""
    return max(earlier)[1].read_text(encoding="utf-8").strip()


def ask(prompt, model):
    """One agent, one answer. Raises RuntimeError with what the CLI said."""
    result = subprocess.run(
        [
            "claude",
            "--print",
            "--output-format", "text",
            "--model", model,
            # nothing here needs the repository, and a tool call would only be a
            # way for the answer to arrive as something other than the text
            "--disallowed-tools", "Bash,Edit,Write,Read,Glob,Grep,WebFetch,WebSearch,Task",
            "--strict-mcp-config",
            "--no-session-persistence",
        ],
        input=prompt,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"claude exited {result.returncode}")

    answer = result.stdout.strip()
    if not answer:
        raise RuntimeError("claude answered with nothing")
    return answer


def check(text, against=None):
    """What is wrong with a piece of copy, or None."""
    lines = text.splitlines()
    if not lines:
        return "it is empty"
    if len(text) > notes.LIMIT:
        return f"it is {len(text)} characters, over the store's {notes.LIMIT}"
    if any(not line.startswith("- ") for line in lines):
        return "not every line is a bullet"
    if against is not None and len(lines) != len(against.splitlines()):
        return f"it has {len(lines)} lines against the English text's {len(against.splitlines())}"
    return None


def write(locale, version, text, dry_run):
    path = notes.copy_path(locale, version)
    if dry_run:
        print(f"\n--- {path.relative_to(ROOT)}\n{text}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text + "\n", encoding="utf-8")


def produce(prompt, model, attempts, against=None):
    """Ask until the answer holds up. Raises RuntimeError with the last reason."""
    reason = None
    for attempt in range(attempts):
        try:
            answer = ask(prompt, model)
        except RuntimeError as failure:
            reason = str(failure)
            continue
        reason = check(answer, against=against)
        if reason is None:
            return answer
    raise RuntimeError(reason)


def english(version, model, attempts):
    """The source text: what is on disk, or a fresh one from the changelog."""
    try:
        section = changelog.section((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), version)
        wrote = version
    except ValueError:
        # the heading is still open, which is where a version being cut sits
        section = changelog.section((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), "Unreleased")
        wrote = "Unreleased"
    print(f"writing the English from the {wrote} section of CHANGELOG.md")

    return produce(
        ENGLISH_PROMPT.format(
            version=version, app=APP, section=section, previous=previous_copy(SOURCE, version)
        ),
        model,
        attempts,
    )


def translate(locale, version, source, model, attempts, review=True):
    description = (notes.METADATA / locale / "description.txt").read_text(encoding="utf-8").strip()

    draft = produce(
        TRANSLATION_PROMPT.format(
            app=APP,
            language=LANGUAGES[locale],
            locale=locale,
            english=source,
            description=description,
            previous=previous_copy(locale, version),
        ),
        model,
        attempts,
        against=source,
    )
    if not review:
        return draft

    # A second reader of the same language, because what a first draft gets
    # wrong is not something the draft can see: a word borrowed for its sound
    # rather than its sense reads fine to whoever wrote it.
    return produce(
        REVIEW_PROMPT.format(
            app=APP,
            language=LANGUAGES[locale],
            locale=locale,
            english=source,
            draft=draft,
            description=description,
        ),
        model,
        attempts,
        against=source,
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Write the store copy of one release, one agent per language."
    )
    parser.add_argument("version", help="marketing version, e.g. 1.41")
    parser.add_argument(
        "--english",
        action="store_true",
        help="rewrite the English text even though there is one",
    )
    parser.add_argument(
        "--locales",
        help="only these, comma separated - to redo one language that came out wrong",
    )
    parser.add_argument("--dry-run", action="store_true", help="print the copy, write nothing")
    parser.add_argument("--model", default="opus", help="model the agents run on")
    parser.add_argument("--jobs", type=int, default=5, help="languages translated at once")
    parser.add_argument("--attempts", type=int, default=2, help="tries per language")
    parser.add_argument(
        "--no-review",
        action="store_false",
        dest="review",
        help="take the first draft, without a second reader of that language",
    )
    args = parser.parse_args(argv)

    version = args.version.strip().removeprefix("v")

    try:
        known = notes.locales()
    except (OSError, ValueError) as reason:
        print(reason, file=sys.stderr)
        return 1

    unnamed = [locale for locale in known if locale not in LANGUAGES]
    if unnamed:
        print(
            f"no language written down for {', '.join(unnamed)}: add it to LANGUAGES in "
            f"{Path(__file__).name} rather than let an agent guess",
            file=sys.stderr,
        )
        return 1

    wanted = known
    if args.locales:
        wanted = [locale.strip() for locale in args.locales.split(",") if locale.strip()]
        unknown = [locale for locale in wanted if locale not in known]
        if unknown:
            print(f"no such locale: {', '.join(unknown)}", file=sys.stderr)
            return 1

    source_path = notes.copy_path(SOURCE, version)
    if args.english or not source_path.is_file():
        try:
            source = english(version, args.model, args.attempts)
        except RuntimeError as reason:
            print(f"{SOURCE}: {reason}", file=sys.stderr)
            return 1
        write(SOURCE, version, source, args.dry_run)
    else:
        source = source_path.read_text(encoding="utf-8").strip()
        print(f"translating the {source_path.relative_to(ROOT)} already written")

    targets = [
        locale
        for locale in wanted
        if locale != SOURCE and (args.english or args.locales or not notes.copy_path(locale, version).is_file())
    ]
    if not targets:
        print(f"every locale already has copy for {version}")
        return 0

    print(f"translating into {', '.join(targets)}")

    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        running = {
            pool.submit(
                translate, locale, version, source, args.model, args.attempts, args.review
            ): locale
            for locale in targets
        }
        for done in concurrent.futures.as_completed(running):
            locale = running[done]
            try:
                write(locale, version, done.result(), args.dry_run)
            except (RuntimeError, OSError) as reason:
                failed.append(locale)
                print(f"{locale}: {reason}", file=sys.stderr)
            else:
                print(f"{locale} done")

    if failed:
        print(
            f"\n{len(failed)} came back wrong. Run again with "
            f"--locales {','.join(failed)} to redo only those.",
            file=sys.stderr,
        )
        return 1

    print(f"\nread the diff before committing it - it goes to the store as written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
