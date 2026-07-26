# OpenDocument.ios ![](https://github.com/opendocument-app/OpenDocument.ios/actions/workflows/ios_main.yml/badge.svg)
It's Android's first OpenOffice Document Reader... for iOS!

This is an iOS frontend for our C++ [OpenDocument.core](https://github.com/opendocument-app/OpenDocument.core) library.

## Setup

Our C++ dependencies come from [conan-odr-index](https://github.com/opendocument-app/conan-odr-index),
which is checked out as a submodule and exported into the local conan cache. No
private conan remote is involved.

The helper scripts in that submodule need python 3.12 or newer — they use PEP
701 f-strings, which are a syntax error on 3.11.

1. `git submodule update --init --depth 1 conan-odr-index`
2. `python3.12 -m venv .venv && source .venv/bin/activate`
3. install conan into that venv: `pip install -r conan-odr-index/requirements.txt`
4. `conan profile detect`
5. `conan/setup-all.sh` — exports the recipes and generates the xcconfigs for
   every configuration and architecture. The first run builds odrcore and its
   dependencies from source and takes a while.
6. open `OpenDocumentReader.xcodeproj` in Xcode

Everything else comes from Swift Package Manager and is resolved by Xcode.

`conan/setup-all.sh` has to be re-run whenever the odrcore version in
`conan/conanfile.py` or the `conan-odr-index` submodule changes.
