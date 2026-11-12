package android.media;

public final class AudioAttributes {
    public static boolean failSetup;
    public static final int USAGE_VOICE_COMMUNICATION = 2;
    public static final int CONTENT_TYPE_SPEECH = 1;
    public static final class Builder {
        public Builder() {
            if (failSetup) throw new IllegalStateException("playback attributes setup failed");
        }
        public Builder setUsage(int usage) { return this; }
        public Builder setContentType(int type) { return this; }
        public AudioAttributes build() { return new AudioAttributes(); }
    }
}
