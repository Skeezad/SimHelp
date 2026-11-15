# Connection review — 2026-11-15

Scope: static inspection of the Android standalone gateway and the iPhone client.
No phone is attached to ADB. Real pairing, cellular calls, microphone capture,
speaker playback, background delivery and Bluetooth radio behavior are unverified.
Compilation establishes buildability, not successful device audio.

## Reviewed paths

| Stage | iPhone source | Android source | Finding |
| --- | --- | --- | --- |
| Discovery | SamsungPairingClient, VoWLANController | PairingServer, VoWLANGatewayService | Pairing discovery and call gateway advertisement are separate. Discovery absence after pairing is not by itself a pairing failure. |
| Pair authentication | SamsungPairingCrypto, SamsungPairingClient | PairingCrypto, PairingServer | Both use X25519, HKDF-SHA256, AirSIMPair/v1 plus the six-digit code, and AES-GCM. Protocol branding remains AirSIM. |
| Direct route identity | SamsungDirectRouteProof, VoWLANHealthProof | DirectGatewayRoutes, VoWLANControlGateway | Authenticated identity and control/PCM ports are checked separately from storing the pairing key. |
| Local control | WiredHTTPTransport, AirSIMAPI | VoWLANControlGateway, AgentClient | Local Wi-Fi routing; interface fallback is restricted for control requests to avoid replaying dial/SMS operations. |
| Local PCM | PCMRoute, NetworkPCMTransport | VoWLANPCMRelay, PhoneAudioBridge | AIRSIMVWL1 external handshake; AIRSIMPCM1 internal handshake; AIRSIMREADY acknowledgement; 8 kHz mono PCM16LE. Android forwards to loopback/private port 7580. |
| iPhone microphone | AudioSessionController, CallKitController, AppModel | PCM uplink relay | Permission, active call state, CallKit activation and audio-engine startup are independent gates. Pairing success does not pass these gates. |
| iPhone speaker | AudioSessionController | PCM downlink relay | Received PCM is converted to float samples and scheduled on AVAudioPlayerNode. A successful socket handshake does not establish audible playback. |
| Android call audio | n/a | ShizukuBridgeUserService, PhoneAudioBridge | Standalone bridge listens on 127.0.0.1:7580 under Root/Shizuku. Capturing cellular downlink and injecting uplink require working privileged platform audio routes. |
| Early media | AppModel, AudioSessionController | AndroidEarlyMedia, VoWLANPCMRelay | Receive-only audio has a separate lease/handshake and is stopped when the call becomes active before normal two-way startup. |
| Bluetooth | VoBLECentralController, VoBLEPairing, VoBLEMediaTransport | VoBLEGattServer, VoBLESessionAuthenticator, VoBLEProtocol | Matching service/characteristic UUIDs, protocol version 1, encrypted media and 320-byte PCM frames (160 samples). Radio/MTU/reconnect behavior still needs device logs. |
| Cloud | IPhoneCloudCallSession | StandaloneCloudMediaManager | WebSocket relay plus Android loopback PCM bridge. This mode needs internet; local hotspot PCM does not. |
| Routing and call ownership | ConnectionModePreference, AppModel, DeviceCallActionRouter | DirectCallOwnership, RemoteAudioSessionRegistry | Automatic mode can choose local/Bluetooth/cloud. Established-call ownership is tracked separately from the displayed selected device. |
| Disconnect/recovery | NetworkPCMTransport, CallKitController | VoWLANPeerLifecycle, VoWLANGatewayService | Explicit stop closes media; retries keep the authenticated destination. Device validation remains required. |

## Confirmed issue fixed

`NetworkPCMTransport.startAttempt()` always applied `requiredInterfaceType = .wifi`
when `requiresWiFi` was true, even after `retryOrFail()` set `fallbackAttempted`.
Consequently the documented fallback retried the same constrained interface.
The Wi-Fi constraint now applies only before the fallback attempt. Destination,
port, TLS and authentication remain unchanged. This is a recovery fix, not proof
that the reported two-way audio failure is resolved.

## Remaining diagnostic limitation

`StandaloneAgentGateway` returns fixed `route_ready=true` and
`route_listening=true` in its audio config response; its warmup/register endpoints
acknowledge requests without proving actual microphone/telephony audio flow.
`VoWLANGatewayService` also treats already running listeners as ready without
probing an active media session. Readiness UI therefore cannot establish audible
two-way operation. Changing these responses without session evidence could break
existing startup behavior, so they were not changed as part of the UI update.

## Evidence needed for the silent call

Capture the same call's CallKit activation, phone_start, engine_ready,
agent_register/agent_ready, pcm_ready and first_downlink events, plus iPhone
captured buffer counts and both endpoints' uplink/downlink byte counts and peaks.
These distinguish audio-engine startup, authentication/transport failure and
Android telephony audio-routing failures. No root cause for the user's device is
claimed without those logs.

## Presentation update

Retained the native iOS TabView and its system glass/selection behavior. Changed
the five tab symbols to keypad grid, filled clock, message bubble, contact circle
and gear; only the first tab title is now Keypad. Removed the blue ambient page
gradient, call-screen gradients and feature-introduction gradient. System light/
dark page backgrounds remain adaptive; the call and feature-introduction screens
remain black for their white text. Native bar geometry depends on iOS version;
pixel matching to the supplied screenshot has not been verified on a device.
