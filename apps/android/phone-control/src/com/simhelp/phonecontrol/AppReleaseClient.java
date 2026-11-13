package com.simhelp.phonecontrol;

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
        return List.of();
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
