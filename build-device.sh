#!/bin/bash

# https://stackoverflow.com/a/246128/198996
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

CONAN_REVISIONS_ENABLED=1 conan install . --profile ios --build missing
