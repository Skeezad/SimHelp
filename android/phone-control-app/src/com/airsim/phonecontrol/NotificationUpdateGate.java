package com.airsim.phonecontrol;

import java.util.Objects;

/** Avoid reposting an unchanged foreground notification on every service loop. */
final class NotificationUpdateGate {
    private static final long REFRESH_MILLIS = 60_000L;
    private boolean hasPublished;
    private String lastDetail;
    private long lastPublishedAt;

    boolean shouldPublish(String detail, long now) {
        return !hasPublished || !Objects.equals(lastDetail, detail)
                || now < lastPublishedAt || now - lastPublishedAt >= REFRESH_MILLIS;
    }

    void published(String detail, long now) {
        hasPublished = true;
        lastDetail = detail;
        lastPublishedAt = now;
    }
}
