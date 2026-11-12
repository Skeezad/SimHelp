package android.telecom;

public final class DisconnectCause {
    private final int code;
    public DisconnectCause(int code) { this.code = code; }
    public int getCode() { return code; }
}
