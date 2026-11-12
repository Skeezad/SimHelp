package android.os;

public final class Looper {
    private Looper() {}

    public static Looper getMainLooper() { return new Looper(); }
}
