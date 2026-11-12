package com.airsim.phonecontrol;

public final class AppReleaseClientTests {
    public static void main(String[] args) throws Exception {
        String asset = "{\"name\":\"AirSIM-Android-Standalone-1.0.0-build100.apk\",\"state\":\"uploaded\","
            + "\"browser_download_url\":\"https://github.com/kai-wu-cortex/AirSIM/releases/download/v1.0.0/AirSIM-Android-Standalone-1.0.0-build100.apk\"}";
        String json = "[{\"tag_name\":\"v1.0.0\",\"draft\":false,\"prerelease\":false,\"assets\":[" + asset + "]}]";
        if (AppUpdatePolicy.select(AppReleaseClient.parse(json), "0.9.8", 92, true) == null)
            throw new AssertionError("actual GitHub JSON release not recognized");
        if (AppUpdatePolicy.select(AppReleaseClient.parse(json.replace("uploaded", "starter")), "0.9.8", 92, true) != null)
            throw new AssertionError("unfinished upload offered");
        if (AppUpdatePolicy.select(AppReleaseClient.parse(json.replace("\"draft\":false,", "")), "0.9.8", 92, true) != null)
            throw new AssertionError("missing draft flag must fail closed");
        boolean rejected = false;
        try { AppReleaseClient.parse("{\"message\":\"API rate limit exceeded\"}"); }
        catch (Exception expected) { rejected = true; }
        if (!rejected) throw new AssertionError("API error object mistaken for no updates");
        if (!AppReleaseClient.parse("[]").isEmpty()) throw new AssertionError("empty release list");
        System.out.println("AppReleaseClientTests: 5 checks passed");
    }
}
