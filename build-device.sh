#!/bin/bash

rm -rf build

mkdir build/
cd build/
cmake -G "Xcode" -DCMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake -DIOS_DEPLOYMENT_TARGET=11.0 -DPLATFORM=MAC_CATALYST ../
cd ../
