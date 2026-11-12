package com.airsim.phonecontrol;

/** Android SmsManager sent-result codes, including the hidden RIL/modem range. */
final class SMSResultCode {
    private SMSResultCode() {}

    static String describe(int code) {
        return switch (code) {
            case -1 -> "未知（-1）";
            case 0 -> "成功（0）";
            case 1 -> "通用失败（1）";
            case 2 -> "无线电关闭（2）";
            case 3 -> "空 PDU（3）";
            case 4 -> "无服务（4）";
            case 5 -> "超出限制（5）";
            case 6 -> "FDN 检查失败（6）";
            case 7 -> "短码不允许（7）";
            case 8 -> "短码被永久拒绝（8）";
            case 9 -> "无线电不可用（9）";
            case 10 -> "网络拒绝（10）";
            case 11 -> "参数无效（11）";
            case 12 -> "状态无效（12）";
            case 13 -> "内存不足（13）";
            case 14 -> "短信格式无效（14）";
            case 15 -> "系统错误（15）";
            case 16 -> "调制解调器错误（16）";
            case 17 -> "网络错误（17）";
            case 18 -> "编码错误（18）";
            case 19 -> "SMSC 地址无效（19）";
            default -> "未知（" + code + "）";
        };
    }

    static boolean isModemError(int code) {
        return code == 16;
    }
}
