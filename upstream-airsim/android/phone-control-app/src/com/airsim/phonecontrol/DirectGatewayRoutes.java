package com.airsim.phonecontrol;

import java.util.HashMap;
import java.util.Map;

/** Only live, explicitly bound Android gateways; never AVF or shell endpoints. */
public final class DirectGatewayRoutes {
    public record Ports(int controlPort, int pcmPort) {}
    private final Map<String, Ports> routes = new HashMap<>();

    public synchronized void put(String host, int controlPort, int pcmPort) {
        if (controlPort < 1024 || controlPort > 65535 || pcmPort < 1024 || pcmPort > 65535)
            throw new IllegalArgumentException("invalid direct gateway ports");
        routes.put(host, new Ports(controlPort, pcmPort));
    }
    public synchronized Ports forHost(String host) { return routes.get(host); }
    public synchronized void remove(String host) { routes.remove(host); }
    public static String healthProof(byte[] secret, String nonce, String agentID) {
        if (nonce == null || nonce.isEmpty() || agentID == null || agentID.isEmpty())
            throw new IllegalArgumentException("health identity requires a nonce and agent");
        return VoWLANAuth.sign(secret, "AIRSIM-HEALTH1\n" + nonce + "\n" + agentID);
    }
    public static String ownedDialProof(byte[] secret, String nonce, String operationID,
                                        String androidID, String backendID) {
        if (nonce == null || nonce.isEmpty() || operationID == null || operationID.isEmpty()
                || androidID == null || androidID.isEmpty() || backendID == null || backendID.isEmpty())
            throw new IllegalArgumentException("dial receipt requires explicit identities");
        return VoWLANAuth.sign(secret, "AIRSIM-DIAL1\n" + nonce + "\n" + operationID + "\n" + androidID + "\n" + backendID);
    }

    public static String proof(byte[] secret, String session, String clientKey, String agentID,
                               int controlPort, int pcmPort) {
        return VoWLANAuth.sign(secret, "AIRSIM-DIRECT1\n" + session + "\n" + clientKey + "\n" + agentID
                + "\n" + controlPort + "\n" + pcmPort);
    }
}
