package com.airsim.phonecontrol;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Anonymous public GitHub read. Never uses Relay/Agent credentials or device IDs. */
public final class AppReleaseClient {
    private AppReleaseClient() {}
    public static List<AppUpdatePolicy.Release> fetch() throws Exception {
        HttpURLConnection connection = (HttpURLConnection) URI.create(
                "https://api.github.com/repos/kai-wu-cortex/AirSIM/releases?per_page=100").toURL().openConnection();
        connection.setConnectTimeout(10_000);
        connection.setReadTimeout(15_000);
        connection.setInstanceFollowRedirects(false);
        connection.setRequestProperty("Accept", "application/vnd.github+json");
        connection.setRequestProperty("X-GitHub-Api-Version", "2022-11-28");
        connection.setRequestProperty("User-Agent", "AirSIM-App-Update");
        try {
            if (connection.getResponseCode() != 200) throw new IOException("GitHub HTTP " + connection.getResponseCode());
            try (var input = connection.getInputStream(); var output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                long deadline = android.os.SystemClock.elapsedRealtime() + 20_000;
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() + count > 4 * 1024 * 1024
                            || android.os.SystemClock.elapsedRealtime() > deadline) throw new IOException("Update response limit");
                    output.write(buffer, 0, count);
                }
                return parse(output.toString(StandardCharsets.UTF_8.name()));
            }
        } finally { connection.disconnect(); }
    }
    static List<AppUpdatePolicy.Release> parse(String json) throws Exception {
        JSONArray array = new JSONArray(json);
        List<AppUpdatePolicy.Release> releases = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject release = array.getJSONObject(i);
            List<AppUpdatePolicy.Asset> assets = new ArrayList<>();
            JSONArray values = release.optJSONArray("assets");
            if (values == null) continue;
            for (int j = 0; j < values.length(); j++) {
                JSONObject asset = values.getJSONObject(j);
                if (!"uploaded".equals(asset.optString("state", ""))) continue;
                assets.add(new AppUpdatePolicy.Asset(asset.optString("name", ""), asset.optString("browser_download_url", "")));
            }
            releases.add(new AppUpdatePolicy.Release(release.optString("tag_name", ""),
                    release.optBoolean("draft", true), release.optBoolean("prerelease", true), assets,
                    release.optString("body", "")));
        }
        return releases;
    }
}
