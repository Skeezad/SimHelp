package com.airsim.phonecontrol;

import java.util.Arrays;

public final class HealthIdentityProofTests {
    public static void main(String[] args) {
        byte[] secret = new byte[32];
        Arrays.fill(secret, (byte) 0x41);
        String signature = DirectGatewayRoutes.healthProof(secret, "fixture-nonce", "fixture-agent");
        if (signature.isEmpty()) throw new AssertionError("health response needs an authenticated identity proof");
        if (!signature.equals("Mn-nJNSJLkoH1AjaSEtBWQvvulaejVSgxFSmC_gJRJc"))
            throw new AssertionError("health proof does not match independent OpenSSL vector");
        if (signature.equals(DirectGatewayRoutes.healthProof(secret, "another-nonce", "fixture-agent")))
            throw new AssertionError("proof must bind this exact request nonce");
        if (signature.equals(DirectGatewayRoutes.healthProof(secret, "fixture-nonce", "another-agent")))
            throw new AssertionError("proof must bind this exact Android identity");
        String dial = DirectGatewayRoutes.ownedDialProof(secret, "nonce", "operation-A", "telecom-A", "agent-A");
        if (dial.isEmpty()) throw new AssertionError("dial response needs authenticated operation identity");
        if (dial.equals(DirectGatewayRoutes.ownedDialProof(secret, "nonce", "operation-B", "telecom-A", "agent-A")))
            throw new AssertionError("another operation cannot adopt this call");
        if (dial.equals(DirectGatewayRoutes.ownedDialProof(secret, "nonce", "operation-A", "telecom-A", "agent-B")))
            throw new AssertionError("backend command identity must be authenticated");
        System.out.println("HealthIdentityProofTests passed");
    }
}
