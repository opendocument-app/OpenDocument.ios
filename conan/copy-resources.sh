#!/bin/sh
set -e
set -u
set -o pipefail

mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

# copy all resources from "${PROJECT_DIR}/conan-assets" to "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
# but ignore .xcfilelist
rsync -av --exclude='*.xcfilelist' "${PROJECT_DIR}/conan-assets/" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/"
