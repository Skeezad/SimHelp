#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AIRSIM_ANDROID_MANIFEST="$ROOT/AndroidManifest.xml" \
AIRSIM_ANDROID_OUTPUT_DIR="$ROOT/build/android" \
AIRSIM_ANDROID_OUTPUT_BASENAME="SimHelp-Android-Standalone" \
exec "$ROOT/../phone-control/build.sh"
