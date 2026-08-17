#!/usr/bin/env bash
#
# Formats every Swift source in this repository with swift-format.
#
#   scripts/format.sh           rewrites the sources in place
#   scripts/format.sh --check   only reports what would change (used by CI)
#
# swift-format comes from the active Xcode toolchain, so the formatter version
# follows the Xcode version CI pins.

set -euo pipefail

cd "$(dirname "$0")/.."

check=false
case "${1:-}" in
    --check) check=true ;;
    "") ;;
    *)
        echo "usage: $0 [--check]" >&2
        exit 2
        ;;
esac

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "swift-format not found in the active Xcode toolchain (needs Xcode 16 or newer)" >&2
    exit 1
fi

# SnapshotHelper.swift is left out: it belongs to fastlane and is kept byte for
# byte as they ship it, so the next version can be copied over it.
#
# The comment stays out here. bash 3.2, which is the one macOS ships and the one
# CI runs, cannot parse an apostrophe in a comment inside a <( ).
files=()
while IFS= read -r -d '' file; do
    # tracked files can be staged for deletion and no longer exist on disk
    if [ -f "$file" ]; then
        files+=("$file")
    fi
done < <(
    git ls-files -z --cached --others --exclude-standard -- \
        '*.swift' ':!:OpenDocumentReaderUITests/SnapshotHelper.swift'
)

if [ ${#files[@]} -eq 0 ]; then
    echo "no Swift sources found" >&2
    exit 1
fi

if [ "$check" = false ]; then
    xcrun swift-format format --in-place --parallel "${files[@]}"
    exit 0
fi

status=0
for file in "${files[@]}"; do
    if ! xcrun swift-format format "$file" \
        | diff -u -L "$file" -L "$file (formatted)" "$file" -; then
        status=1
    fi
done

if [ $status -ne 0 ]; then
    echo >&2
    echo "Swift sources are not formatted. Run scripts/format.sh and commit the result." >&2
fi

exit $status
