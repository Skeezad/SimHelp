package com.simhelp.phonecontrol;

/** Feedback requires the explicit settings-page upload action. */
final class FeedbackUploadPolicy {
    private FeedbackUploadPolicy() {}
    static boolean allows(String trigger) { return "manual".equals(trigger); }
}
