package com.airsim.phonecontrol;

/** Replaces only the Agent transport, not gateway receipt construction or Telecom identity lookup. */
public final class AgentClient {
    public record ForwardResponse(int status, String payload) {}
    interface Forwarder { ForwardResponse forward(String method, String path, String body) throws Exception; }
    static Forwarder transport;
    public AgentClient(android.content.Context context) {}
    public ForwardResponse forwardVoWLAN(String method, String path, String body) throws Exception {
        return transport.forward(method, path, body);
    }
}
