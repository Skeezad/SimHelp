package com.airsim.phonecontrol;

import java.io.IOException;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.function.Consumer;

/** Accepts peers until the listener is closed or its underlying socket fails. */
final class VoWLANAcceptLoop {
    private VoWLANAcceptLoop() {}

    static void run(ServerSocket listener, Consumer<Socket> onPeer, Consumer<IOException> onError) {
        while (!listener.isClosed()) {
            try {
                onPeer.accept(listener.accept());
            } catch (IOException error) {
                if (!listener.isClosed()) onError.accept(error);
                try { listener.close(); } catch (IOException ignored) {}
                return;
            }
        }
    }
}
