#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BASE="$ROOT/build/jvm-test"
OUT="$BASE/audio-policy"
TASK_JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}
SDK=${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}
ANDROID_JAR="$SDK/platforms/android-35/android.jar"
mkdir -p "$OUT"
"$TASK_JAVA_HOME/bin/javac" --release 17 -cp "$BASE:$ANDROID_JAR" -d "$OUT" \
  "$ROOT"/test/android/telecom/Call.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AppConfig.java \
  "$ROOT"/test/audio-policy/android/os/Handler.java \
  "$ROOT"/test/audio-policy/android/telecom/InCallService.java \
  "$ROOT"/test/audio-policy/com/simhelp/phonecontrol/*.java \
  "$ROOT"/test/audio-policy/com/simhelp/phonecontrol/voble/VoBLEGatewayService.java \
  "$ROOT"/src/com/simhelp/phonecontrol/TelecomStateMapper.java \
  "$ROOT"/src/com/simhelp/phonecontrol/LocalOutputMuteController.java \
  "$ROOT"/src/com/simhelp/phonecontrol/LocalCallAudioController.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RemoteAudioSessionRegistry.java \
  "$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEMediaSession.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SimHelpInCallService.java \
  "$ROOT"/test/com/simhelp/phonecontrol/RemoteCallMuteLifecycleTests.java
"$TASK_JAVA_HOME/bin/java" -cp "$OUT:$BASE:$ANDROID_JAR" com.simhelp.phonecontrol.RemoteCallMuteLifecycleTests
