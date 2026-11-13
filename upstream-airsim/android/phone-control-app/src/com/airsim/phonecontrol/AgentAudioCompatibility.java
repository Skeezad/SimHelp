package com.airsim.phonecontrol;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Presentation policy for bounded privileged evidence. No audio, network or device actions. */
final class AgentAudioCompatibility {
    enum Level { PENDING, ATTENTION, INCOMPATIBLE, OBSERVED }
    record Result(Level level, String title, List<String> points) {
        String details() { return "• " + String.join("\n• ", points); }
    }

    static Result evaluate(String report, boolean carrierActive) {
        Map<String, String> fields = parse(report);
        List<String> points = new ArrayList<>();
        if ("timeout".equals(fields.get("privileged_startup"))) {
            return result(Level.ATTENTION, "Shizuku user service has not been started · Audio detection has not been entered yet",
                "Having the Shizuku master service online does not mean that SimHelp's privileged service has been started; there is currently no service connection available to authenticate bidirectional PCM.",
                "true".equals(fields.get("shizuku_mtk_startup_risk"))
                    ? "Detected MediaTek platform and Shizuku 13.6.0: There is an application context initialization failure issue in upstream. You can use an authorized Root channel, or switch to an officially compatible version and re-authorize it."
                    : "Please check the Shizuku authorization and user service startup logs; you can retry manually or use an authorized Root channel.",
                "Boot timeout does not equal audio hardware incompatibility. After the service is started, the downlink collection and uplink injection of calls need to be verified separately.");
        }
        if (fields.isEmpty()) return result(Level.PENDING, "Waiting for audio bridge detection",
            "Please confirm that Shizuku/Root is running and authorize SimHelp, and wait for the user service to return to the latest status.",
            "Failure to obtain test data does not mean that the device is incompatible. The fact that the Agent is online does not mean that the two-way conversation is normal.");
        String tx = fields.getOrDefault("pcm_cap_tx", "unknown");
        if ("ok".equals(fields.get("pcm_cap_query")) && "missing".equals(tx)) {
            return result(Level.INCOMPATIBLE, "The current device is not compatible with SimHelp · Adaptation is required",
                "To be adapted: call audio uplink injection. Privileged query found no Telephony Tx and no Samsung VOICE_TX interface.",
                "Pairing and SMS are not subject to this detection; a working call sending backend is required for the current system.");
        }
        if (!"running".equals(fields.get("pcm"))) return result(Level.ATTENTION, "PCM audio bridge is not running yet",
            "First check the permission channel, user service and local PCM listening startup.", "If the process is not started, it cannot be directly judged that the chip is incompatible.");

        String failure = fields.getOrDefault("pcm_failure", "none");
        if (!failure.equals("none")) {
            String code = fields.getOrDefault("pcm_error_code", "unknown");
            if (code.equals("permission_denied")) return result(Level.ATTENTION, "Call audio permission was denied by the system",
                "Check Shizuku/Root authorization and system call audio collection permissions; ordinary microphone permissions cannot replace call collection permissions.",
                "If it is still rejected by the system after authorization, you need to adapt the privileged audio access path of the current ROM.");
            if (code.equals("telephony_tx_unavailable") || code.equals("platform_api_unavailable")) {
                return result(Level.INCOMPATIBLE, "The current device is not compatible with SimHelp · Adaptation is required",
                    code.equals("telephony_tx_unavailable") ? "Pending adaptation: The call uplink is injected into the backend, and the system does not provide a send port available for the existing bridge."
                        : "Pending adaptation: Audio interface missing from current Android/manufacturer systems.",
                    "This is a failure of the most recent audio session, updated after redetection or successful establishment of a new session.");
            }
            points.add(failurePoint(code, failure));
            points.add("This is the fault record of the most recent session; it needs to be judged based on permissions, call status and device routing, not just based on the chip model.");
            return new Result(Level.ATTENTION, "Audio bridge abnormality · To be checked or adapted", List.copyOf(points));
        }
        if (!"ok".equals(fields.get("pcm_cap_query"))) {
            points.add("Audio port capability not yet obtained: Check privileged query permissions or update the audio bridge; do not treat query failures as missing ports.");
        } else {
            points.add(tx.equals("samsung_tag") ? "Samsung VOICE_TX interface found; the existence of the interface does not mean that the actual route has been verified."
                : "Discover the system call sending port Telephony Tx.");
            if ("conversion".equals(fields.get("pcm_cap_format"))) points.add(
                "redmi9_mtk_experimental".equals(fields.get("pcm_profile"))
                    ? "Redmi 9 experimental format adaptation has been enabled, and the network protocol is still 8 kHz mono; actual two-way listening acceptance shall prevail."
                    : "Format pending verification: The format declared by the send port is different from the bridge's 8 kHz mono PCM16 and may require sample rate/channel adaptation; the system may also convert automatically.");
            if ("not_exposed".equals(fields.get("pcm_cap_rx"))) points.add(
                "Downlink needs to be verified: The system does not disclose the call receiving port, and the VOICE_DOWNLINK collection still needs to be verified, and it cannot be determined based on this that there is no downlink.");
        }
        if (!"true".equals(fields.get("pcm_initialized"))) {
            points.add("There are currently no remote audio sessions being initialized. It will not actively collect sound when it is idle, not yet paired, or when it is only talking locally.");
            points.add("Two-way call to be verified: Make a call manually after pairing, and the detection will automatically observe the actual data and routing.");
            return new Result(Level.PENDING, "ok".equals(fields.get("pcm_cap_query"))
                ? "Basic check completed · Two-way call pending verification" : "Incomplete detection information · Two-way call pending verification", List.copyOf(points));
        }
        if (!carrierActive) {
            points.add("Wait for the operator's call to connect; no audio or one-way reception will not be judged as a fault for the time being.");
            return new Result(Level.PENDING, "Waiting for call audio verification", List.copyOf(points));
        }
        if ("yes".equals(fields.get("pcm_capture_silenced"))) {
            points.add("The system is collecting silent calls: Check the call recording occupancy, privileged collection permissions and ROM audio policy; the network transmission is normal or only silent data may be received.");
            return new Result(Level.ATTENTION, "The downlink call is muted by the system", List.copyOf(points));
        }
        if ("other".equals(fields.get("pcm_capture_route"))) {
            points.add("To be adapted: The actual downlink input is not the call receiving port, and the phone microphone or external playback should not be used to replace the call sound.");
            return new Result(Level.ATTENTION, "Call downlink routing exception", List.copyOf(points));
        }
        if ("other".equals(fields.get("pcm_route_observed")) && !tx.equals("samsung_tag")) {
            points.add("Pending adaptation: The actual uplink playback device is not the call sending port, and the remote sound may not be injected into the cellular call. Please end the test and check the system routing adaptation.");
            return new Result(Level.ATTENTION, "The call uplink routing is abnormal · Adaptation is required", List.copyOf(points));
        }
        if (number(fields, "pcm_session_age_ms") < 0) {
            points.add("The current audio bridge does not return session aging information. Please update and reconnect to the permission service; do not use old statistics to determine the current call.");
            return new Result(Level.PENDING, "Audio bridge detection information to be updated", List.copyOf(points));
        }
        if (number(fields, "pcm_session_age_ms") < 10_000) {
            points.add("The audio session has just been established and is waiting for bidirectional frames and routing evidence from the sender.");
            return new Result(Level.PENDING, "Verifying bidirectional PCM link", List.copyOf(points));
        }
        if (number(fields, "pcm_stats_age_ms") < 0 || number(fields, "pcm_stats_age_ms") > 4_000) {
            points.add("PCM statistics are not updated and cannot tell whether bidirectional data is still being transmitted; check the audio bridge thread and current connection.");
            return new Result(Level.ATTENTION, "Audio link detection data has expired", List.copyOf(points));
        }
        boolean downStalled = number(fields, "pcm_down_bytes") <= 0 || number(fields, "pcm_down_idle_ms") >= 8_000;
        boolean upStalled = number(fields, "pcm_up_bytes") <= 0 || number(fields, "pcm_up_idle_ms") >= 8_000;
        if (downStalled) points.add("Downlink not advancing: Check for VOICE_DOWNLINK capture, system read errors, and phone-to-iPhone media links.");
        if (upStalled) points.add("Upstream not advancing: Check iPhone audio sessions, network/Bluetooth transfers, and Telephony Tx writes; cannot be directly attributed to chip incompatibility.");
        if (downStalled || upStalled) return new Result(Level.ATTENTION, "Bidirectional PCM link abnormality", List.copyOf(points));
        if (!"verified".equals(fields.get("pcm_route"))) {
            points.add("Bidirectional data is being transmitted, but the upstream route has not been verified; Telephony Tx/vendor routing adaptation needs to be checked. Hidden routing requires manual confirmation of the peer's voice.");
            return new Result(Level.ATTENTION, "The uplink call route needs to be verified", List.copyOf(points));
        }
        if ("redmi9_mtk_experimental".equals(fields.get("pcm_profile"))
                && !"telephony".equals(fields.get("pcm_capture_route"))) {
            points.add("Redmi 9 experimental adaptation has not yet confirmed the actual downlink route; successful initialization cannot be considered as the iPhone can hear sound.");
            return new Result(Level.PENDING, "Redmi 9 downlink routing needs to be verified", List.copyOf(points));
        }
        if (number(fields, "pcm_down_peak") <= 1 || number(fields, "pcm_up_peak") <= 1) {
            points.add("Bidirectional data and sender routing has been observed, but no significant sound has been observed on one side. This will also happen if the voice is muted and no one is talking; please take turns speaking to verify.");
            return new Result(Level.PENDING, "Audio content awaits manual verification", List.copyOf(points));
        }
        points.add("Bidirectional PCM data advancement and call sender routing have been observed; it still needs to be confirmed that both parties can actually hear the sound, which does not mean that all call scenarios have been adapted.");
        return new Result(Level.OBSERVED, "Bidirectional PCM link observed", List.copyOf(points));
    }

