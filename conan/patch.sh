#!/usr/bin/env bash

set -e

echo "patch conan generated xcconfig files"

# patch xcconfig - see https://github.com/conan-io/conan/issues/16526
sed -i '' -E 's/(.*)_[a-zA-Z]+_[a-zA-Z]+(\[.*\]) = (.*)$/\1\2 = \$(inherited) \3/g;t' conan-output/*.xcconfig

echo "done"
