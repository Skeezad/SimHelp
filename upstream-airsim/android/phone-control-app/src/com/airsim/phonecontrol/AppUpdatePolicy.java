package com.airsim.phonecontrol;

import java.util.List;
import java.net.URI;
import java.util.regex.Pattern;

/** App releases only. Deliberately independent of the Linux Agent updater. */
public final class AppUpdatePolicy {
    public record Asset(String name, String url) {}
    public record Release(String tag, boolean draft, boolean prerelease, List<Asset> assets, String notes) {}
    public record Candidate(String version, long build, String page, String notes) {
        public String identity() { return version + "#" + build; }
    }
    private AppUpdatePolicy() {}
    public static boolean needsNotes(String installed, String seen) {
        return installed != null && !installed.isEmpty() && !installed.equals(seen);
    }
    public static boolean checkDue(long lastAttempt, long now, boolean manual, boolean checking) {
        return !checking && (manual || lastAttempt == 0 || (now >= lastAttempt && now - lastAttempt >= 86_400_000L));
    }
    public static Candidate select(List<Release> releases, String installed, long build, boolean standalone) {
        if (parts(installed) == null) return null;
        Candidate best = null;
        for (Release release : releases) {
            if (release.draft() || release.prerelease() || release.tag() == null) continue;
            String version = release.tag().startsWith("v") ? release.tag().substring(1) : release.tag();
            if (parts(version) == null || compare(version, installed) < 0) continue;
            Pattern pattern = Pattern.compile("AirSIM-Android-" + (standalone ? "Standalone" : "AVF")
                    + "-" + Pattern.quote(version) + "(?:-build([0-9]{1,9}))?(?:-Android10-13)?\\.apk");
            for (Asset asset : release.assets()) {
                var match = pattern.matcher(asset.name());
                if (!match.matches() || !trustedAsset(asset.url(), release.tag(), asset.name())) continue;
                long remoteBuild = match.group(1) == null ? 0 : Long.parseLong(match.group(1));
                if (remoteBuild > 0 && remoteBuild <= build) continue;
                if (compare(version, installed) == 0 && remoteBuild <= build) continue;
                if (best != null && (compare(version, best.version()) < 0
                        || (compare(version, best.version()) == 0 && remoteBuild <= best.build()))) continue;
                String notes = release.notes() == null ? "" : release.notes();
                best = new Candidate(version, remoteBuild,
                        "https://github.com/kai-wu-cortex/AirSIM/releases/tag/" + release.tag(),
                        notes.substring(0, Math.min(notes.length(), 6_000)));
            }
        }
        return best;
    }
    private static boolean trustedAsset(String value, String tag, String name) {
        try {
            URI uri = URI.create(value);
            return "https".equals(uri.getScheme()) && "github.com".equals(uri.getHost())
                    && uri.getPort() == -1 && uri.getUserInfo() == null && uri.getQuery() == null
                    && uri.getFragment() == null && uri.getRawPath().equals(
                        "/kai-wu-cortex/AirSIM/releases/download/" + tag + "/" + name);
        } catch (RuntimeException ignored) { return false; }
    }
    private static int[] parts(String version) {
        if (version == null || !version.matches("[0-9]{1,9}(?:\\.[0-9]{1,9}){2,3}")) return null;
        String[] pieces = version.split("\\.");
        int[] result = new int[4];
        for (int i = 0; i < pieces.length; i++) result[i] = Integer.parseInt(pieces[i]);
        return result;
    }
    private static int compare(String left, String right) {
        int[] a = parts(left), b = parts(right);
        for (int i = 0; i < 4; i++) if (a[i] != b[i]) return Integer.compare(a[i], b[i]);
        return 0;
    }
}
