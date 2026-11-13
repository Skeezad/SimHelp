package com.airsim.phonecontrol;

import java.util.List;

public final class AppUpdatePolicyTests {
    private static int checks;
    private static void check(boolean condition, String why) {
        checks++; if (!condition) throw new AssertionError(why);
    }
    private static AppUpdatePolicy.Release release(String tag, String asset, boolean draft, boolean prerelease) {
        return new AppUpdatePolicy.Release(tag, draft, prerelease,
                List.of(new AppUpdatePolicy.Asset(asset,
                    "https://github.com/kai-wu-cortex/AirSIM/releases/download/" + tag + "/" + asset)), "notes");
    }
    public static void main(String[] args) {
        check(AppUpdatePolicy.needsNotes("0.9.8#92", ""), "first install must show offline notes");
        check(!AppUpdatePolicy.needsNotes("0.9.8#92", "0.9.8#92"), "same build must not repeat");
        check(AppUpdatePolicy.needsNotes("0.9.8#93", "0.9.8#92"), "same marketing version with new build needs notes");
        check(AppUpdatePolicy.checkDue(0, 100_000_000, false, false), "first check due");
        check(!AppUpdatePolicy.checkDue(100_000_000, 100_000_001, false, false), "no foreground polling");
        check(AppUpdatePolicy.checkDue(100_000_000, 186_400_000, false, false), "24 hour interval");
        check(AppUpdatePolicy.checkDue(100_000_000, 100_000_001, true, false), "manual bypasses daily cooldown");
        check(!AppUpdatePolicy.checkDue(0, 100_000_000, true, true), "coalesce manual and automatic checks");
        check(!AppUpdatePolicy.checkDue(200_000_000, 100_000_000, false, false), "clock rollback must not flood");
        var agent = release("v9.0.0", "airsim-avf-agent_9.0.0-1_arm64.deb", false, false);
        var stable = release("v0.10.0", "AirSIM-Android-Standalone-0.10.0-Android10-13.apk", false, false);
        var old = release("v0.9.8", "AirSIM-Android-Standalone-0.9.8-Android10-13.apk", false, false);
        var bridge = release("v1.0.0", "AirSIM-Android-AVF-1.0.0.apk", false, false);
        var draft = release("v8.0.0", "AirSIM-Android-Standalone-8.0.0.apk", true, false);
        var beta = release("v7.0.0", "AirSIM-Android-Standalone-7.0.0.apk", false, true);
        var found = AppUpdatePolicy.select(List.of(agent, old, bridge, draft, beta, stable), "0.9.8.1", 94, true);
        check(found != null && found.version().equals("0.10.0"), "numeric ordering and app/platform filtering");
        check(found.page().equals("https://github.com/kai-wu-cortex/AirSIM/releases/tag/v0.10.0"), "canonical project release page");
        check(AppUpdatePolicy.select(List.of(old), "0.9.8.1", 94, true) == null, "never offer semantic downgrade");
        check(AppUpdatePolicy.select(List.of(old), "0.9.8", 94, true) == null, "unknown build must not offer same-version downgrade");
        check(AppUpdatePolicy.select(List.of(stable), "unknown", 94, true) == null, "unknown installed version fails closed");
        var rebuild = release("v0.9.8", "AirSIM-Android-Standalone-0.9.8-build95.apk", false, false);
        check(AppUpdatePolicy.select(List.of(rebuild), "0.9.8", 94, true).build() == 95, "explicit build detects same-version upgrade");
        check(AppUpdatePolicy.select(List.of(rebuild), "0.9.8", 95, true) == null, "same build no update");
        var mismatched = release("v9.0.0", "AirSIM-Android-Standalone-0.9.8.apk", false, false);
        check(AppUpdatePolicy.select(List.of(mismatched), "0.9.8", 94, true) == null, "asset must match release tag");
        var lowerBuild = release("v1.0.0", "AirSIM-Android-Standalone-1.0.0-build90.apk", false, false);
        check(AppUpdatePolicy.select(List.of(lowerBuild), "0.9.8", 94, true) == null, "known lower versionCode is not installable upgrade");
        var unsafe = new AppUpdatePolicy.Release("v1.0.0", false, false,
            List.of(new AppUpdatePolicy.Asset("AirSIM-Android-Standalone-1.0.0.apk", "https://evil.invalid/app.apk")), "notes");
        check(AppUpdatePolicy.select(List.of(unsafe), "0.9.8", 94, true) == null, "reject non-project asset host");
        check(AppUpdatePolicy.select(List.of(bridge), "0.9.8", 92, false) != null, "AVF Bridge gets APK, never Linux package");
        System.out.println("AppUpdatePolicyTests: " + checks + " checks passed");
    }
}
