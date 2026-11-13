#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/airsim-ios-update-tests.XXXXXX)
xcrun swiftc "$ROOT/SimHelp/AppReleasePolicy.swift" "$ROOT/SimHelp/AppUpdateController.swift" "$ROOT/UpdatePolicySmoke/main.swift" -o "$OUT/tests"
"$OUT/tests"
