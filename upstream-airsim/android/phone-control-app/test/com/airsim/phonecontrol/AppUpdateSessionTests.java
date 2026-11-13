package com.airsim.phonecontrol;

public final class AppUpdateSessionTests {
    public static void main(String[] args) {
        AppUpdateSession session = new AppUpdateSession();
        if (!session.begin(0, 100_000_000, false)) throw new AssertionError("first request");
        if (session.begin(0, 100_000_001, true)) throw new AssertionError("new Activity must share in-flight request");
        var candidate = new AppUpdatePolicy.Candidate("1.0.0", 100, "https://github.com/kai-wu-cortex/AirSIM/releases/tag/v1.0.0", "notes");
        var result = new AppUpdateSession.Result(candidate, "new version", false);
        session.finish(result);
        // Two UI consumers inspect the same process mailbox, without either owning the request.
        var oldActivity = session.pending("");
        var replacementActivity = session.pending("");
        if (oldActivity != result || replacementActivity != result) throw new AssertionError("recreation lost completed result");
        session.consumed(replacementActivity);
        if (session.pending("") != null) throw new AssertionError("acknowledged result repeated");
        if (session.begin(100_000_000, 100_000_002, false)) throw new AssertionError("recreated UI bypassed daily limit");
        if (!session.begin(100_000_000, 100_000_002, true)) throw new AssertionError("manual retry unavailable");
        var failure = new AppUpdateSession.Result(null, "check failed", true);
        session.finish(failure);
        if (session.pending("") != failure) throw new AssertionError("manual failure result lost on recreation");
        session.consumed(failure);
        session.finish(result);
        if (session.pending("1.0.0#100") != null) throw new AssertionError("auto update already notified");
        if (!session.status().equals("new version")) throw new AssertionError("last check state lost");
        System.out.println("AppUpdateSessionTests: recreation, single-flight, cooldown, manual failure and notification checks passed");
    }
}
