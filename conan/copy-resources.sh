#!/bin/sh

set -e
set -u
set -o pipefail

mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

rsync -av "${PROJECT_DIR}/conan-assets/files/" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/"
