#!/bin/sh
set -eu

# Never turn a development experiment into a shipping model by copying the
# normal resource directory. Explicit build opt-in and Debug are both required.
comparison_destination="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/PersonalMLComparison"
if [ "${ICHART_INCLUDE_PERSONAL_ML_COMPARISON:-NO}" != YES ]; then
    if [ -e "$comparison_destination" ]; then
        echo 'error: Stale personal comparison resources. Use a fresh build directory.' >&2
        exit 1
    fi
    exit 0
fi
if [ "${CONFIGURATION:?}" != Debug ]; then
    echo 'error: Personal ML comparison resources are Debug-only.' >&2
    exit 1
fi
comparison_source="${ICHART_PERSONAL_ML_ARTIFACT_DIR:?Set the verified comparison package directory}"
if [ ! -f "$comparison_source/manifest.json" ] || [ ! -d "$comparison_source/PersonalVisualEncoderResearch.mlpackage" ]; then
    echo 'error: The verified personal comparison package is missing.' >&2
    exit 1
fi
mkdir -p "$comparison_destination"
/usr/bin/ditto "$comparison_source/PersonalVisualEncoderResearch.mlpackage" "$comparison_destination/PersonalVisualEncoderResearch.mlpackage"
/bin/cp "$comparison_source/manifest.json" "$comparison_destination/manifest.json"
if [ -f "$comparison_source/public-anchors.json" ]; then
    /bin/cp "$comparison_source/public-anchors.json" "$comparison_destination/public-anchors.json"
elif [ -e "$comparison_destination/public-anchors.json" ]; then
    echo 'error: Stale public anchors. Use a fresh build directory for the legacy package.' >&2
    exit 1
fi
