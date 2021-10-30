#!/bin/bash

# https://stackoverflow.com/a/246128/198996
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

rm -rf build

mkdir build/
cd build/
cmake -G "Xcode" -DCMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake -DIOS_DEPLOYMENT_TARGET=14.0 -DPLATFORM=OS64COMBINED ../
cd ../
