package com.airsim.phonecontrol;

import java.net.InetAddress;

public final class PairingPeerPolicyTests {
    public static void main(String[] args) throws Exception {
        // Bonjour may select Wi-Fi link-local IPv6 even when both phones also have IPv4.
        check(VoWLANNetworkPolicy.permitsPairingPeer(
                InetAddress.getByName("fe80::1234"), InetAddress.getByName("fe80::5678"), "wlan0"),
                "automatic Bonjour pairing must accept link-local IPv6 on Wi-Fi");
        for (String name : new String[]{"swlan0", "ap0"}) {
            check(VoWLANNetworkPolicy.permitsPairingPeer(
                    InetAddress.getByName("fe80::1234"), InetAddress.getByName("fe80::5678"), name),
                    "hotspot link-local pairing must remain available");
        }
        for (String name : new String[]{"rmnet0", "tun0", "lo", null}) {
            check(!VoWLANNetworkPolicy.permitsPairingPeer(
                    InetAddress.getByName("fe80::1234"), InetAddress.getByName("fe80::5678"), name),
                    "IPv6 pairing must not widen cellular, overlay or unknown interface access");
        }
        for (String remote : new String[]{"2001:db8::1", "fd00::1", "::1", "192.168.1.3"}) {
            check(!VoWLANNetworkPolicy.permitsPairingPeer(
                    InetAddress.getByName(remote), InetAddress.getByName("fe80::5678"), "wlan0"),
                    "non-link-local and mixed-family peers must stay rejected");
        }
        check(!VoWLANNetworkPolicy.permitsPairingPeer(
                InetAddress.getByName("fe80::1234"), InetAddress.getByName("2001:db8::2"), "wlan0"),
                "local endpoint must also be link-local");
        check(VoWLANNetworkPolicy.permitsPairingPeer(
                InetAddress.getByName("192.168.1.3"), InetAddress.getByName("192.168.1.2"), "wlan0"),
                "ordinary IPv4 pairing must remain available");
        check(VoWLANNetworkPolicy.permitsPairingPeer(
                InetAddress.getByName("100.64.1.3"), InetAddress.getByName("100.64.1.2"), "tun0"),
                "Tailscale IPv4 pairing must remain available");
        check(VoWLANNetworkPolicy.permitsPairingPeer(
                InetAddress.getByName("100.64.1.3"), InetAddress.getByName("192.168.1.2"), "wlan0"),
                "one-end Tailscale subnet routing must pair over the LAN address");
        check(VoWLANNetworkPolicy.permitsPeer("100.64.1.3", "192.168.1.2"),
                "tailnet peer arriving on the LAN must pass control/PCM policy");
        check(VoWLANNetworkPolicy.permitsPeer("192.168.1.3", "100.64.1.2"),
                "LAN peer arriving on a tailnet address must pass control/PCM policy");
        check(!VoWLANNetworkPolicy.permitsPeer("100.64.1.3", "127.0.0.1"),
                "loopback must not accept a tailnet peer");
        check(!VoWLANNetworkPolicy.permitsPairingPeer(
                InetAddress.getByName("8.8.8.8"), InetAddress.getByName("192.168.1.2"), "wlan0"),
                "public IPv4 must stay rejected");
        System.out.println("PairingPeerPolicyTests passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
