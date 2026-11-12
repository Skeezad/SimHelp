package com.airsim.phonecontrol;

import android.os.SystemClock;

/**
 * Short-lived window opened only while AirSIM's own SmsManager call is pending.
 * The accessibility service must never click a generic "发送" button outside it.
 */
final class SmsSendConfirmationGate {
    private static volatile long armedUntilMillis;

    private SmsSendConfirmationGate() {}

    static void arm(long durationMillis) {
        armedUntilMillis = SystemClock.elapsedRealtime() + Math.max(1_000L, durationMillis);
    }

    static void disarm() {
        armedUntilMillis = 0L;
    }

    static boolean isArmed() {
        return armedUntilMillis != 0L && SystemClock.elapsedRealtime() <= armedUntilMillis;
    }
}
