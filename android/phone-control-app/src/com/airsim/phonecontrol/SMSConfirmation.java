package com.airsim.phonecontrol;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Tracks sent callbacks; a failed segment resolves the attempt without waiting for the rest. */
final class SMSConfirmation {
    record Outcome(boolean complete, boolean success, int errorCode, int confirmedSegments) {}

    private final boolean[] received;
    private final CountDownLatch pending;
    private final CountDownLatch resolved = new CountDownLatch(1);
    private int firstErrorCode;
    private boolean failed;

    SMSConfirmation(int segments) {
        if (segments <= 0) throw new IllegalArgumentException("SMS has no segments");
        received = new boolean[segments];
        pending = new CountDownLatch(segments);
    }

    synchronized void record(int index, int resultCode) {
        if (index < 0 || index >= received.length || received[index]) return;
        received[index] = true;
        if (resultCode != -1 && !failed) {
            failed = true;
            firstErrorCode = resultCode;
        }
        pending.countDown();
        if (failed || pending.getCount() == 0) resolved.countDown();
    }

    Outcome await(long timeoutMillis) throws InterruptedException {
        boolean complete = resolved.await(timeoutMillis, TimeUnit.MILLISECONDS);
        synchronized (this) {
            return new Outcome(complete, complete && !failed, firstErrorCode,
                    received.length - (int) pending.getCount());
        }
    }
}
