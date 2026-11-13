package com.airsim.phonecontrol;

import android.content.Context;

import java.util.List;

/** User-tunable private ranges and preferred listener ports. */
final class NetworkSettings {
    static final int DEFAULT_CONTROL_PORT = 7592;
    static final int DEFAULT_PCM_PORT = 7593;
    static final int DEFAULT_PAIRING_PORT = 0;

    private static final String FILE = "network_settings";
    private static final String KEY_RANGES = "private_ranges";
    private static final String KEY_CONTROL = "control_port";
    private static final String KEY_PCM = "pcm_port";
    private static final String KEY_PAIRING = "pairing_port";

    private NetworkSettings() {}

    static String rangesText(Context context) {
        return prefs(context).getString(KEY_RANGES, "");
    }

    static List<PrivateNetworkPolicy.Prefix> ranges(Context context) {
        return PrivateNetworkPolicy.parseAll(rangesText(context));
    }

    static void setRangesText(Context context, String value) {
        prefs(context).edit().putString(KEY_RANGES, value == null ? "" : value.trim()).apply();
        apply(context);
    }

    static int controlPort(Context context) {
        return port(context, KEY_CONTROL, DEFAULT_CONTROL_PORT);
    }

    static int pcmPort(Context context) {
        return port(context, KEY_PCM, DEFAULT_PCM_PORT);
    }

    static int pairingPort(Context context) {
        return port(context, KEY_PAIRING, DEFAULT_PAIRING_PORT);
    }

    static void setPorts(Context context, int control, int pcm, int pairing) {
        prefs(context).edit()
                .putInt(KEY_CONTROL, valid(control, DEFAULT_CONTROL_PORT))
                .putInt(KEY_PCM, valid(pcm, DEFAULT_PCM_PORT))
                .putInt(KEY_PAIRING, valid(pairing, DEFAULT_PAIRING_PORT))
                .apply();
    }

    static void apply(Context context) {
        VoWLANNetworkPolicy.setCustomPrefixes(ranges(context));
    }

    private static int port(Context context, String key, int fallback) {
        return valid(prefs(context).getInt(key, fallback), fallback);
    }

    private static int valid(int value, int fallback) {
        return isUsablePort(value) ? value : fallback;
    }

    private static android.content.SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    /** True when the requested port is usable; 0 means "any free port". */
    static boolean isUsablePort(int value) {
        return value == 0 || (value >= 1024 && value <= 65535);
    }
}
