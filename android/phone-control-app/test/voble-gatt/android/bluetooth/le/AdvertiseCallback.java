package android.bluetooth.le;
public class AdvertiseCallback {
    public static final int ADVERTISE_FAILED_DATA_TOO_LARGE = 1;
    public void onStartSuccess(AdvertiseSettings settings) {}
    public void onStartFailure(int error) {}
}
