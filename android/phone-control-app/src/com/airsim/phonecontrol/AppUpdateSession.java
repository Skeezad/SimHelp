package com.airsim.phonecontrol;

/** Process-owned result mailbox: Activity recreation must not lose a throttled request. */
final class AppUpdateSession {
    record Result(AppUpdatePolicy.Candidate candidate, String message, boolean manual) {}
    private boolean checking;
    private Result result;
    private String status = "每天最多自动检查一次；与 Linux Agent 更新分开";
    synchronized boolean begin(long attempt, long now, boolean manual) {
        if (!AppUpdatePolicy.checkDue(attempt, now, manual, checking)) return false;
        checking = true;
        return true;
    }
    synchronized void finish(Result result) {
        checking = false; this.result = result; status = result.message();
    }
    synchronized Result pending(String notified) {
        if (result == null) return null;
        return result.manual() || (result.candidate() != null && !result.candidate().identity().equals(notified))
                ? result : null;
    }
    synchronized void consumed(Result result) { if (this.result == result) this.result = null; }
    synchronized String status() { return checking ? "正在检查应用更新…" : status; }
}
