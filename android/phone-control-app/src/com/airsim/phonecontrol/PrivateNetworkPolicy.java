package com.airsim.phonecontrol;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * User-defined private IPv4 ranges in addition to the built-in RFC1918 / CGNAT /
 * link-local defaults. Ranges never make a peer trusted: VoWLAN HMAC stays
 * mandatory; they only decide which LANs AirSIM is willing to serve.
 */
public final class PrivateNetworkPolicy {
    private PrivateNetworkPolicy() {}

    public record Prefix(int network, int bits) {
        public boolean contains(int address) {
            if (bits <= 0) return true;
            return bits >= 32
                    ? address == network
                    : (address & mask(bits)) == (network & mask(bits));
        }
        public String text() { return format(network) + "/" + bits; }
    }

    private static int mask(int bits) { return bits <= 0 ? 0 : bits >= 32 ? -1 : (-1 << (32 - bits)); }

    private static String format(int address) {
        return ((address >>> 24) & 0xFF) + "." + ((address >>> 16) & 0xFF) + "."
                + ((address >>> 8) & 0xFF) + "." + (address & 0xFF);
    }

    static int parseIPv4(String host) {
        if (host == null) return -1;
        String[] fields = host.trim().split("\\.", -1);
        if (fields.length != 4) return -1;
        int value = 0;
        for (String field : fields) {
            if (field.isEmpty() || field.length() > 3) return -1;
            if (field.length() > 1 && field.charAt(0) == '0') return -1;
            for (int index = 0; index < field.length(); index++) {
                char c = field.charAt(index);
                if (c < '0' || c > '9') return -1;
            }
            int part = Integer.parseInt(field);
            if (part > 255) return -1;
            value = (value << 8) | part;
        }
        return value;
    }

    public static Prefix parse(String text) {
        if (text == null) return null;
        String value = text.trim();
        if (value.isEmpty()) return null;
        int slash = value.indexOf('/');
        String host = slash < 0 ? value : value.substring(0, slash);
        int bits = 32;
        if (slash >= 0) {
            String parsed = value.substring(slash + 1).trim();
            if (parsed.isEmpty() || parsed.length() > 2) return null;
            for (int index = 0; index < parsed.length(); index++) {
                char c = parsed.charAt(index);
                if (c < '0' || c > '9') return null;
            }
            bits = Integer.parseInt(parsed);
            if (bits > 32) return null;
        }
        int network = parseIPv4(host);
        if (network < 0) return null;
        return new Prefix(network & mask(bits), bits);
    }

    public static List<Prefix> parseAll(String text) {
        List<Prefix> values = new ArrayList<>();
        if (text == null) return values;
        for (String item : text.split("[,\\s]+")) {
            Prefix prefix = parse(item);
            if (prefix != null && !values.contains(prefix)) values.add(prefix);
        }
        return Collections.unmodifiableList(values);
    }

    public static String formatAll(List<Prefix> values) {
        StringBuilder text = new StringBuilder();
        for (Prefix value : values) {
            if (text.length() > 0) text.append(", ");
            text.append(value.text());
        }
        return text.toString();
    }

    public static boolean contains(List<Prefix> values, String host) {
        int address = parseIPv4(host);
        if (address < 0) return false;
        for (Prefix value : values) if (value.contains(address)) return true;
        return false;
    }

    /** Built-in private/link-local/VoWLAN-overlay detection, extended by user ranges. */
    public static boolean isPrivateOrLocal(List<Prefix> custom, String host) {
        int address = parseIPv4(host);
        if (address < 0) return false;
        int a = (address >>> 24) & 0xFF;
        int b = (address >>> 16) & 0xFF;
        if (a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)) return true;
        if (a == 169 && b == 254) return true;
        if (a == 100 && b >= 64 && b <= 127) return true;
        if (a == 127) return true;
        return custom != null && contains(custom, host);
    }
}
