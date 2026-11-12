package android.telephony;
public class SubscriptionInfo {
    public int slot;
    public int subscriptionId;
    public boolean embedded;
    public String number = "";
    public int getSimSlotIndex() { return slot; }
    public int getSubscriptionId() { return subscriptionId; }
    public boolean isEmbedded() { return embedded; }
    public CharSequence getCarrierName() { return "Carrier"; }
    public String getNumber() { return number; }
}
