#!/usr/bin/env python3
#
# Works out which version a release run builds, and refuses the runs that cannot
# name one:
#
#   a version input   that version
#   no input          only a dry run, on the 0.0.0 in project.pbxproj
#
# It comes from a dispatch input rather than a tag the run was pushed on: a tag
# would be a promise made before the upload, and a version often takes more than
# one build to clear review. The workflow writes the tags afterwards instead.
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
# v is tolerated and stripped below, since the input is typed by hand
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


def resolve(given, dry_run, log=print):
    """The version to build, or "" for none. Raises ValueError with the reason."""
    version = given.strip()

    if not version:
        if not dry_run:
            raise ValueError(
                "nothing to take a version from: fill in the version input, or "
                "tick dry_run to build without uploading."
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
    parser.add_argument("--input", default="", help="version input of the run")
    parser.add_argument(
        "--dry-run",
        default="false",
        help="whether the run publishes nothing; only a dry run may go without a version",
    )
    args = parser.parse_args(argv)

    try:
        version = resolve(args.input, boolean(args.dry_run))
    except ValueError as reason:
        return fail(str(reason))

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as out:
            out.write(f"version={version}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
