package com.airsim.phonecontrol;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.widget.Toast;
import java.lang.ref.WeakReference;
import java.util.concurrent.Executors;
import java.util.function.BooleanSupplier;

/** Activity-owned dialogs, process-wide single-flight networking on a worker thread. */
final class AppUpdatePresenter {
    private static final AppUpdateSession SESSION = new AppUpdateSession();
    private static WeakReference<AppUpdatePresenter> foregroundOwner = new WeakReference<>(null);
    private static final java.util.concurrent.ExecutorService WORKER = Executors.newSingleThreadExecutor();
    private static final String NOTES_SEEN = "notes_seen", ATTEMPT = "attempt", NOTIFIED = "notified";
    private final WeakReference<Activity> owner;
    private final SharedPreferences preferences;
    private final BooleanSupplier idle;
    private final String version;
    private final long build;
    private final boolean standalone;
    private AlertDialog dialog;

    AppUpdatePresenter(Activity activity, BooleanSupplier idle) {
        owner = new WeakReference<>(activity);
        preferences = activity.getSharedPreferences("airsim-app-updates", Activity.MODE_PRIVATE);
        this.idle = idle;
        String name = ""; long code = 0;
        try {
            var info = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
            name = info.versionName == null ? "" : info.versionName; code = info.getLongVersionCode();
        } catch (Exception ignored) { /* Unknown versions must not offer upgrades. */ }
        version = name; build = code; standalone = RuntimeMode.isStandalone(activity);
    }

    String status() { return SESSION.status(); }

    boolean showStartupNotes(Runnable after) {
        Activity activity = liveOwner();
        if (activity == null || !AppUpdatePolicy.needsNotes(version + "#" + build,
                preferences.getString(NOTES_SEEN, ""))) return false;
        if (dialog != null) return true;
        showNotes(after);
        return true;
    }

    void showNotes(Runnable after) {
        Activity activity = liveOwner();
        if (activity == null || dialog != null) return;
        String notes = "• Fixed SIM subscription listening compatibility in Android 10 to avoid crash when calling higher version interface when starting Service. \n\n"
                + "• Report the device power for display by compatible iPhone widgets; the power will not be faked when there is no valid sampling. \n\n"
                + "• Companion with iPhone build 162 adds new widgets, unread text messages/missed call flags and experimental TLS public network pairing tutorial. \n\n"
                + "• Improved Shizuku SMS inbox compatibility; only the last 15 minutes of SMS will be forwarded for the first time, and the cursor will only be advanced for old SMS. \n\n"
                + "• U30Air client and call closing improvements require compatible devices; this APK does not install or update U30Air firmware. \n\n"
                + "• Feedback is still manually uploaded by the user; pairings and existing data are retained.";
        AlertDialog next = new AlertDialog.Builder(activity).setTitle("Updates to the current version ·" + version + "（" + build + "）")
                .setMessage(notes).setPositiveButton("knew", (ignored, which) -> {
                    preferences.edit().putString(NOTES_SEEN, version + "#" + build).apply();
                }).create();
        next.setCancelable(false);
        next.setOnDismissListener(ignored -> { dialog = null; if (liveOwner() != null) after.run(); });
        dialog = next; next.show();
    }

    void foreground() {
        foregroundOwner = new WeakReference<>(this);
        if (liveOwner() == null || !idle.getAsBoolean() || dialog != null) return;
        if (SESSION.pending(preferences.getString(NOTIFIED, "")) != null) presentPending();
        else check(false);
    }

    void check(boolean manual) {
        Activity activity = liveOwner();
        if (activity == null || !SESSION.begin(preferences.getLong(ATTEMPT, 0), System.currentTimeMillis(), manual)) return;
        foregroundOwner = new WeakReference<>(this);
        preferences.edit().putLong(ATTEMPT, System.currentTimeMillis()).apply();
        if (manual) Toast.makeText(activity, "Checking for app updates…", Toast.LENGTH_SHORT).show();
        WORKER.execute(() -> {
            AppUpdatePolicy.Candidate candidate = null;
            String message;
            try {
                candidate = AppUpdatePolicy.select(AppReleaseClient.fetch(), version, build, standalone);
                message = candidate == null ? "No public app version newer than the current one found" : "Discover new versions of apps" + candidate.version();
            } catch (Exception ignored) {
                message = "Check failed, please check the network or try again later; this does not mean you are up to date.";
            }
            SESSION.finish(new AppUpdateSession.Result(candidate, message, manual));
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                AppUpdatePresenter current = foregroundOwner.get();
                if (current != null) current.presentPending();
            });
        });
    }

    private void presentPending() {
        Activity activity = liveOwner();
        AppUpdateSession.Result result = SESSION.pending(preferences.getString(NOTIFIED, ""));
        if (activity == null || !idle.getAsBoolean() || dialog != null || result == null) return;
        AppUpdatePolicy.Candidate candidate = result.candidate();
        String message = result.message();
        if (candidate != null) message += "\n\n" + candidate.notes()
                + "\n\n will open the release page of this application, please select" + (standalone ? "Standalone APK" : "AVF Bridge APK")
                + ". Only data with the same package name and signature can be retained for overwriting and upgrading; Debug/third-party re-signed packages may not be directly overwritten, so please do not uninstall them first to bypass signature errors. It will not download or install automatically.";
        AlertDialog.Builder builder = new AlertDialog.Builder(activity).setTitle("Apply updates").setMessage(message)
                .setNegativeButton("closure", null);
        if (candidate != null) builder.setPositiveButton("View release page", (ignored, which) -> {
            try { activity.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(candidate.page()))); }
            catch (android.content.ActivityNotFoundException ignoredError) {
                Toast.makeText(activity, "There is no browser that can open the web page", Toast.LENGTH_LONG).show();
            }
        });
        AlertDialog next = builder.create();
        next.setOnDismissListener(ignored -> { dialog = null; });
        dialog = next; next.show();
        if (candidate != null) preferences.edit().putString(NOTIFIED, candidate.identity()).apply();
        SESSION.consumed(result);
    }

    void pause() {
        if (foregroundOwner.get() == this) foregroundOwner.clear();
        if (dialog != null) dialog.dismiss();
    }

    void destroy() {
        if (foregroundOwner.get() == this) foregroundOwner.clear();
        owner.clear();
        if (dialog != null) { dialog.setOnDismissListener(null); dialog.dismiss(); dialog = null; }
    }

    private Activity liveOwner() {
        Activity activity = owner.get();
        return activity == null || activity.isFinishing() || activity.isDestroyed() ? null : activity;
    }
}
