#!/bin/bash

# https://stackoverflow.com/a/246128/198996
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

conan install conan/ \
    --output-folder=conan-output \
    --build=missing \
    --profile:host=conan/profiles/ios-simulator \
    -s build_type=Release \
    -s "&:build_type=RelWithDebInfo" \
    -s "odrcore/*:build_type=RelWithDebInfo"
