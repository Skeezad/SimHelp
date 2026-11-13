package com.airsim.phonecontrol;

import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

/** Refreshes one visible status value without rebuilding its page. */
final class LiveStatusPoller {
    interface Scheduler {
        void postDelayed(Runnable task, long delayMillis);
        void removeCallbacks(Runnable task);
    }

    private final BooleanSupplier source;
    private final Consumer<Boolean> render;
    private final Scheduler scheduler;
    private final long intervalMillis;
    private boolean running;
    private Boolean lastRendered;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!running) return;
            try {
                boolean value = source.getAsBoolean();
                if (lastRendered == null || lastRendered != value) {
                    render.accept(value);
                    lastRendered = value;
                }
            } catch (RuntimeException error) {
                BridgeLog.error("pcm_status_poll_failed", error);
            } finally {
                if (running) scheduler.postDelayed(this, intervalMillis);
            }
        }
    };

    LiveStatusPoller(BooleanSupplier source, Consumer<Boolean> render,
            Scheduler scheduler, long intervalMillis) {
        this.source = source;
        this.render = render;
        this.scheduler = scheduler;
        this.intervalMillis = intervalMillis;
    }

    void start() {
        if (running) return;
        running = true;
        tick.run();
    }

    void stop() {
        running = false;
        scheduler.removeCallbacks(tick);
        lastRendered = null;
    }
}
