package com.airsim.phonecontrol;

/** Avoids a tight retry loop when the Relay is rate limited or unavailable. */
final class RelayRetryPolicy {
    private RelayRetryPolicy() {}

    static long delayMillis(int consecutiveFailures, Throwable error) {
        if (error instanceof RelayHTTPException http
                && (http.statusCode() == 429 || http.statusCode() >= 500)) {
            int exponent = Math.max(0, Math.min(consecutiveFailures - 1, 5));
            return Math.min(300_000L, 15_000L << exponent);
        }
        return RetryPolicy.delayMillis(consecutiveFailures - 1);
    }
}
