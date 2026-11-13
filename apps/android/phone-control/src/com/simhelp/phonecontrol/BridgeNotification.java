package com.simhelp.phonecontrol;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;

public final class BridgeNotification {
    public static final String CHANNEL = "airsim_bridge_status";
    public static final String GROUP = "airsim_services";
    private static final String CALL_CHANNEL = "airsim_incoming_calls_v2";
    public static final int WATCHDOG_ID = 5071;
    public static final int RECOVERY_ID = 5074;
    private static final int CALL_ID = 5072;
    public static final int VOWLAN_ID = 5073;
    private BridgeNotification() {}

    public static void createChannel(Context context) {
        NotificationChannel channel = new NotificationChannel(CHANNEL, "SimHelp Talking Bridge", NotificationManager.IMPORTANCE_LOW);
        channel.setSound(null, null);
        channel.enableVibration(false);
        context.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private static void createCallChannel(Context context) {
        NotificationChannel channel = new NotificationChannel(
                CALL_CHANNEL, "SimHelp incoming call (full screen)", NotificationManager.IMPORTANCE_MAX);
        // The iPhone is the primary ringer in remote_silent mode. Android still
        // needs a visible, actionable call surface when the phone is locked.
        channel.setSound(null, null);
        channel.enableVibration(false);
        context.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    public static Notification status(Context context, String detail) {
        createChannel(context);
        PendingIntent open = PendingIntent.getActivity(context, 0, new Intent(context, MainActivity.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle("SimHelp Talking Bridge")
                .setContentText(detail)
                .setSubText("Default card:" + DefaultCallAccount.selectedLabel(context))
                .setContentIntent(open)
                .setGroup(GROUP)
                .addAction(android.R.drawable.ic_menu_manage, "Switch default card",
                        CallNotificationActionReceiver.switchSimIntent(context))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
    }

    public static void notifyStatus(Context context, String detail) {
        createChannel(context);
        context.getSystemService(NotificationManager.class)
                .notify(WATCHDOG_ID, status(context, detail));
    }

    public static Notification terminalRecovery(Context context, Intent terminal) {
        createChannel(context);
        PendingIntent open = PendingIntent.getActivity(context, RECOVERY_ID, terminal,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle("SimHelp requires Linux VM recovery")
                .setContentText("Click to open Terminal to resume the connection")
                .setContentIntent(open)
                .addAction(android.R.drawable.ic_menu_view, "Open Terminal", open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
    }

    public static Notification vowlan(Context context, String detail) {
        createChannel(context);
        PendingIntent open = PendingIntent.getActivity(context, 2, new Intent(context, MainActivity.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle("SimHelp VoWLAN")
                .setContentText(detail)
                .setContentIntent(open)
                .setGroup(GROUP)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
    }

    public static void showCall(Context context, String callId, String direction,
                                String mode, String state, String number) {
        if (callId == null || callId.isEmpty() || "ended".equals(state) || "unknown".equals(state)) return;
        boolean incoming = "incoming".equals(direction) && "incoming".equals(state);
        if (incoming) createCallChannel(context);
        else createChannel(context);
        Intent screenIntent = new Intent(context, CallScreenActivity.class)
                .setData(Uri.parse("airsim-call://screen/" + Uri.encode(callId)))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
                        | Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(CallScreenActivity.EXTRA_CALL_ID, callId);
        PendingIntent screen = PendingIntent.getActivity(context, 1, screenIntent,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        String displayNumber = number == null ? "" : number.trim();
        String text = incoming
                ? (displayNumber.isEmpty()
                    ? "Unknown number · Can answer or reject directly"
                    : "You can answer or reject calls directly on Android")
                : "Call in progress · Click to view";
        Notification.Builder builder = new Notification.Builder(context, incoming ? CALL_CHANNEL : CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle(incoming
                        ? (displayNumber.isEmpty() ? "SimHelp incoming call" : displayNumber)
                        : "SimHelp calls")
                .setContentText(text)
                .setContentIntent(screen)
                .setCategory(Notification.CATEGORY_CALL)
                .setSubText(incoming
                        ? "SimHelp · " + (AppConfig.MODE_REMOTE_SILENT.equals(mode) ? "remote silence" : "local display") + "·Incoming calls"
                        : "SimHelp · Call")
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setOnlyAlertOnce(true);
        if (incoming) {
            builder.setPriority(Notification.PRIORITY_HIGH)
                    .setFullScreenIntent(screen, true)
                    .addAction(android.R.drawable.sym_action_call, "Answer",
                            CallNotificationActionReceiver.pendingIntent(context, callId, "answer"))
                    .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Reject",
                            CallNotificationActionReceiver.pendingIntent(context, callId, "reject"));
        } else {
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "hang up",
                    CallNotificationActionReceiver.pendingIntent(context, callId, "end"));
        }
        context.getSystemService(NotificationManager.class).notify(callId, CALL_ID, builder.build());
    }

    public static void clearCall(Context context, String callId) {
        context.getSystemService(NotificationManager.class).cancel(callId, CALL_ID);
    }
}
