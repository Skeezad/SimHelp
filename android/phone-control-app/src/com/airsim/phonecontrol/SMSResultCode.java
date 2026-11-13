package com.airsim.phonecontrol;

/** Android SmsManager sent-result codes, including the hidden RIL/modem range. */
final class SMSResultCode {
    private SMSResultCode() {}

    static String describe(int code) {
        return switch (code) {
            case -1 -> "Unknown (-1)";
            case 0 -> "Success(0)";
            case 1 -> "generic failure(1)";
            case 2 -> "radio off(2)";
            case 3 -> "Empty PDU (3)";
            case 4 -> "No service (4)";
            case 5 -> "Limit exceeded (5)";
            case 6 -> "FDN check failed (6)";
            case 7 -> "Short codes not allowed (7)";
            case 8 -> "Shortcode is permanently rejected (8)";
            case 9 -> "Radio not available (9)";
            case 10 -> "Network Denied (10)";
            case 11 -> "Invalid parameter (11)";
            case 12 -> "Invalid status (12)";
            case 13 -> "Out of memory (13)";
            case 14 -> "Invalid SMS format (14)";
            case 15 -> "System Error (15)";
            case 16 -> "Modem error (16)";
            case 17 -> "Network error(17)";
            case 18 -> "Encoding error (18)";
            case 19 -> "Invalid SMSC address (19)";
            default -> "unknown(" + code + "）";
        };
    }

    static boolean isModemError(int code) {
        return code == 16;
    }
}
