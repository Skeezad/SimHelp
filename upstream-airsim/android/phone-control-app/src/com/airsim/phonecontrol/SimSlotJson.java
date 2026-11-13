package com.airsim.phonecontrol;

import android.content.Context;
import android.telephony.SmsManager;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Android-only JSON adapter for the paired iPhone's SIM selector. Kept separate
 * from DefaultCallAccount so the JVM account tests do not need org.json.
 * The list is display metadata only; identifiers are opaque Telecom handles and
 * numbers are never logged or persisted by this class.
 */
public final class SimSlotJson {
    private SimSlotJson() {}

    public static JSONArray slots(Context context) {
        JSONArray values = new JSONArray();
        try {
            DefaultCallAccount.Snapshot snapshot = DefaultCallAccount.snapshot(context);
            if (!snapshot.error().isEmpty()) return values;
            String selected = DefaultCallAccount.selectedKey(context);
            for (DefaultCallAccount.Account account : snapshot.accounts()) {
                values.put(new JSONObject()
                        .put("id", account.key())
                        .put("label", account.label())
                        .put("number", account.number())
                        .put("default", account.key().equals(selected))
                        .put("slot_index", account.slotIndex())
                        .put("sub_id", account.subscriptionId())
                        .put("carrier_name", account.carrierName())
                        .put("is_embedded", account.embedded())
                        .put("is_default_voice", account.defaultVoice())
                        .put("is_default_sms", account.defaultSms()
                                || account.subscriptionId() == SmsManager.getDefaultSmsSubscriptionId()));
            }
        } catch (RuntimeException | org.json.JSONException ignored) {
            // A missing permission or OEM restriction leaves the selector hidden.
        }
        return values;
    }
}
