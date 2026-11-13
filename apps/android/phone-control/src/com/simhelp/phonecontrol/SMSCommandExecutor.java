package com.simhelp.phonecontrol;

import android.Manifest;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Telephony;
import android.telephony.SmsManager;
import android.telephony.SubscriptionManager;

import java.util.ArrayList;
import java.util.UUID;

/** Executes an Agent SMS command through the selected Android SIM, not Telecom. */
public final class SMSCommandExecutor {
    private static final long SENT_TIMEOUT_MS = 45_000L;
    private static final String SEGMENT_EXTRA = "segment";

    interface PrivilegedSender {
        String send(String destination, String body, int subscriptionId);
    }

    interface RootSender {
        String send(String destination, String body, int subscriptionId);
    }

    private static volatile PrivilegedSender privilegedSender;
    private static volatile RootSender rootSender;

    static void setPrivilegedSender(PrivilegedSender sender) {
        privilegedSender = sender;
    }

    static void setRootSender(RootSender sender) {
        rootSender = sender;
    }

    private SMSCommandExecutor() {}

    static AgentCommandDispatcher.Result execute(Context context, AgentCommand command) {
        String destination = SMSPayloadPolicy.normalizeDestination(command.number);
        if (destination.isEmpty() || !SMSPayloadPolicy.validBody(command.message)) {
            return AgentCommandDispatcher.Result.failure("Invalid number or text message content");
        }
        if (context.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            return AgentCommandDispatcher.Result.failure("SimHelp lacks permission to send text messages; please allow text messages in Samsung app permissions");
        }
        if (!context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)) {
            return AgentCommandDispatcher.Result.failure("This device does not support system SMS sending");
        }

