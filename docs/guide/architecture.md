# Architecture and compatibility

## Components

The Android phone owns the SIM and integrates with Android Telecom and SMS APIs. Its foreground services handle pairing, commands, state, and media. The iPhone provides the calling, messaging, contacts, and settings interface.

The no-root Android audio path uses a separately authorized Shizuku service. Android permission approval, a running Shizuku process, an authenticated network link, and working two-way carrier audio are distinct conditions.

## Connection paths

- **VoWLAN:** local-network control and audio between paired devices.
- **VoBLE:** Bluetooth control and audio paths where the device and configuration support them.
- **Cloud / relay:** optional remote services with their own credentials and deployment configuration.
- **Public TLS gateway:** an advanced, experimental direct connection through a trusted gateway.

Local pairing should be validated before enabling remote configurations. Optional forwarding features send data to the destinations configured by the user; they should be reviewed before enabling them.

## Compatibility identifiers

The folder layout and Java source namespaces use SimHelp. Some wire-protocol magic values, authentication domains, discovery prefixes, preference keys, and component configuration variables remain unchanged to preserve compatibility. These are implementation details rather than application branding.

The Android application ID remains `ir.simhelp.personal` so signed updates can replace the existing personal app. The signing certificate must also match. The iPhone signing tool may rewrite bundle identifiers; each embedded extension must retain a matching executable and compatible signing configuration.

## Current validation limits

The project has compilation and source checks. Galaxy A12 / Android 12 carrier-call audio has not been verified in a real call. Real-device checks must cover incoming and outgoing calls, audio in both directions, SMS, reconnects, and behavior after restarting the Android phone.

## Documentation

The guides under `docs/guide/` describe this personal build. Other technical documents and archived notes are reference material and can describe experimental or historical variants.
