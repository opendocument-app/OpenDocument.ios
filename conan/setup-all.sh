#!/usr/bin/env bash

set -euo pipefail

# https://stackoverflow.com/a/246128/198996
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

CONFIGURATIONS=("Debug" "Debug Lite" "Release" "Release Lite")

if [ ! -f conan-odr-index/scripts/conan_export_all_packages.py ]; then
  echo "conan-odr-index submodule is missing. Run:" >&2
  echo "  git submodule update --init --depth 1 conan-odr-index" >&2
  exit 1
fi

# our recipes live in the conan-odr-index submodule and get exported into the
# local cache, so no private remote is involved
python3 conan-odr-index/scripts/conan_export_all_packages.py

# XcodeDeps appends to the per-package include lists rather than rewriting them,
# so leftovers from earlier runs keep shadowing freshly generated files
rm -rf conan-output conan-assets

install() {
  local profile="$1"
  local configuration="$2"
  shift 2

  conan install conan/ \
    --output-folder=conan-output \
    --build=missing \
    --profile:host="conan/profiles/${profile}" \
    -o "configuration=${configuration}" \
    "$@"
}

# assets, deployed into the app bundle as odrcore's runtime data
install ios "Release" \
  --deployer=conan/conandeployer.py \
  --deployer-folder=conan-assets

# device
for configuration in "${CONFIGURATIONS[@]}"; do
  install ios "${configuration}"
done

# simulator
for arch in "arm64" "x64"; do
  for configuration in "${CONFIGURATIONS[@]}"; do
    install "ios-simulator-${arch}" "${configuration}"
  done
done
