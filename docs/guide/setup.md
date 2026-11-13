# Setup

## Android phone

The current APK requires Android 10 or later. The development device is a Galaxy A12 running Android 12; two-way call audio still needs device testing.

1. Install the signed SimHelp APK.
2. Open SimHelp and set it as the default phone app when requested.
3. Grant the call, phone-state, and SMS permissions shown by the app. Allow notifications if Android requests them.
4. For the no-root audio bridge, install and start Shizuku, complete its Wireless debugging setup, and authorize SimHelp.
5. Return to SimHelp and check its status messages. Shizuku may need restarting after the phone reboots.

App permission explanations are English. Android's own permission-dialog buttons and titles follow the device's system language.

## iPhone

1. Download a successful iOS build artifact from this private repository's Actions page.
2. Extract the ZIP to obtain the IPA.
3. Sign and install it using Sideloadly or another compatible tool.
4. Open SimHelp and grant local-network, Bluetooth, microphone, and contacts access as needed.

The Watch companion is excluded from the sideloaded IPA to avoid companion bundle-identifier errors when signing tools rewrite the iPhone app identifier. System-owned iOS dialog titles and buttons follow the iPhone language; app-supplied permission explanations are English.

## Pair the phones

1. Connect both phones to the same Wi-Fi, or connect the iPhone to the Android hotspot.
2. Complete Android setup and tap **Start pairing**.
3. In the iPhone app, select the local / VoWLAN setup and enter the pairing code.
4. If discovery does not find the phone, use the Android app's displayed address and pairing port.
5. If the code expires, start a new pairing session.

A saved pairing record does not prove that the connection is currently active.

## Check the connection

Send and receive a test SMS. Make a short call and confirm that both people can hear each other. Check incoming calls as well as outgoing calls. Audio bridge diagnostics report service health; they cannot confirm that the carrier call audio is usable.

If connection fails, check the shared network, iPhone local-network permission, Android permissions, and Shizuku authorization. Keep the Android foreground service running. Advanced relay or public TLS configurations require additional infrastructure and are not necessary for an initial local pairing test.
