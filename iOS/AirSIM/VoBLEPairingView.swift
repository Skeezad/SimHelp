import SwiftUI

struct VoBLEPairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingUnpairConfirmation = false
    @State private var unpairing = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: stateSymbol)
                        .font(.title2)
                        .foregroundStyle(stateColor)
                        .frame(width: 42, height: 42)
                        .background(stateColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stateTitle).font(.headline)
                        Text(stateDetail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let identity = model.voble.authenticatedIdentity {
                    LabeledContent("Certified Agent", value: identity)
                }
                if let message = model.voble.errorMessage, !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Bluetooth connection")
            } footer: {
                Text("Bluetooth mode is independent of VoWLAN and Cloud Relay; dialing control or call audio will not be enabled until certification is completed.")
            }

            if let sas = model.voble.pendingSAS {
                Section("Check security code") {
                    Text(sas)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Bluetooth Pairing security code \(sas)")
                    Text("Verify that the six-digit number matches what Android SimHelp displays.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("The numbers match and pairing is completed.", systemImage: "checkmark.shield.fill") {
                        model.voble.confirmPairing()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel this match", role: .cancel) {
                        model.voble.cancelPairing()
                    }
                }
            }

            if !model.voble.discoveredPeers.isEmpty {
                Section("Discovered Android Agent") {
                    ForEach(model.voble.discoveredPeers) { peer in
                        Button {
                            model.vobleHub.connect(peer)
                        } label: {
                            HStack {
                                Label(peer.name, systemImage: "smartphone")
                                Spacer()
                                Text("\(peer.signal) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    model.vobleHub.start()
                    model.vobleHub.radio.rescan()
                }
                if model.voble.authenticatedIdentity != nil {
                    Button("Cancel VoBLE pairing", systemImage: "trash", role: .destructive) {
                        showingUnpairConfirmation = true
                    }
                    .disabled(unpairing)
                } else if model.voble.recoverableIdentity != nil,
                          case .failed = model.voble.state {
                    Button("Clear old credentials for the machine and rescan", systemImage: "arrow.counterclockwise") {
                        model.voble.clearLocalCredentialAndRetry()
                    }
                }
            }
        }
        .navigationTitle("Bluetooth Agent")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.vobleHub.start() }
        .confirmationDialog(
            "Delete VoBLE credentials on iPhone and Android simultaneously?",
            isPresented: $showingUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpair", role: .destructive) {
                unpairing = true
                Task {
                    defer { unpairing = false }
                    try? await model.voble.unpairCurrentPeer()
                }
            }
            Button("keep pairing", role: .cancel) {}
        } message: {
            Text("The six-digit security code needs to be rechecked after cancellation. VoWLAN and cloud configurations will not be affected.")
        }
    }

    private var stateTitle: String {
        switch model.vobleHub.pairingState {
        case .stopped: "Not started yet"
        case .bluetoothUnavailable: "Bluetooth is not available"
        case .scanning: "Looking for Android Agent"
        case .connecting: "Connecting"
        case .connected: "Connected, discovering services"
        case .authenticating: "Application layer authentication in progress"
        case .ready: "Bluetooth call is ready"
        case .failed: "Connection failed"
        }
    }

    private var stateDetail: String {
        switch model.vobleHub.pairingState {
        case .ready: "Control channel authenticated; audio channel will be started on call"
        case .failed(let message): message
        case .bluetoothUnavailable: "Please turn on Bluetooth in system settings and allow SimHelp access"
        default: "Please keep Android SimHelp running and enable Bluetooth mode"
        }
    }

    private var stateSymbol: String {
        switch model.vobleHub.pairingState {
        case .ready: "checkmark.circle.fill"
        case .failed, .bluetoothUnavailable: "exclamationmark.triangle.fill"
        case .stopped: "wave.3.right.circle"
        default: "wave.3.right"
        }
    }

    private var stateColor: Color {
        switch model.vobleHub.pairingState {
        case .ready: .green
        case .failed, .bluetoothUnavailable: .orange
        case .stopped: .secondary
        default: .blue
        }
    }
}
