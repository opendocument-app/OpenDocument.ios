#!/bin/bash

rm -rf build

mkdir build/
cd build/
cmake -G "Xcode" -DCMAKE_TOOLCHAIN_FILE=../OpenDocument.core/lib/ios-cmake/ios.toolchain.cmake ../OpenDocument.core/
cd ../
