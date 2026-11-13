package com.airsim.phonecontrol;

/** Interprets the Shizuku UserService's live PCM process status. */
final class PCMBridgeStatus {
    private PCMBridgeStatus() {}

    static boolean isRunning(String value) {
        if (value == null) return false;
        for (String field : value.split("\\s+")) {
            if ("pcm=running".equals(field)) return true;
        }
        return false;
    }
}
