package com.airsim.bridge;

/** Stops then releases one OS endpoint; a failed stop must never skip release. */
final class AudioEndpointLease implements AutoCloseable {
    private final Runnable stop;
    private final Runnable release;
    private boolean closed;

    AudioEndpointLease(Runnable stop, Runnable release) {
        this.stop = stop;
        this.release = release;
    }

    @Override public void close() {
        if (closed) return;
        closed = true;
        try {
            stop.run();
        } catch (RuntimeException | Error failure) {
            try { release.run(); }
            catch (RuntimeException | Error secondary) {
                if (failure != secondary) failure.addSuppressed(secondary);
            }
            throw failure;
        }
        release.run();
    }
}
