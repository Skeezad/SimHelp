package com.airsim.phonecontrol;

import android.content.Context;

/** User-selected privileged transport. AUTO keeps KernelSU root first, Shizuku fallback. */
final class PrivilegeChannelPreference {
    enum Channel { AUTO, SHIZUKU, ROOT }

    private static final String FILE = "privilege_channel";
    private static final String KEY = "channel";

    private PrivilegeChannelPreference() {}

    static Channel get(Context context) {
        String value = context.getApplicationContext()
                .getSharedPreferences(FILE, Context.MODE_PRIVATE)
                .getString(KEY, Channel.AUTO.name());
        try {
            return Channel.valueOf(value == null ? Channel.AUTO.name() : value);
        } catch (IllegalArgumentException ignored) {
            return Channel.AUTO;
        }
    }

    static void set(Context context, Channel channel) {
        context.getApplicationContext()
                .getSharedPreferences(FILE, Context.MODE_PRIVATE)
                .edit().putString(KEY, (channel == null ? Channel.AUTO : channel).name()).apply();
    }

    static String label(Channel channel) {
        if (channel == Channel.SHIZUKU) return "仅 Shizuku";
        if (channel == Channel.ROOT) return "仅 Root（KernelSU）";
        return "自动（Root 优先，失败回 Shizuku）";
    }
}
