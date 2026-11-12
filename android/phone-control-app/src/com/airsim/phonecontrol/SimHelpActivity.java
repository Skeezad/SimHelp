package com.airsim.phonecontrol;

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

/** Persian, no-root setup and pairing entry point. Never reports audio as tested
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
        page.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        page.setPadding(dp(22), dp(28), dp(22), dp(32));
        scroll.addView(page);
        setContentView(scroll);

        TextView brand = text("SimHelp", 34, TEXT);
        brand.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.setTextDirection(View.TEXT_DIRECTION_LTR);
        brand.setGravity(Gravity.RIGHT);
        page.addView(brand);
        page.addView(text("سیم‌کارت روی اندروید، تماس و پیام روی آیفون", 16, MUTED));
        TextView badge = text("نسخهٔ شخصی • بدون روت", 12, ACCENT);
        badge.setPadding(0, dp(12), 0, dp(18));
        page.addView(badge);

        LinearLayout device = card(page, "گوشی میزبان");
        device.addView(text(Build.MANUFACTURER + " " + Build.MODEL + " · Android " + Build.VERSION.RELEASE, 15, TEXT));
        device.addView(text("سازگاری صدای A12 هنوز با تماس واقعی تأیید نشده. آماده بودن پل صدا به معنی موفق بودن مکالمه نیست.", 13, MUTED));

        LinearLayout setup = card(page, "۱. آماده‌سازی اندروید");
        roleStatus = text("", 14, TEXT); setup.addView(roleStatus);
        button(setup, "انتخاب SimHelp به‌عنوان برنامهٔ تلفن", this::requestDialer);
        permissionStatus = text("", 14, TEXT); setup.addView(permissionStatus);
        button(setup, "اجازهٔ تماس و پیامک", this::requestNeededPermissions);
        bridgeStatus = text("", 14, TEXT); setup.addView(bridgeStatus);
        button(setup, "راه‌اندازی Shizuku", this::setupShizuku);
        setup.addView(text("در Shizuku، Wireless debugging را فعال و Pairing را انجام بده؛ سپس به SimHelp برگرد و دسترسی را تأیید کن. بعد از راه‌اندازی مجدد گوشی ممکن است تکرارش لازم باشد.", 13, MUTED));

        LinearLayout connect = card(page, "۲. اتصال آیفون");
        connect.addView(text("هر دو گوشی را به یک وای‌فای وصل کن یا آیفون را به هات‌اسپات اندروید وصل کن. در کلاینت آیفون، English و اتصال VoWLAN / Local را انتخاب کن.", 14, MUTED));
        peerStatus = text("", 14, TEXT); connect.addView(peerStatus);
        pairCode = text("— — — — — —", 30, ACCENT);
        pairCode.setGravity(Gravity.CENTER);
        pairCode.setTextDirection(View.TEXT_DIRECTION_LTR);
        pairCode.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        connect.addView(pairCode);
        pairDetail = text("برای دریافت کد، اتصال جدید را بزن.", 14, MUTED);
        pairDetail.setTextIsSelectable(true); connect.addView(pairDetail);
        expiry = text("", 12, MUTED); connect.addView(expiry);
        button(connect, "اتصال جدید به آیفون", this::startPairing);
        button(connect, "بستن پنجرهٔ اتصال", () -> { stopPairing(); pairCode.setText("— — — — — —"); pairDetail.setText("پنجرهٔ اتصال بسته شد."); });

        LinearLayout test = card(page, "۳. تست واقعی تماس");
        test.addView(text("پس از اتصال، با یک گوشی دیگر به سیم‌کارت A12 زنگ بزن. روی آیفون جواب بده و شنیده شدن صدا در هر دو جهت را بررسی کن. سپس تماس خروجی و یک پیامک آزمایشی را امتحان کن.", 14, TEXT));
        button(test, "بررسی پل صدا", this::checkAudio);
        button(test, "تنظیمات باتری برنامه", () -> open(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName()))));
        test.addView(text("آیفون: این IPA برای سایدلود است. تماس در پس‌زمینه و هنگام قفل بودن صفحه هنوز آزمایش نشده؛ برای تست اول اپ آیفون را باز نگه دار.", 13, MUTED));

        LinearLayout help = card(page, "ابزارها و راهنما");
        button(help, "تنظیمات فنی موتور AirSIM", () -> open(new Intent(this, MainActivity.class)));
        button(help, "راهنمای نصب و مجوز سورس", () -> new AlertDialog.Builder(this)
                .setTitle("SimHelp · نسخهٔ شخصی")
                .setMessage("این نسخه از موتور AirSIM استفاده می‌کند و برای استفادهٔ غیرتجاری آماده شده. ابزارهای فنی موتور فعلاً رابط اصلی پروژه را دارند.\n\nآیفون: IPA را با Sideloadly و حساب خودت نصب کن. Local / VoWLAN را انتخاب کن و کد همین صفحه را وارد کن. در صورت نیاز آدرس نمایش‌داده‌شده را دستی وارد کن.\n\nترافیک تماس و پیامک از شبکهٔ گوشی میزبان عبور می‌کند و هزینهٔ معمول اپراتور را دارد.\n\nhttps://github.com/kai-wu-cortex/AirSIM\nPolyForm Noncommercial 1.0.0\nفایل‌های LICENSE، NOTICE و THIRD_PARTY_NOTICES در APK موجودند.")
                .setPositiveButton("باشه", null).show());
        TextView footer = text("SimHelp 0.1 • بر پایهٔ AirSIM\nآزمایشی — تأیید تماس روی A12 در انتظار تست", 12, MUTED);
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
            message("نقش تلفن در دسترس نیست", "تنظیمات برنامه‌های پیش‌فرض گوشی را بررسی کن."); return;
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
        roleStatus.setText(isDialer() ? "✓ برنامهٔ تلفن انتخاب شده" : "○ برنامهٔ تلفن هنوز انتخاب نشده");
        permissionStatus.setText(missingPermissions().isEmpty() ? "✓ مجوزهای ضروری داده شده" : "○ تماس و پیامک به مجوز نیاز دارند");
        ShizukuBridgeManager bridge = ShizukuBridgeManager.get(this);
        ShizukuBridgeManager.StartupSnapshot snapshot = bridge.startupSnapshot();
        String state = !snapshot.installed() ? "○ Shizuku نصب نیست" : !snapshot.running() ? "○ Shizuku فعال نیست"
                : !snapshot.authorized() ? "○ منتظر اجازهٔ Shizuku" : bridge.privilegeConnected()
                ? "✓ دسترسی Shizuku برقرار است؛ صدای دوطرفه هنوز نیاز به تست دارد" : "○ در حال اتصال به سرویس صدا";
        bridgeStatus.setText(state);
        int peers = VoWLANPairingStore.records(this).size();
        peerStatus.setText(peers == 0 ? "هنوز آیفونی با این برنامه جفت نشده" : "✓ دستگاه جفت‌شده: " + peers + " · این عدد وضعیت آنلاین را نشان نمی‌دهد");
        if (pairingExpires > 0) {
            long seconds = Math.max(0, (pairingExpires - System.currentTimeMillis()) / 1000);
            expiry.setText(seconds > 0 ? "اعتبار کد: " + seconds + " ثانیه" : "اعتبار کد تمام شد؛ اتصال جدید را بزن.");
            if (seconds == 0) {
                stopPairing(); pairCode.setText("— — — — — —");
                pairDetail.setText("کد منقضی شد؛ برای تلاش دوباره اتصال جدید را بزن.");
                expiry.setText("کد قبلی معتبر نیست.");
            }
        }
    }

    private void startPairing() {
        if (!isDialer() || !missingPermissions().isEmpty()) {
            message("اول آماده‌سازی", "ابتدا برنامهٔ تلفن و مجوزهای تماس و پیامک را تأیید کن."); return;
        }
        stopPairing();
        final long generation = pairingGeneration;
        pairDetail.setText("در حال ایجاد اتصال محلی…");
        pairCode.setText("…");
        pairing = new PairingServer(this, new PairingServer.Listener() {
            @Override public void onStarted(String code, String address, long expiresAt) {
                runOnUiThread(() -> {
                    if (generation != pairingGeneration || isDestroyed()) return;
                    pairingExpires = expiresAt;
                    pairCode.setText(code);
                    pairDetail.setText("این کد را در آیفون وارد کن. آدرس اتصال دستی:\n" + address);
                    updateStatus();
                });
            }
            @Override public void onSucceeded(String ignored) {
                runOnUiThread(() -> {
                    if (generation != pairingGeneration || isDestroyed()) return;
                    stopPairing();
                    pairCode.setText("✓");
                    pairDetail.setText("جفت‌سازی انجام شد. حالا تماس و پیامک آزمایشی را بررسی کن.");
                    updateStatus();
                });
            }
            @Override public void onFailed(String ignored) {
                runOnUiThread(() -> {
                    if (generation != pairingGeneration || isDestroyed()) return;
                    stopPairing();
                    pairCode.setText("—");
                    pairDetail.setText("اتصال کامل نشد یا کد منقضی شد. شبکهٔ مشترک و باز بودن اپ آیفون را بررسی کن و دوباره تلاش کن.");
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
            runOnUiThread(() -> { if (!isDestroyed()) message("گزارش پل صدا", "این گزارش فنی جای تست شنیدن صدا در هر دو جهت را نمی‌گیرد.\n\n" + result); });
        });
    }

    private void open(Intent intent) {
        try { startActivity(intent); }
        catch (android.content.ActivityNotFoundException error) { message("امکان باز کردن نیست", "این بخش در دستگاه در دسترس نیست."); }
    }
    private void message(String title, String body) {
        new AlertDialog.Builder(this).setTitle(title).setMessage(body).setPositiveButton("باشه", null).show();
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
        view.setGravity(Gravity.RIGHT); view.setTextDirection(View.TEXT_DIRECTION_FIRST_STRONG_RTL);
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
