package com.simhelp.phonecontrol;

// SimHelp personal adaptation, 2026-11-12. Uses the licensed AirSIM transport.
import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.role.RoleManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** English, no-root setup and pairing entry point. Never reports audio as tested
 * merely because a service, permission or transport is connected. */
public final class SimHelpActivity extends Activity {
    private static final int BG = Color.rgb(10, 17, 28);
    private static final int CARD = Color.rgb(21, 33, 49);
    private static final int TEXT = Color.rgb(238, 244, 251);
    private static final int MUTED = Color.rgb(155, 174, 197);
    private static final int ACCENT = Color.rgb(81, 225, 183);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private TextView roleStatus, permissionStatus, bridgeStatus, peerStatus, pairCode, pairDetail, expiry;
    private PairingServer pairing;
    private long pairingGeneration;
    private long pairingExpires;
    private boolean resumed;
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            if (!resumed) return;
            updateStatus();
            handler.postDelayed(this, 1500);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        // This edition is explicitly no-root. Do not silently try `su`.
        ShizukuBridgeManager.get(this).setPrivilegeChannel(PrivilegeChannelPreference.Channel.SHIZUKU);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        page.setPadding(dp(22), dp(28), dp(22), dp(32));
        scroll.addView(page);
        setContentView(scroll);

        TextView brand = text("SimHelp", 34, TEXT);
        brand.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.setTextDirection(View.TEXT_DIRECTION_LTR);
        brand.setGravity(Gravity.START);
        page.addView(brand);
        page.addView(text("SIM on Android. Calls and messages on iPhone.", 16, MUTED));
        TextView badge = text("Personal build | No root required", 12, ACCENT);
        badge.setPadding(0, dp(12), 0, dp(18));
        page.addView(badge);

        LinearLayout device = card(page, "Android phone");
        device.addView(text(Build.MANUFACTURER + " " + Build.MODEL + " · Android " + Build.VERSION.RELEASE, 15, TEXT));
        device.addView(text("Call audio on the Galaxy A12 has not been verified in a real call. A connected audio bridge does not confirm that two-way audio works.", 13, MUTED));

        LinearLayout setup = card(page, "1. Set up Android");
        roleStatus = text("", 14, TEXT); setup.addView(roleStatus);
        button(setup, "Set SimHelp as the default phone app", this::requestDialer);
        permissionStatus = text("", 14, TEXT); setup.addView(permissionStatus);
        button(setup, "Grant call and SMS permissions", this::requestNeededPermissions);
        bridgeStatus = text("", 14, TEXT); setup.addView(bridgeStatus);
        button(setup, "Set up Shizuku", this::setupShizuku);
        setup.addView(text("Start Shizuku using Wireless debugging and complete its pairing steps. Then return to SimHelp and allow access. You may need to start Shizuku again after restarting your phone.", 13, MUTED));

        LinearLayout connect = card(page, "2. Connect your iPhone");
        connect.addView(text("Connect both phones to the same Wi-Fi, or connect your iPhone to this Android phone's hotspot. In the iPhone app, choose Local / VoWLAN and enter the pairing code below.", 14, MUTED));
        peerStatus = text("", 14, TEXT); connect.addView(peerStatus);
        pairCode = text("— — — — — —", 30, ACCENT);
        pairCode.setGravity(Gravity.CENTER);
        pairCode.setTextDirection(View.TEXT_DIRECTION_LTR);
        pairCode.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        connect.addView(pairCode);
        pairDetail = text("Tap Start pairing to generate a code.", 14, MUTED);
        pairDetail.setTextIsSelectable(true); connect.addView(pairDetail);
        expiry = text("", 12, MUTED); connect.addView(expiry);
        button(connect, "Start pairing", this::startPairing);
        button(connect, "Stop pairing", () -> { stopPairing(); pairCode.setText("— — — — — —"); pairDetail.setText("Pairing stopped."); });