        try {
            int defaultSubscription = defaultSmsSubscription(context);
            int subscriptionID = defaultSubscription;
            if (!command.simAccount.isEmpty()) {
                subscriptionID = SubscriptionManager.INVALID_SUBSCRIPTION_ID;
                DefaultCallAccount.Snapshot slots = DefaultCallAccount.snapshot(context);
                if (!slots.error().isEmpty()) {
                    return AgentCommandDispatcher.Result.failure(slots.error());
                }
                for (DefaultCallAccount.Account account : slots.accounts()) {
                    if (command.simAccount.equals(account.key())) {
                        subscriptionID = account.subscriptionId();
                        break;
                    }
                }
                if (subscriptionID == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                    return AgentCommandDispatcher.Result.failure("The selected SMS card slot has been removed, please select again");
                }
            }
            if (subscriptionID == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                return AgentCommandDispatcher.Result.failure("Please select the default SMS SIM in Samsung SIM card settings");
            }
            // Arm before every sender path: Shizuku/root may run SmsManager in
            // another process, but the MIUI confirmation window is handled here.
            SmsSendConfirmationGate.arm(SENT_TIMEOUT_MS + 15_000L);
            RootSender root = rootSender;
            if (root != null) {
                String result = root.send(destination, command.message, subscriptionID);
                if (result != null && result.startsWith("ok:")) {
                    SmsSendConfirmationGate.disarm();
                    int segments = segments(result);
                    BridgeLog.info("sms_send_root accepted segments=" + segments);
                    return AgentCommandDispatcher.Result.success(segments);
                }
                BridgeLog.info("sms_send_root_fallback result="
                        + (result == null || result.isEmpty() ? "unknown" : result));
            }
            PrivilegedSender privileged = privilegedSender;
            if (privileged != null) {
                String result = privileged.send(destination, command.message, subscriptionID);
                if (result != null && result.startsWith("ok:")) {
                    SmsSendConfirmationGate.disarm();
                    int segments = segments(result);
                    BridgeLog.info("sms_send_shizuku accepted segments=" + segments);
                    return AgentCommandDispatcher.Result.success(segments);
                }
                BridgeLog.info("sms_send_shizuku_fallback result="
                        + (result == null || result.isEmpty() ? "unknown" : result));
            }
            BridgeLog.info("sms_send_path=system subscription=" + subscriptionID);
            SmsManager manager = managerForSubscription(context, subscriptionID);
            if (manager == null) {
                SmsSendConfirmationGate.disarm();
                return AgentCommandDispatcher.Result.failure("System SMS service is unavailable");
            }
            ArrayList<String> parts = manager.divideMessage(command.message);
            if (parts == null || parts.isEmpty()) {
                SmsSendConfirmationGate.disarm();
                return AgentCommandDispatcher.Result.failure("SMS segmentation failed");
            }

            SMSConfirmation confirmation = new SMSConfirmation(parts.size());
            String attemptID = UUID.randomUUID().toString();
            String trace = attemptID.substring(0, 8);
            String action = context.getPackageName() + ".SMS_SENT." + attemptID;
            String defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(context);
            BridgeLog.info("sms_send_started trace=" + trace + " segments=" + parts.size()
                    + " subscription=" + subscriptionID
                    + " default_subscription=" + defaultSubscription
                    + " default_sms_package=" + (defaultSmsPackage == null ? "none" : defaultSmsPackage));
            BroadcastReceiver receiver = new BroadcastReceiver() {
                @Override public void onReceive(Context ignored, Intent intent) {
                    if (action.equals(intent.getAction())) {
                        int segment = intent.getIntExtra(SEGMENT_EXTRA, -1);
                        int resultCode = getResultCode();
                        int modemError = intent.getIntExtra("errorCode", -1);
                        confirmation.record(segment, resultCode);
                        BridgeLog.info("sms_send_callback trace=" + trace + " segment=" + segment
                                + " result=" + resultCode
                                + " result_text=" + SMSResultCode.describe(resultCode)
                                + " modem_error=" + modemError);
                    }
                }
            };
            IntentFilter filter = new IntentFilter(action);
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                context.registerReceiver(receiver, filter);
            }
            ArrayList<PendingIntent> sentIntents = new ArrayList<>(parts.size());
            try {
                for (int index = 0; index < parts.size(); index++) {
                    Intent sent = new Intent(action).setPackage(context.getPackageName())
                            .putExtra(SEGMENT_EXTRA, index);
                    sentIntents.add(PendingIntent.getBroadcast(context, index, sent,
                            PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE));
                }
                if (parts.size() == 1) {
                    manager.sendTextMessage(destination, null, parts.get(0), sentIntents.get(0), null);
                } else {
                    manager.sendMultipartTextMessage(destination, null, parts, sentIntents, null);
                }
                SMSConfirmation.Outcome outcome = confirmation.await(SENT_TIMEOUT_MS);
                if (!outcome.complete()) {
                    SmsSendConfirmationGate.disarm();
                    BridgeLog.info("sms_send_timeout trace=" + trace + " confirmed="
                            + outcome.confirmedSegments() + " total=" + parts.size());
                    return AgentCommandDispatcher.Result.failure("Timeout waiting for the system SMS sending receipt; please confirm whether the SMS has been sent and do not try again immediately.");
                }
                if (!outcome.success()) {
                    SmsSendConfirmationGate.disarm();
                    int errorCode = outcome.errorCode();
                    BridgeLog.info("sms_send_rejected trace=" + trace + " result=" + errorCode
                            + " result_text=" + SMSResultCode.describe(errorCode));
                    String hint = SMSResultCode.isModemError(errorCode)
                            ? "; Please check the default SMS SIM and signal, and allow Xiaomi's SMS sending confirmation pop-up window" : "";
                    return AgentCommandDispatcher.Result.failure(
                            "System SMS failed to be sent (" + SMSResultCode.describe(errorCode) + hint + "）");
                }
                SmsSendConfirmationGate.disarm();
                BridgeLog.info("sms_send_confirmed trace=" + trace + " segments=" + parts.size());
                return AgentCommandDispatcher.Result.success(parts.size());
            } finally {
                SmsSendConfirmationGate.disarm();
                for (PendingIntent intent : sentIntents) intent.cancel();
                context.unregisterReceiver(receiver);
            }
        } catch (InterruptedException error) {
            SmsSendConfirmationGate.disarm();
            Thread.currentThread().interrupt();
            return AgentCommandDispatcher.Result.failure("The SMS sending was interrupted; please confirm whether the SMS has been sent and do not try again immediately.");
        } catch (RuntimeException error) {
            SmsSendConfirmationGate.disarm();
            BridgeLog.error("sms_send_failed", error);
            return AgentCommandDispatcher.Result.failure("Android SMS sending failed:" + error.getClass().getSimpleName());
        }
    }

    /** Public bridge for the VoBLE gateway; returns "ok:<segments>" or "error:<message>". */
    public static String sendFromVoBLE(
            Context context, String requestId, String number, String message, String simAccount) {
        AgentCommandDispatcher.Result result = execute(context,
                new AgentCommand(requestId, "send_sms", "", number, message, simAccount));
        return result.success() ? "ok:" + result.segments() : "error:" + result.error();
    }

    private static int segments(String result) {
        try { return Math.max(1, Integer.parseInt(result.substring(3))); }
        catch (NumberFormatException ignored) { return 1; }
    }

    private static int defaultSmsSubscription(Context context) {
        try {
            int subscription = SubscriptionManager.getDefaultSmsSubscriptionId();
            if (subscription != SubscriptionManager.INVALID_SUBSCRIPTION_ID) return subscription;
        } catch (RuntimeException ignored) {
            // Fall through to SmsManager for vendors that do not expose the
            // SubscriptionManager default to non-default SMS apps.
        }
        return SmsManager.getDefaultSmsSubscriptionId();
    }

    static SmsManager managerForSubscription(Context context, int subscriptionID) {
        if (Build.VERSION.SDK_INT >= 31) {
            SmsManager service = context.getSystemService(SmsManager.class);
            if (service != null) return service.createForSubscriptionId(subscriptionID);
        }
        return SmsManager.getSmsManagerForSubscriptionId(subscriptionID);
    }
}
