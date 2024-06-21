#!/bin/bash

# https://stackoverflow.com/a/246128/198996
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

for configuration in "Debug" "Debug Lite" "Release" "Release Lite"; do
  conan install conan/ \
    --output-folder=conan-output \
    --build=missing \
    --profile:host=conan/profiles/ios \
    -s build_type=Release \
    -s "&:build_type=Release" \
    -s "odrcore/*:build_type=RelWithDebInfo" \
    -o "configuration=${configuration}"
done
