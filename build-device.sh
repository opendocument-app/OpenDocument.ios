#!/bin/bash

rm -rf build

mkdir build/
cd build/
cmake -G "Xcode" -DCMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake ../
cd ../
