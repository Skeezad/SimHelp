package com.airsim.phonecontrol;

import android.accessibilityservice.AccessibilityService;
import android.content.ComponentName;
import android.content.Context;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayDeque;
import java.util.Locale;
import java.util.Set;

/**
 * Xiaomi/HyperOS sometimes asks "是否发送短信" before the modem sends a
 * non-default-SMS-app message. This service clicks only the positive button,
 * only while an AirSIM SmsManager attempt is pending. It never logs or stores
 * message text, numbers, or arbitrary screen content.
 */
public final class SmsConfirmationAccessibilityService extends AccessibilityService {
    private static final Set<String> ALLOWED_PACKAGES = Set.of(
            "com.android.mms",
            "com.miui.smsextra",
            "com.miui.securitycenter",
            "com.android.phone",
            "com.miui.phone",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.lbe.security.miui",
            "com.miui.securitycore",
            "com.android.systemui",
            "com.miui.systemui",
            "com.android.settings"
    );
    private static final String[] DIALOG_MARKERS = {
            "发送短信", "发送此短信", "是否发送", "确认发送", "短信发送"
    };
    private static final String[] POSITIVE_LABELS = {
            "发送", "发送短信", "确认发送", "允许发送", "允许", "同意",
            "同意并发送", "确定", "始终允许", "好的", "OK", "Send", "Allow"
    };
    private static final long CLICK_DEBOUNCE_MS = 800L;
    private long lastClickAt;

    static boolean isEnabled(Context context) {
        String enabled = Settings.Secure.getString(context.getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null) return false;
        ComponentName component = new ComponentName(context, SmsConfirmationAccessibilityService.class);
        return enabled.contains(component.flattenToString())
                || enabled.contains(component.flattenToShortString());
    }

    @Override protected void onServiceConnected() {
        super.onServiceConnected();
        BridgeLog.info("sms_accessibility_connected");
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || !SmsSendConfirmationGate.isArmed()) return;
        int type = event.getEventType();
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                && type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return;
        CharSequence packageName = event.getPackageName();
        if (packageName == null
                || !ALLOWED_PACKAGES.contains(packageName.toString().toLowerCase(Locale.ROOT))) {
            BridgeLog.info("sms_accessibility_ignored_package="
                    + (packageName == null ? "none" : packageName));
            return;
        }
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;
        String screen = collectText(root);
        if (!containsMarker(screen)) {
            BridgeLog.info("sms_accessibility_no_marker package=" + packageName);
            return;
        }
        long now = android.os.SystemClock.elapsedRealtime();
        if (now - lastClickAt < CLICK_DEBOUNCE_MS) return;
        AccessibilityNodeInfo button = findPositiveButton(root);
        if (button == null) {
            BridgeLog.info("sms_accessibility_no_button package=" + packageName);
            return;
        }
        if (click(button)) {
            lastClickAt = now;
            BridgeLog.info("sms_confirm_clicked label=positive");
        } else {
            BridgeLog.info("sms_accessibility_click_failed package=" + packageName);
        }
    }

    private static boolean containsMarker(String text) {
        String compact = text.replaceAll("[\\s\\u00A0]+", "");
        for (String marker : DIALOG_MARKERS) {
            if (compact.contains(marker)) return true;
        }
        return false;
    }

    private static String collectText(AccessibilityNodeInfo root) {
        StringBuilder value = new StringBuilder();
        ArrayDeque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        int visited = 0;
        while (!queue.isEmpty() && visited++ < 200 && value.length() < 2_000) {
            AccessibilityNodeInfo node = queue.removeFirst();
            CharSequence text = node.getText();
            if (text != null) value.append(text).append(' ');
            CharSequence description = node.getContentDescription();
            if (description != null) value.append(description).append(' ');
            for (int index = 0; index < node.getChildCount(); index++) {
                AccessibilityNodeInfo child = node.getChild(index);
                if (child != null) queue.add(child);
            }
        }
        return value.toString();
    }

    private static AccessibilityNodeInfo findPositiveButton(AccessibilityNodeInfo root) {
        ArrayDeque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        int visited = 0;
        while (!queue.isEmpty() && visited++ < 200) {
            AccessibilityNodeInfo node = queue.removeFirst();
            if ((isPositiveLabel(node.getText())
                    || isPositiveLabel(node.getContentDescription()))
                    && hasClickableAncestor(node)) {
                return node;
            }
            for (int index = 0; index < node.getChildCount(); index++) {
                AccessibilityNodeInfo child = node.getChild(index);
                if (child != null) queue.add(child);
            }
        }
        return null;
    }

    private static boolean isPositiveLabel(CharSequence value) {
        if (value == null) return false;
        String label = value.toString().replaceAll("[\\s\\u00A0]+", "");
        for (String candidate : POSITIVE_LABELS) {
            if (candidate.equalsIgnoreCase(label)) return true;
        }
        String lower = label.toLowerCase(Locale.ROOT);
        return lower.startsWith("发送") || lower.startsWith("允许")
                || lower.startsWith("同意") || lower.startsWith("确定")
                || lower.startsWith("send") || lower.startsWith("allow");
    }

    private static boolean hasClickableAncestor(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo current = node;
        for (int depth = 0; current != null && depth < 5; depth++) {
            if (current.isClickable()) return true;
            current = current.getParent();
        }
        return false;
    }

    private static boolean click(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo current = node;
        for (int depth = 0; current != null && depth < 5; depth++) {
            if (current.isClickable() && current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true;
            }
            current = current.getParent();
        }
        return false;
    }

    @Override public void onInterrupt() {}
}