        LinearLayout test = card(page, "3. Check call audio");
        test.addView(text("Make a short test call and check that both people can hear each other. The Galaxy A12's audio support must be verified during a real call; connection and permission checks alone cannot confirm it.", 14, TEXT));
        button(test, "Check audio bridge", this::checkAudio);
        button(test, "Open app settings", () -> open(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName()))));
        test.addView(text("Install the iPhone IPA using Sideloadly. If the phones cannot find each other, check that both are on the same network and that local network access is allowed on the iPhone.", 13, MUTED));

        LinearLayout help = card(page, "Help and advanced settings");
        button(help, "Open advanced settings", () -> open(new Intent(this, MainActivity.class)));
        button(help, "About SimHelp", () -> new AlertDialog.Builder(this)
                .setTitle("SimHelp · Personal build · TheSkeezad")
                .setMessage("SimHelp connects your iPhone to the SIM in your Android phone for calls and SMS.\n\nInstall the iPhone IPA using Sideloadly. Pair the phones using Local / VoWLAN on the same network. Shizuku must be running and authorized for the no-root audio bridge.\n\nAudio compatibility depends on your phone and must be checked in a real call.\n\nDeveloper: TheSkeezad\nLicense notices are included in the APK under assets/licenses.")
                .setPositiveButton("OK", null).show());
        TextView footer = text("SimHelp | TheSkeezad\nPersonal build | Test call audio on your phone before relying on it", 12, MUTED);
        footer.setGravity(Gravity.CENTER); footer.setPadding(0, dp(18), 0, 0); page.addView(footer);
        updateStatus();
    }

    private List<String> missingPermissions() {
        List<String> missing = new ArrayList<>();
        for (String permission : new String[]{Manifest.permission.CALL_PHONE, Manifest.permission.SEND_SMS,
                Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_PHONE_NUMBERS}) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) missing.add(permission);
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            missing.add(Manifest.permission.POST_NOTIFICATIONS);
        return missing;
    }

    private boolean isDialer() {
        RoleManager manager = getSystemService(RoleManager.class);
        return manager != null && manager.isRoleHeld(RoleManager.ROLE_DIALER);
    }

    private void requestDialer() {
        RoleManager manager = getSystemService(RoleManager.class);
        if (manager == null || !manager.isRoleAvailable(RoleManager.ROLE_DIALER)) {
            message("Default phone app unavailable", "This device does not allow SimHelp to request the default phone app role."); return;
        }
        if (isDialer()) { updateStatus(); return; }
        startActivityForResult(manager.createRequestRoleIntent(RoleManager.ROLE_DIALER), 400);
    }

    private void requestNeededPermissions() {
        List<String> missing = missingPermissions();
        if (missing.isEmpty()) { updateStatus(); return; }
        requestPermissions(missing.toArray(new String[0]), 401);
    }

    private void setupShizuku() {
        ShizukuBridgeManager bridge = ShizukuBridgeManager.get(this);
        ShizukuBridgeManager.StartupSnapshot snapshot = bridge.startupSnapshot();
        if (!snapshot.installed()) { open(new Intent(Intent.ACTION_VIEW, Uri.parse("https://shizuku.rikka.app/download/"))); return; }
        if (!snapshot.running()) { bridge.openShizuku(); return; }
        bridge.requestPermission();
        bridge.ensureStarted();
        updateStatus();
    }

    private void updateStatus() {
        if (roleStatus == null) return;
        roleStatus.setText(isDialer() ? "Ready: SimHelp is the default phone app" : "Action needed: Set SimHelp as the default phone app");
        permissionStatus.setText(missingPermissions().isEmpty() ? "Ready: Call and SMS permissions granted" : "Action needed: Grant call and SMS permissions");
        ShizukuBridgeManager bridge = ShizukuBridgeManager.get(this);
        ShizukuBridgeManager.StartupSnapshot snapshot = bridge.startupSnapshot();
        String state = !snapshot.installed() ? "Shizuku is not installed" : !snapshot.running() ? "Shizuku is not running"
                : !snapshot.authorized() ? "Allow SimHelp to use Shizuku" : bridge.privilegeConnected()
                ? "Shizuku bridge connected; call audio still needs a real-call test" : "Waiting for the Shizuku bridge to connect";
        bridgeStatus.setText(state);
        int peers = VoWLANPairingStore.records(this).size();
        peerStatus.setText(peers == 0 ? "No iPhone has been paired yet" : "Paired devices: " + peers + " | Saved pairing does not confirm an active connection");
        if (pairingExpires > 0) {
            long seconds = Math.max(0, (pairingExpires - System.currentTimeMillis()) / 1000);
            expiry.setText(seconds > 0 ? "Code expires in: " + seconds + " seconds" : "Pairing code expired. Start pairing again.");
            if (seconds == 0) {
                stopPairing(); pairCode.setText("— — — — — —");
                pairDetail.setText("The code has expired. Tap Start pairing to generate a new code.");
                expiry.setText("Pairing session expired.");
            }
        }
    }

    private void startPairing() {
        if (!isDialer() || !missingPermissions().isEmpty()) {
            message("Complete Android setup", "Set SimHelp as the default phone app and grant the required permissions before pairing."); return;
        }
        stopPairing();
        final long generation = pairingGeneration;
        pairDetail.setText("Starting the pairing service...");
        pairCode.setText("…");
        pairing = new PairingServer(this, new PairingServer.Listener() {
            @Override public void onStarted(String code, String address, long expiresAt) {
                runOnUiThread(() -> {
                    if (generation != pairingGeneration || isDestroyed()) return;
                    pairingExpires = expiresAt;
                    pairCode.setText(code);
                    pairDetail.setText("Enter this code in the iPhone app. Manual connection address:\n" + address);
                    updateStatus();
                });
            }
            @Override public void onSucceeded(String ignored) {
                runOnUiThread(() -> {
                    if (generation != pairingGeneration || isDestroyed()) return;
                    stopPairing();
                    pairCode.setText("✓");
                    pairDetail.setText("Pairing complete. Open the iPhone app to check the connection and test calls and SMS.");
                    updateStatus();
                });
            }
            @Override public void onFailed(String ignored) {
                runOnUiThread(() -> {
                    if (generation != pairingGeneration || isDestroyed()) return;
                    stopPairing();
                    pairCode.setText("—");
                    pairDetail.setText("Pairing failed. Check the Wi-Fi connection and try again. Both phones must be on the same network.");
                });
            }
        });
        pairing.start();
    }

    private void stopPairing() {
        pairingGeneration++;
        pairingExpires = 0;
        if (expiry != null) expiry.setText("");
        PairingServer active = pairing; pairing = null;
        if (active != null) try { active.close(); } catch (java.io.IOException ignored) { }
    }

    private void checkAudio() {
        ShizukuBridgeManager bridge = ShizukuBridgeManager.get(this);
        if (!bridge.privilegeConnected()) { setupShizuku(); return; }
        worker.execute(() -> {
            String report;
            try { report = bridge.freshAudioHealthReport(); }
            catch (RuntimeException error) { report = "Audio check failed: " + error.getClass().getSimpleName(); }
            final String result = report;
            runOnUiThread(() -> { if (!isDestroyed()) message("Audio bridge diagnostics", "This report checks the audio bridge. It does not confirm that both people can hear each other during a call.\n\n" + result); });
        });
    }

    private void open(Intent intent) {
        try { startActivity(intent); }
        catch (android.content.ActivityNotFoundException error) { message("Cannot open this screen", "The required app or settings screen is not available on this device."); }
    }
    private void message(String title, String body) {
        new AlertDialog.Builder(this).setTitle(title).setMessage(body).setPositiveButton("OK", null).show();
    }
    private LinearLayout card(LinearLayout parent, String title) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(18), dp(16), dp(18), dp(16));
        GradientDrawable background = new GradientDrawable(); background.setColor(CARD); background.setCornerRadius(dp(20));
        box.setBackground(background);
        LinearLayout.LayoutParams layout = new LinearLayout.LayoutParams(-1, -2);
        layout.bottomMargin = dp(14); parent.addView(box, layout);
        TextView label = text(title, 18, TEXT); label.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        label.setPadding(0, 0, 0, dp(10)); box.addView(label); return box;
    }
    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setTextColor(color);
        view.setGravity(Gravity.START); view.setTextDirection(View.TEXT_DIRECTION_LTR);
        view.setLineSpacing(dp(3), 1); view.setPadding(0, dp(4), 0, dp(4)); return view;
    }
    private void button(LinearLayout parent, String label, Runnable action) {
        TextView button = text(label, 14, ACCENT);
        button.setGravity(Gravity.CENTER); button.setMinHeight(dp(50));
        button.setPadding(dp(12), dp(12), dp(12), dp(12));
        GradientDrawable shape = new GradientDrawable(); shape.setColor(Color.rgb(28, 52, 64)); shape.setCornerRadius(dp(12));
        button.setBackground(shape); button.setFocusable(true); button.setOnClickListener(v -> action.run());
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2); params.topMargin = dp(10); params.bottomMargin = dp(8);
        parent.addView(button, params);
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    @Override protected void onResume() { super.onResume(); resumed = true; handler.post(refresh); }
    @Override protected void onPause() { resumed = false; handler.removeCallbacks(refresh); super.onPause(); }
    @Override protected void onDestroy() { stopPairing(); worker.shutdownNow(); super.onDestroy(); }
}
