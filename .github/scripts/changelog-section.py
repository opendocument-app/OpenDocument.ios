#!/usr/bin/env python3
#
# Prints the CHANGELOG.md section for one version, and fails when there is none.
#
# The release run reads it before building, so a version without release copy
# fails in seconds rather than once both apps are uploaded, and again when it
# drafts the github release, whose body the section becomes.

import argparse
import re
import sys

# `## [1.37] - 2026-08-02`, `## [1.38]`, `## Unreleased`. Whatever follows the
# version is not looked at, so an unusual date separator still closes the
# section above it. Not `###`, which belongs to whichever section it sits in
HEADING = re.compile(r"^## +\[?([^\]\s]+)")

# `[1.37]: https://github.com/...compare/1.36...1.37` at the foot of the file:
# inside the last section, but not release copy
LINK = re.compile(r"^\[[^\]]+\]: +\S+\s*$")


def section(text, version):
    """The body under `## [<version>]`. Raises ValueError if missing or empty."""
    wanted = version.strip().removeprefix("v")

    found = False
    body = []
    for line in text.splitlines():
        heading = HEADING.match(line)
        if heading:
            if found:
                break
            found = heading.group(1).removeprefix("v") == wanted
        elif found and not LINK.match(line):
            body.append(line)

    if not found:
        raise ValueError(
            f"CHANGELOG.md has no '## [{wanted}]' section. Cut the Unreleased heading "
            f"to '## [{wanted}]' before releasing it - that copy is the release body."
        )

    body = "\n".join(body).strip()
    if not body:
        raise ValueError(
            f"the '## [{wanted}]' section of CHANGELOG.md is empty. A release with "
            "nothing user facing in it should say so rather than say nothing."
        )
    return body


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Print the CHANGELOG.md section of one version."
    )
    parser.add_argument("--version", required=True, help="version to look up, e.g. 1.38")
    parser.add_argument("--file", default="CHANGELOG.md", help="changelog to read")
    args = parser.parse_args(argv)

    try:
        with open(args.file, encoding="utf-8") as changelog:
            body = section(changelog.read(), args.version)
    except (OSError, ValueError) as reason:
        # stderr rather than a ::error:: annotation, which the runner only reads
        # off stdout - and both callers redirect stdout
        print(reason, file=sys.stderr)
        return 1

    sys.stdout.reconfigure(encoding="utf-8")
    print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
