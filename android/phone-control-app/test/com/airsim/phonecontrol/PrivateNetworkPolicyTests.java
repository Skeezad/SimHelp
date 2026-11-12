package com.airsim.phonecontrol;

import java.util.List;

public final class PrivateNetworkPolicyTests {
    public static void main(String[] args) {
        List<PrivateNetworkPolicy.Prefix> custom = PrivateNetworkPolicy.parseAll("30.0.0.0/8, 100.64.0.0/10");
        check(custom.size() == 2, "two custom ranges must parse");
        check(custom.get(0).text().equals("30.0.0.0/8"), "prefix text must round-trip");
        check(PrivateNetworkPolicy.contains(custom, "30.1.2.3"), "custom /8 must contain 30.1.2.3");
        check(!PrivateNetworkPolicy.contains(custom, "31.1.2.3"), "custom /8 must not contain 31.x");

        // Default policy rejects a non-RFC1918 LAN the user has not configured.
        VoWLANNetworkPolicy.setCustomPrefixes(List.of());
        check(!VoWLANNetworkPolicy.permitsPeer("30.0.0.5", "30.0.0.2"),
                "unconfigured 30/8 peer must stay rejected");
        check(!VoWLANNetworkPolicy.isVoWLANInterface("wlan0", "30.0.0.2"),
                "unconfigured 30/8 must not be treated as a VoWLAN address");

        // User-configured range participates in control/PCM and pairing policy.
        VoWLANNetworkPolicy.setCustomPrefixes(custom);
        check(VoWLANNetworkPolicy.permitsPeer("30.0.0.5", "30.0.0.2"),
                "configured 30/8 peer must pass control/PCM policy");
        check(VoWLANNetworkPolicy.isVoWLANInterface("wlan0", "30.0.0.2"),
                "configured 30/8 must be advertised as a VoWLAN address");
        check(VoWLANNetworkPolicy.isCustomPrivate("100.64.9.9"), "custom CGNAT copy must match");
        check(!VoWLANNetworkPolicy.permitsPeer("8.8.8.8", "30.0.0.2"),
                "public peers stay rejected even with custom ranges");
        check(!VoWLANNetworkPolicy.permitsPeer("30.0.0.5", "127.0.0.1"),
                "loopback must keep rejecting non-loopback peers");

        // A narrower prefix must not widen to neighbours.
        VoWLANNetworkPolicy.setCustomPrefixes(PrivateNetworkPolicy.parseAll("30.10.0.0/16"));
        check(VoWLANNetworkPolicy.permitsPeer("30.10.1.5", "30.10.1.2"), "custom /16 peer allowed");
        check(!VoWLANNetworkPolicy.permitsPeer("30.11.1.5", "30.10.1.2"), "neighbour /16 rejected");

        // Malformed input is ignored rather than widening the allowlist.
        check(PrivateNetworkPolicy.parse("30.0.0.0/33") == null, "prefix length above 32 is invalid");
        check(PrivateNetworkPolicy.parse("30.0.0") == null, "incomplete address is invalid");
        check(PrivateNetworkPolicy.parse("030.0.0.0/8") == null, "leading zero is invalid");
        check(PrivateNetworkPolicy.parse("") == null, "blank is invalid");
        check(PrivateNetworkPolicy.parseAll("bogus, 30.0.0.0/8").size() == 1,
                "invalid entries must be dropped, not executed");
        VoWLANNetworkPolicy.setCustomPrefixes(List.of());
        System.out.println("PrivateNetworkPolicyTests passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
