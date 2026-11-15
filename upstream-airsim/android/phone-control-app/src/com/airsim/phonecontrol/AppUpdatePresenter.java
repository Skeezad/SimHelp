package com.airsim.phonecontrol;

import android.app.Activity;
import java.util.function.BooleanSupplier;

/** App update checks and release-note dialogs are disabled in this distribution. */
final class AppUpdatePresenter {
    AppUpdatePresenter(Activity activity, BooleanSupplier idle) {}
    String status() { return ""; }
    boolean showStartupNotes(Runnable after) { return false; }
    void showNotes(Runnable after) { after.run(); }
    void foreground() {}
    void check(boolean manual) {}
    void pause() {}
    void destroy() {}
}
