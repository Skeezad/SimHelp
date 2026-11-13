#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$ROOT/build/jvm-test"
JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}
JAVAC="$JAVA_HOME/bin/javac"
JAVA="$JAVA_HOME/bin/java"
CRYPTO_JAR=$(sh "$ROOT/crypto-dependency.sh")

assert_contains() {
  file=$1
  expected=$2
  message=$3
  if ! grep -Fq "$expected" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_not_contains() {
  file=$1
  unexpected=$2
  message=$3
  if grep -Fq "$unexpected" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_contains "$ROOT/src/com/simhelp/phonecontrol/PairingServer.java" \
  'pairing_direct_gateway_unavailable state=' \
  'manual pairing must diagnose missing live control/PCM listeners'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/PairingServer.java" \
  'listener.onFailed("密钥已保存，但直连网关未就绪，尚未完成手动配对。"' \
  'missing direct gateway must not report complete pairing success on Android'

assert_contains "$ROOT/AndroidManifest.xml" \
  'android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING' \
  'boot-safe watchdog permission is missing'
assert_contains "$ROOT/AndroidManifest.xml" \
  'android:foregroundServiceType="remoteMessaging"' \
  'boot-safe foreground service type is missing'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING' \
  'watchdog still requests a boot-blocked foreground service type'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/VoWLANGatewayService.java" \
  'ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING' \
  'VoWLAN gateway still requests a boot-blocked foreground service type'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'setPendingIntentCreatorBackgroundActivityStartMode' \
  'Terminal recovery does not grant creator-side background launch privileges'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'setPendingIntentBackgroundActivityStartMode' \
  'Terminal recovery does not grant sender-side background launch privileges'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'PendingIntent.getActivity' \
  'Terminal recovery still bypasses the supported PendingIntent launch path'
assert_not_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'startActivity(terminal)' \
  'Terminal recovery still uses a background activity start that Android blocks'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'String payload = new AgentClient(this).nextCommand();' \
  'watchdog does not refresh the AVF Agent endpoint for each reconnect'
assert_not_contains "$ROOT/src/com/simhelp/phonecontrol/AgentWatchdogService.java" \
  'AgentClient client = new AgentClient(this);' \
  'watchdog still caches a pre-boot AVF endpoint for its entire lifetime'
assert_contains "$ROOT/AndroidManifest.xml" \
  'android:name=".BridgeApplication"' \
  'persistent diagnostics are not initialized at process start'
assert_contains "$ROOT/AndroidManifest.xml" 'android.permission.RECEIVE_SMS' \
  'incoming SMS permission is missing'
assert_contains "$ROOT/AndroidManifest.xml" 'android.permission.READ_SMS' \
  'optional inbox fallback permission is missing'
assert_contains "$ROOT/AndroidManifest.xml" 'android:name=".IncomingSMSReceiver"' \
  'carrier SMS receiver is missing'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/StandaloneAgentGateway.java" \
  'smsStore.localMessages().toString()' 'standalone SMS inbox is not exposed to iPhone'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentClient.java" \
  'http_request_started' \
  'Agent HTTP connection attempts are missing from debug diagnostics'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/AgentClient.java" \
  'http_request_finished' \
  'Agent HTTP response status and timing are missing from debug diagnostics'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/MainActivity.java" \
  'Debug 日志' \
  'the Android app has no user-visible debug log controls'
assert_contains "$ROOT/src/com/simhelp/phonecontrol/MainActivity.java" \
  'BridgeLog.clear()' \
  'the Android app cannot clear captured diagnostics'

rm -rf "$OUT"
mkdir -p "$OUT"
"$JAVAC" --release 17 -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/FeedbackUploadPolicy.java \
  "$ROOT"/test/com/simhelp/phonecontrol/FeedbackUploadPolicyTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.FeedbackUploadPolicyTests
assert_contains "$ROOT/src/com/simhelp/phonecontrol/FeedbackUploader.java" \
  '!FeedbackUploadPolicy.allows(trigger)' 'feedback upload must gate collection and network access'
"$JAVAC" --release 17 -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/AppUpdatePolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AppUpdateSession.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AppUpdatePolicyTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AppUpdateSessionTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.AppUpdatePolicyTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.AppUpdateSessionTests
"$JAVAC" --release 17 -cp "$CRYPTO_JAR" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayHTTPException.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CloudCallTarget.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayCommandRetryState.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayCommandConfiguration.java \
  "$ROOT"/src/com/simhelp/phonecontrol/StandaloneWebSocket.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayEgressGate.java \
  "$ROOT"/test/android/util/Base64.java \
  "$ROOT"/test/com/simhelp/phonecontrol/StandaloneCommandLifecycleTests.java \
  "$ROOT"/src/com/simhelp/phonecontrol/WebSocketPeerClose.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CommandPollingPolicy.java \
  "$ROOT"/test/com/simhelp/phonecontrol/RelayCommandRetryTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/WebSocketPeerCloseTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.RelayCommandRetryTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.WebSocketPeerCloseTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.StandaloneCommandLifecycleTests
"$JAVAC" --release 17 -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayHTTPException.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayRegistrationRecovery.java \
  "$ROOT"/test/com/simhelp/phonecontrol/RelayRegistrationRecoveryTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.RelayRegistrationRecoveryTests
"$JAVAC" --release 17 -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayHTTPException.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CloudCallRetryPolicy.java \
  "$ROOT"/test/com/simhelp/phonecontrol/CloudCallRetryPolicyTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.CloudCallRetryPolicyTests
"$JAVAC" --release 17 -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayHTTPException.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayCommandRetryState.java \
  "$ROOT"/src/com/simhelp/phonecontrol/WebSocketPeerClose.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CloudSMSUploader.java \
  "$ROOT"/test/com/simhelp/phonecontrol/CloudSMSUploaderTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.CloudSMSUploaderTests
"$JAVAC" --release 17 -cp "$CRYPTO_JAR" -d "$OUT" \
  "$ROOT"/test/android/Manifest.java \
  "$ROOT"/test/android/provider/Settings.java \
  "$ROOT"/test/android/content/SharedPreferences.java \
  "$ROOT"/test/android/content/ComponentName.java \
  "$ROOT"/test/android/content/Intent.java \
  "$ROOT"/test/android/content/IntentFilter.java \
  "$ROOT"/test/android/os/BatteryManager.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AndroidBatteryStatus.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AndroidBatteryStatusTests.java \
  "$ROOT"/test/android/content/pm/PackageManager.java \
  "$ROOT"/test/android/content/pm/PackageInfo.java \
  "$ROOT"/test/android/os/Bundle.java \
  "$ROOT"/test/android/os/Build.java \
  "$ROOT"/test/android/telecom/PhoneAccount.java \
  "$ROOT"/test/android/telecom/PhoneAccountHandle.java \
  "$ROOT"/test/android/telephony/TelephonyManager.java \
  "$ROOT"/test/android/telephony/PhoneNumberUtils.java \
  "$ROOT"/test/android/telephony/SubscriptionManager.java \
  "$ROOT"/test/android/telephony/SubscriptionInfo.java \
  "$ROOT"/test/android/content/Context.java \
  "$ROOT"/test/android/net/Uri.java \
  "$ROOT"/test/android/os/Looper.java \
  "$ROOT"/test/android/os/Handler.java \
  "$ROOT"/test/android/telecom/Call.java \
  "$ROOT"/test/android/telecom/DisconnectCause.java \
  "$ROOT"/test/android/telecom/TelecomManager.java \
  "$ROOT"/test/android/telecom/VideoProfile.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AppConfig.java \
  "$ROOT"/test/com/simhelp/phonecontrol/BridgeLog.java \
	"$ROOT"/test/com/simhelp/phonecontrol/RuntimeMode.java \
	"$ROOT"/test/com/simhelp/phonecontrol/StandaloneAgentGateway.java \
  "$ROOT"/test/org/json/JSONObject.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PureLocalModeCoordinator.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PureLocalModeProof.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PureLocalModeWire.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SIMSlotObserver.java \
  "$ROOT"/test/com/simhelp/phonecontrol/SIMSlotObserverTests.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AgentClient.java \
  "$ROOT"/src/com/simhelp/phonecontrol/InstallerClient.java \
  "$ROOT"/src/com/simhelp/phonecontrol/ReleaseAssetSelector.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AVFStartupPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/RuntimePermissionPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/SMSDeliveryIdentity.java \
	"$ROOT"/src/com/simhelp/phonecontrol/SMSRecentDeliveryIDs.java \
	"$ROOT"/src/com/simhelp/phonecontrol/SMSInboxCursor.java \
  "$ROOT"/src/com/simhelp/phonecontrol/TelecomStateMapper.java \
	"$ROOT"/src/com/simhelp/phonecontrol/TelecomRolePolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/DialerRoleSetupPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/ShizukuStartupPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/TelecomInvocation.java \
	"$ROOT"/src/com/simhelp/phonecontrol/PrivilegedBridgeProtocol.java \
	"$ROOT"/src/com/simhelp/phonecontrol/PrivilegedBridgeCoordinator.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AudioWatchdogSnapshot.java \
  "$ROOT"/src/com/simhelp/phonecontrol/PCMHealthEvidence.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AgentAudioCompatibility.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AudioHealthReportCache.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RootHelperIdentity.java \
  "$ROOT"/src/com/simhelp/phonecontrol/PrivilegeChannelGate.java \
  "$ROOT"/src/com/simhelp/phonecontrol/EarlyMediaLeases.java \
  "$ROOT"/test/com/simhelp/phonecontrol/EarlyMediaLeaseTests.java \
  "$ROOT"/src/com/simhelp/phonecontrol/ServiceBindAttempt.java \
  "$ROOT"/test/com/simhelp/phonecontrol/ServiceBindAttemptTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/RootHelperLifecycleTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AgentAudioCompatibilityTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PCMHealthEvidenceTests.java \
	"$ROOT"/src/com/simhelp/phonecontrol/PhoneAudioBridgeProcessPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/WireJson.java \
  "$ROOT"/src/com/simhelp/phonecontrol/DebugRedactor.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CrashReportFormatter.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AppInformation.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CrashReportStore.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CrashReportSharePayload.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AgentCommand.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CallRepository.java \
  "$ROOT"/src/com/simhelp/phonecontrol/DefaultCallAccount.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CloudCallTarget.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AgentCommandDispatcher.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SMSPayloadPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SMSConfirmation.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RetryPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayHTTPException.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RelayRetryPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CommandPollingPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RecoveryPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/RecoveryLaunchPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CallEventDeduplicator.java \
  "$ROOT"/src/com/simhelp/phonecontrol/PairingCrypto.java \
  "$ROOT"/src/com/simhelp/phonecontrol/PairingSession.java \
	"$ROOT"/src/com/simhelp/phonecontrol/AVFNetworkPolicy.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANAuth.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANControlPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/VoWLANAcceptLoop.java \
	"$ROOT"/src/com/simhelp/phonecontrol/VoWLANPeerLifecycle.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANReplayCache.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANPCMProtocol.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANPortBinder.java \
	"$ROOT"/src/com/simhelp/phonecontrol/PrivateNetworkPolicy.java \
	"$ROOT"/src/com/simhelp/phonecontrol/VoWLANNetworkPolicy.java \
    "$ROOT"/src/com/simhelp/phonecontrol/DirectGatewayRoutes.java \
    "$ROOT"/src/com/simhelp/phonecontrol/DirectCallOwnership.java \
    "$ROOT"/test/com/simhelp/phonecontrol/RemoteCallHangupGuard.java \
    "$ROOT"/src/com/simhelp/phonecontrol/RemoteCallAudioScope.java \
	"$ROOT"/src/com/simhelp/phonecontrol/StandaloneLongPoll.java \
	"$ROOT"/src/com/simhelp/phonecontrol/MainScreenPresentation.java \
	"$ROOT"/src/com/simhelp/phonecontrol/LiveStatusPoller.java \
	"$ROOT"/src/com/simhelp/phonecontrol/PCMBridgeStatus.java \
	"$ROOT"/src/com/simhelp/phonecontrol/MuteRequestRetrier.java \
	"$ROOT"/src/com/simhelp/phonecontrol/NotificationUpdateGate.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEProtocol.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEAudioQueue.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEPairingManager.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLECredentialStore.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEReplayWindow.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEControlChannel.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLECallController.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEPCMBackendResolver.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEDiagnostics.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEPCMBridgeSession.java \
	"$ROOT"/src/com/simhelp/phonecontrol/voble/VoBLEMediaSession.java \
	"$ROOT"/test/com/simhelp/phonecontrol/CoreTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PairingPeerPolicyTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/HealthIdentityProofTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PairingCryptoCompatibilityTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/NotificationUpdateGateTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/CallRepositoryTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/DefaultCallAccountTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/ShizukuStartupPolicyTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/PrivateNetworkPolicyTests.java
"$JAVAC" --release 17 -cp "$OUT" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/AndroidAgentIdentity.java \
  "$ROOT"/test/com/simhelp/phonecontrol/AndroidAgentIdentityTests.java
sh "$ROOT/verify-io-api.sh" "$OUT"
"$JAVA" -cp "$OUT:$CRYPTO_JAR" com.simhelp.phonecontrol.CoreTests
"$JAVA" -cp "$OUT:$CRYPTO_JAR" com.simhelp.phonecontrol.SIMSlotObserverTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.PairingPeerPolicyTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.PrivateNetworkPolicyTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.HealthIdentityProofTests
"$JAVA" -cp "$OUT:$CRYPTO_JAR" com.simhelp.phonecontrol.PairingCryptoCompatibilityTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.PCMHealthEvidenceTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.AgentAudioCompatibilityTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.RootHelperLifecycleTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.ServiceBindAttemptTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.EarlyMediaLeaseTests
sh "$ROOT/test-voble-gatt.sh"
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.NotificationUpdateGateTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.CallRepositoryTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.DefaultCallAccountTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.AndroidAgentIdentityTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.AndroidBatteryStatusTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.ShizukuStartupPolicyTests

# Keep the real diagnostics class ahead of the unrelated suite's BridgeLog test double.
DIAGNOSTICS_OUT="$OUT/diagnostics"
mkdir -p "$DIAGNOSTICS_OUT"
"$JAVAC" --release 17 -cp "$OUT" -d "$DIAGNOSTICS_OUT" \
  "$ROOT"/test/android/util/Log.java \
  "$ROOT"/src/com/simhelp/phonecontrol/BridgeLog.java \
  "$ROOT"/test/com/simhelp/phonecontrol/DiagnosticFileTests.java
sh "$ROOT/verify-io-api.sh" "$DIAGNOSTICS_OUT"
"$JAVA" -cp "$DIAGNOSTICS_OUT:$OUT" com.simhelp.phonecontrol.DiagnosticFileTests

"$JAVAC" --release 17 -cp "$OUT" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/LocalOutputMuteController.java \
  "$ROOT"/src/com/simhelp/phonecontrol/CallOutputPolicyMute.java \
  "$ROOT"/src/com/simhelp/phonecontrol/BoundedAudioOperation.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SystemCallOutputPolicy.java \
  "$ROOT"/test/com/simhelp/phonecontrol/CallOutputPolicyMuteTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/LocalOutputMuteControllerTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.LocalOutputMuteControllerTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.CallOutputPolicyMuteTests

"$JAVAC" --release 17 -cp "$OUT" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/AudioWatchdogSnapshot.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RemoteAudioWatchdog.java \
  "$ROOT"/src/com/simhelp/phonecontrol/RemoteCallAudioScope.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AudioWatchdogReport.java \
  "$ROOT"/src/com/simhelp/phonecontrol/BoundedAudioOperation.java \
  "$ROOT"/test/com/simhelp/phonecontrol/BoundedAudioOperationTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/RemoteAudioWatchdogTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.RemoteAudioWatchdogTests
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.BoundedAudioOperationTests

"$JAVAC" --release 17 -cp "$OUT" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANNetworkRecoveryGate.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANAdvertisementEpoch.java \
  "$ROOT"/test/com/simhelp/phonecontrol/VoWLANNetworkRecoveryTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.VoWLANNetworkRecoveryTests

# Compile the actual executor against Android; replace only the telephony boundary at runtime.
ANDROID_JAR="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}/platforms/android-35/android.jar"
SMS_OUT="$OUT/sms-compat"
mkdir -p "$SMS_OUT"
"$JAVAC" --release 17 -cp "$ANDROID_JAR:$DIAGNOSTICS_OUT:$OUT" -d "$SMS_OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/SMSResultCode.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SmsSendConfirmationGate.java \
  "$ROOT"/src/com/simhelp/phonecontrol/SMSCommandExecutor.java \
  "$ROOT"/test/com/simhelp/phonecontrol/FeedbackUploader.java
"$JAVAC" --release 17 -cp "$SMS_OUT:$OUT:$ANDROID_JAR" -d "$SMS_OUT" \
  "$ROOT"/test/compat/android/telephony/SmsManager.java \
  "$ROOT"/test/com/simhelp/phonecontrol/SMSCompatibilityTests.java
"$JAVA" -cp "$SMS_OUT:$OUT:$ANDROID_JAR" com.simhelp.phonecontrol.SMSCompatibilityTests

"$JAVAC" --release 17 -cp "$OUT" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/CloudPCMAudioQueue.java \
  "$ROOT"/test/com/simhelp/phonecontrol/CloudPCMAudioQueueTests.java
"$JAVA" -cp "$OUT" com.simhelp.phonecontrol.CloudPCMAudioQueueTests

"$JAVAC" --release 17 -cp "$DIAGNOSTICS_OUT:$OUT" -d "$OUT" \
  "$ROOT"/src/com/simhelp/phonecontrol/CloudPCMMediaPump.java \
  "$ROOT"/test/com/simhelp/phonecontrol/CloudPCMMediaPumpTests.java
"$JAVA" -cp "$DIAGNOSTICS_OUT:$OUT" com.simhelp.phonecontrol.CloudPCMMediaPumpTests

PCM_OUT="$OUT/direct-pcm"
mkdir -p "$PCM_OUT"
"$JAVAC" --release 17 -cp "$OUT:$ANDROID_JAR" -d "$PCM_OUT" \
  "$ROOT"/test/pcm/com/simhelp/phonecontrol/VoWLANPairingStore.java \
  "$ROOT"/test/pcm/com/simhelp/phonecontrol/RemoteAudioSessionRegistry.java \
  "$ROOT"/src/com/simhelp/phonecontrol/AndroidEarlyMedia.java \
  "$ROOT"/src/com/simhelp/phonecontrol/VoWLANPCMRelay.java \
  "$ROOT"/test/com/simhelp/phonecontrol/DirectPCMIntegrationTests.java \
  "$ROOT"/test/com/simhelp/phonecontrol/EarlyMediaRelayIntegrationTests.java
"$JAVA" -cp "$PCM_OUT:$OUT:$ANDROID_JAR" com.simhelp.phonecontrol.DirectPCMIntegrationTests
"$JAVA" -cp "$PCM_OUT:$OUT:$ANDROID_JAR" com.simhelp.phonecontrol.EarlyMediaRelayIntegrationTests

sh "$ROOT/test-audio-policy.sh"

sh "$ROOT/test-privileged-sms.sh"