    static boolean knownShizukuMtkStartupRisk(String hardware, String version) {
        if (hardware == null || version == null) return false;
        return hardware.toLowerCase(java.util.Locale.ROOT).matches("mt[0-9]+[a-z0-9_]*")
            && (version.equals("13.6.0") || version.startsWith("13.6.0."));
    }

    private static String failurePoint(String code, String event) {
        if (code.startsWith("capture_") || event.equals("downlink_error")) return "To be checked/adapted: call downlink collection source, sampling format and system AudioRecord reading.";
        if (code.startsWith("playback_") || code.equals("telephony_tx_rejected") || event.equals("uplink_error"))
            return "To be checked/adapted: Telephony Tx uplink injection, sample rate/channel conversion and AudioTrack writing.";
        if (code.startsWith("telephony_query")) return "To be checked/adapted: Privileged audio port query interface and access permissions.";
        if (code.startsWith("handshake")) return "To be investigated: PCM handshake or connection interruption; check the permission service and transmission link, and it is not directly determined that the audio hardware is incompatible.";
        return "Troubleshooting: Audio initialization or media session failed, please check the error phase in the local PCM details.";
    }
    private static Result result(Level level, String title, String... points) { return new Result(level, title, List.of(points)); }
    private static Map<String, String> parse(String report) {
        Map<String, String> result = new HashMap<>();
        if (report == null || report.length() > 8192) return result;
        for (String field : report.split("\\s+")) {
            int at = field.indexOf('=');
            if (at > 0 && at < field.length() - 1) result.put(field.substring(0, at), field.substring(at + 1));
        }
        return result;
    }
    private static long number(Map<String, String> fields, String key) {
        try { return Long.parseLong(fields.get(key)); } catch (NumberFormatException ignored) { return -1; }
    }
}
