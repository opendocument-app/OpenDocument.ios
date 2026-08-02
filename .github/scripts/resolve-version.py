#!/usr/bin/env python3
#
# Works out which version a release run builds, and refuses the runs that cannot
# name one:
#
#   tag push                 the tag; a version input has to agree or stay empty
#   dispatched off a branch  the version input, which is how a release whose
#                            upload failed gets finished off its branch
#   neither                  only a dry run, on the 0.0.0 in project.pbxproj
#
# The shape is checked here because xcodebuild never checks it: MARKETING_VERSION
# is a free-form string to the build, so a typo would only surface when App Store
# Connect rejects the upload at the very end. Whether the version is above what
# is live is left to the store, which is the only thing that knows.
#
# Prints the resolved version and writes it to GITHUB_OUTPUT as `version`, empty
# when there is none. Run it by hand to see what a dispatch would build.

import argparse
import os
import re
import sys

# what CFBundleShortVersionString accepts: one to three numeric parts. A leading
# v is allowed because tags are often written that way, and stripped below
VERSION = re.compile(r"^v?[0-9]{1,3}(\.[0-9]{1,3}){0,2}$")


def fail(message):
    if os.environ.get("GITHUB_ACTIONS"):
        # also surfaces as an annotation on the run, not only inside the step log
        print(f"::error::{message}")
    else:
        print(message, file=sys.stderr)
    return 1


def boolean(value):
    """A workflow input as it reaches a shell: the string "true" or "false"."""
    if value.strip().lower() in ("true", "1"):
        return True
    if value.strip().lower() in ("false", "0", ""):
        return False
    raise ValueError(f"'{value}' is not true or false")


def resolve(tag, given, dry_run, log=print):
    """The version to build, or "" for none. Raises ValueError with the reason."""
    tag, given = tag.strip(), given.strip()

    if tag and given and given.removeprefix("v") != tag.removeprefix("v"):
        raise ValueError(
            f"the version input ({given}) is not the tag this ran on ({tag}). "
            "leave it blank to build the tag."
        )

    version = tag or given
    if not version:
        if not dry_run:
            raise ValueError(
                "nothing to take a version from. push this as a tag, dispatch it "
                "on one, or fill in the version input."
            )
        log("no version given - building the 0.0.0 in project.pbxproj")
        return ""

    if not VERSION.match(version):
        raise ValueError(
            f"'{version}' is not a version: expected up to three numbers, like 1.36 or 1.36.1"
        )
    version = version.removeprefix("v")
    log(f"building {version}")
    return version


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Resolve the version a release run builds."
    )
    parser.add_argument("--tag", default="", help="tag the run was triggered by, if any")
    parser.add_argument("--input", default="", help="version input of a dispatched run")
    parser.add_argument(
        "--dry-run",
        default="false",
        help="whether the run publishes nothing; only a dry run may go without a version",
    )
    args = parser.parse_args(argv)

    try:
        version = resolve(args.tag, args.input, boolean(args.dry_run))
    except ValueError as reason:
        return fail(str(reason))

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as out:
            out.write(f"version={version}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
