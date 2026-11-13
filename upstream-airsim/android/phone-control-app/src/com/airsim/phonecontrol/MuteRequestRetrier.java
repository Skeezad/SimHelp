package com.airsim.phonecontrol;

/** Retries a transient privileged audio command without replaying an obsolete call state. */
final class MuteRequestRetrier {
    interface Scheduler {
        void execute(Runnable task);
        void schedule(Runnable task, long delayMillis);
    }

    interface Action {
        void apply(boolean muted) throws Exception;
        /** Transport tag (VoBLE/VoWLAN) so a retry keeps the right stream policy. */
        default void apply(boolean muted, String transport) throws Exception { apply(muted); }
    }

    interface Listener {
        void completed(boolean muted, Exception error);
    }

    private final Scheduler scheduler;
    private final Action action;
    private final Listener listener;
    private int generation;

    MuteRequestRetrier(Scheduler scheduler, Action action, Listener listener) {
        this.scheduler = scheduler;
        this.action = action;
        this.listener = listener;
    }

    synchronized void request(boolean muted) {
        requestWithTransport(muted, PrivilegedBridgeProtocol.TRANSPORT_VOWLAN);
    }

    synchronized void requestWithTransport(boolean muted, String transport) {
        int requestedGeneration = ++generation;
        String tag = PrivilegedBridgeProtocol.TRANSPORT_VOBLE.equals(transport)
                ? PrivilegedBridgeProtocol.TRANSPORT_VOBLE
                : PrivilegedBridgeProtocol.TRANSPORT_VOWLAN;
        scheduler.execute(() -> attempt(requestedGeneration, muted, tag, 1));
    }

    private void attempt(int requestedGeneration, boolean muted, String transport, int number) {
        if (!isCurrent(requestedGeneration)) return;
        try {
            action.apply(muted, transport);
            if (isCurrent(requestedGeneration)) listener.completed(muted, null);
        } catch (Exception error) {
            if (!isCurrent(requestedGeneration)) return;
            int next = Math.min(number + 1, 4);
            scheduler.schedule(() -> attempt(requestedGeneration, muted, transport, next),
                    number < 3 ? number * 1_000L : 10_000L);
            if (number == 3) listener.completed(muted, error);
        }
    }

    private synchronized boolean isCurrent(int requestedGeneration) {
        return requestedGeneration == generation;
    }
}
