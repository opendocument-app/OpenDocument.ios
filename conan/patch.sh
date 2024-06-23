#!/usr/bin/env bash

set -e

echo "patch conan generated xcconfig files"

# patch xcconfig - see https://github.com/conan-io/conan/issues/16526
sed -i '' -E 's/\]\[arch=arm64\]\[/][/g;t' conan-output/*.xcconfig

echo "done"
