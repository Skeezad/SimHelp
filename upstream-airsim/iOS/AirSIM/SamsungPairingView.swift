import SwiftUI

struct SamsungPairingView: View {
    /// This toggle only controls whether Relay/APNs registration is written.
    /// It never changes the media connection mode.
    static var defaultLocalPairingOnly: Bool { !CloudSignalingPreference.isEnabled() }
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var localPairingOnly = SamsungPairingView.defaultLocalPairingOnly
    @StateObject private var browser = SamsungPairingBrowser()
    @State private var code = ""
    @State private var pairingServiceID: String?
    @State private var message = ""
    enum Method { case automatic, privateIP, publicDomain }
    @State private var method: Method = .automatic
    private var manual: Bool { method != .automatic }
    private var usesTLS: Bool { method == .publicDomain }
    @State private var host = ""
    @State private var port = ""
    @State private var controlPort = "443"
    @State private var pcmPort = "7593"
    @State private var pairingTask: Task<Void, Never>?
    @State private var isVisible = false

    init(initialMethod: Method = .automatic) {
        _method = State(initialValue: initialMethod)
        _port = State(initialValue: initialMethod == .publicDomain ? "9443" : "")
    }

    var body: some View {
        Form {
            Section {
              DisclosureGroup("Cloud notification for this pairing") {
                Toggle(isOn: $localPairingOnly) {
                    Label("Only this pairing will not be written to the cloud.", systemImage: "wifi")
                }
                .disabled(pairingServiceID != nil || RelayEgressGate.shared.isBlocked)
                .accessibilityIdentifier("localPairingOnly")
                Text(localPairingOnly
                     ? "This pairing only writes the VoWLAN key, not the Relay/APNs. The current call media mode will not be changed."
                     : "Additional Relay/APNs are written for this pairing; it is only used for notification and will not change the current call media mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
              }
            }

            Section("Connection steps") {
                if usesTLS {
                    Label("The NAS or router has been configured for TLS forwarding with a valid certificate", systemImage: "lock.shield")
                    Label("Temporarily enable the pairing portal and close it after completion", systemImage: "network")
                } else {
                    Label("Let Android and this machine connect to the same Wi-Fi", systemImage: "wifi")
                    Label("You can also connect the machine to Android mobile hotspots", systemImage: "personalhotspot")
                }
                Label("Click "Start One-time Pairing" in the Android App", systemImage: "key")
            }

            Section("Pairing method") {
                Picker("Pairing method", selection: $method) {
                    Text("autodiscover").tag(Method.automatic)
                    Text("Private IP").tag(Method.privateIP)
                    Text("Public domain name").tag(Method.publicDomain)
                }
                .pickerStyle(.menu)
                .disabled(pairingServiceID != nil)
            }

            if usesTLS {
                Section {
                    RemoteDirectGuideEntry(context: .firstPairing)
                }
            }

            if manual {
                Section {
                    TextField(usesTLS ? "HTTPS domain name, such as phone.example.com" : "Android IPv4, such as 192.168.1.2 or 100.64.1.2", text: $host)
                        .keyboardType(usesTLS ? .URL : .decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("manualPairingHost")
                    TextField(usesTLS ? "HTTPS pairing port, for example 9443" : "Android pairing port", text: $port)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("manualPairingPort")
                    if usesTLS {
                        TextField("HTTPS control port", text: $controlPort).keyboardType(.numberPad)
                            .accessibilityIdentifier("publicPairingControlPort")
                        TextField("TLS audio port", text: $pcmPort).keyboardType(.numberPad)
                            .accessibilityIdentifier("publicPairingPCMPort")
                    }
                    codeField
                    Button("Connect and encrypt pairing", systemImage: "lock.shield") {
                        pairingTask = Task { await pairManually() }
                    }
                    .disabled(code.count != 6 || host.isEmpty || port.isEmpty || pairingServiceID != nil)
                    if pairingServiceID != nil { ProgressView("Connecting and authenticating...") }
                } header: { Text(usesTLS ? "Public domain name matching (experimental · HTTPS)" : "Manual address pairing") } footer: {
                    if usesTLS {
                        Text("Enter the domain name without https:// or path. The three ports are all TLS ports provided by the NAS; the pairing port is forwarded to the Android pairing window, and the control and audio are forwarded separately. The certificate must be trustworthy and match the domain name. Plain text public network connection or skipping certificate verification is not supported. No need to turn on AirSIM cloud mode.")
                    } else {
                      Text("First open the one-time pairing window on Android and fill in the pairing port on this page, not the ADB or call port. When using Tailscale, fill in Android's Tailscale IPv4. Both ends must be connected and allow mutual access; there is no need to enable SimHelp cloud mode."
                        + "If the LAN uses a special network segment (such as 30.0.0.0/8), first add the network segment in Settings → Connections and Devices → LAN and VPN. After pairing select VoWLAN or automatic connection mode.")
                    }
                }
                .disabled(pairingServiceID != nil)
            } else {
              Section("Discovered devices") {
                if browser.services.isEmpty {
                    HStack {
                        ProgressView()
                        Text(browser.stateText).foregroundStyle(.secondary)
                    }
                }
                ForEach(browser.services) { service in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(service.displayName, systemImage: "iphone.radiowaves.left.and.right")
                            .font(.headline)
                        codeField
                        Button("Encrypted pairing", systemImage: "lock.shield") {
                            pairingTask = Task { await pair(service) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(code.count != 6 || pairingServiceID != nil)
                    }
                    .padding(.vertical, 4)
                }
                Button("Rescan", systemImage: "arrow.clockwise") {
                    browser.restart()
                }
                .disabled(pairingServiceID != nil)
                Text("Please open the one-time pairing window on Android and allow local network access on iPhone. The scan will be rescanned when returning to the app or switching back to auto-discovery; manual addresses may be used for router isolation or VPNs that do not support broadcasts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
              }
            }

            if !message.isEmpty {
                Section("result") { Text(message) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(usesTLS ? "Public domain name matching · Experimental" : manual ? "Manual address pairing" : "Automatically discover pairs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isVisible = true
            if RelayEgressGate.shared.isBlocked { localPairingOnly = true }
            if !manual { browser.start() }
        }
        .onChange(of: method) { value in
            if value != .automatic { browser.stop() } else { browser.start() }
            host = ""
            port = value == .publicDomain ? "9443" : ""
            code = ""
            message = ""
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                browser.stop()
            } else if isVisible, phase == .active, !manual, pairingServiceID == nil {
                browser.restart()
            }
        }
        .onDisappear {
            isVisible = false
            browser.stop()
            pairingTask?.cancel()
        }
    }

    private var codeField: some View {
        TextField("6-digit verification code displayed by Android", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .onChange(of: code) { value in
                code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
            }
    }

    @MainActor
    private func pairManually() async {
        pairingServiceID = "manual"
        message = "Connecting Android pairing window..."
        defer { pairingServiceID = nil }
        do {
            let address = try SamsungManualPairingAddress(host: host, port: port, usesTLS: usesTLS,
                controlPort: controlPort, pcmPort: pcmPort)
            message = try await VoIPPushController.shared.performAndroidPairing(localOnly: localPairingOnly) { registration in
                let result = try await SamsungPairingClient.pairManually(address: address, code: code, registration: registration)
                try Task.checkCancellation()
                try await model.completeLocalPairing(agentID: result.route.agentID,
                    registration: registration, endpoint: result.route.endpoint,
                    clockOffset: result.clockOffset)
                if address.usesTLS {
                    do {
                        try await model.configureRemoteDirect(agentID: result.route.agentID, route: result.route)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        return "Android encrypted pairing is successful, but the public network control entrance has not passed device authentication and the domain name route is not saved. Please check the control port forwarding and try again in ‘Self-created domain name direct connection’: \(error.localizedDescription)"
                    }
                    if !localPairingOnly { model.setCloudSignalingEnabled(true) }
                    return "The public domain name has been paired successfully, and the identities of the control portal and the device have been verified. Available when VoWLAN or Auto mode is selected and this device is selected; the audio port needs to be verified during an actual call."
                }
                try await model.vowlan.installManualRoute(result.route)
                if !localPairingOnly { model.setCloudSignalingEnabled(true) }
                // Tailscale/5G can need a moment before the control port is
                // reachable after the pairing window closes.
                for attempt in 0..<3 {
                    if model.vowlan.availability.isOnlineForDisplay {
                        return "Pairing is successful and the direct connection gateway has been authenticated. Select VoWLAN or automatic connection mode for calls and text messages."
                    }
                    guard attempt < 2 else { break }
                    try? await Task.sleep(for: .milliseconds(400))
                    await model.vowlan.probeNow()
                }
                return "Pairing is successful, the address has been saved, but the direct gateway is temporarily unreachable. Please check network, Tailscale access rules and Android PCM bridge; no fallback writes to Relay."
            }
        } catch is CancellationError {
            message = "Connection canceled"
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func pair(_ service: SamsungPairingService) async {
        pairingServiceID = service.id
        message = localPairingOnly
            ? "Encrypting and writing VoWLAN local key..."
            : "Encrypting and writing to Android Agent…"
#if DEBUG
        print("[SimHelp Pair] claim_started session=\(service.sessionID)")
#endif
        defer { pairingServiceID = nil }
        do {
            message = try await VoIPPushController.shared.performAndroidPairing(
                localOnly: localPairingOnly
            ) { registration in
                let paired = try await SamsungPairingClient.pairDevice(
                        service: service,
                        code: code,
                        registration: registration
                    )
                try await model.completeLocalPairing(agentID: paired.agentID, registration: registration)
                if !localPairingOnly { model.setCloudSignalingEnabled(true) }
                return model.localDevices.api(for: paired.agentID) == nil
                    ? "Encrypted pairing has been written into Android and is awaiting call gateway authentication; no available routes have been established yet." : paired.message
            }
#if DEBUG
            print("[SimHelp Pair] claim_completed session=\(service.sessionID)")
#endif
        } catch is CancellationError {
            message = "Connection canceled"
        } catch {
            message = "Pairing failed: \(error.localizedDescription)"
#if DEBUG
            print("[SimHelp Pair] claim_failed session=\(service.sessionID) error=\(String(describing: type(of: error)))")
#endif
        }
    }
}


/// Contextual help only: reading the guide never writes pairing or route settings.
enum RemoteDirectGuideContext: String, CaseIterable, Identifiable {
    case firstPairing = "First public network pairing"
    case existingDevice = "Paired device"
    var id: Self { self }
}

struct RemoteDirectGuideEntry: View {
    let context: RemoteDirectGuideContext
    @State private var showingGuide = false
    @State private var detent: PresentationDetent = .large

    var body: some View {
        Button {
            detent = .large
            showingGuide = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tutorial").foregroundStyle(.primary)
                    Text("Preparation conditions, port forwarding and pairing steps")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("remoteDirectGuide")
        .sheet(isPresented: $showingGuide) {
            RemoteDirectGuideView(context: context)
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)
        }
    }
}

struct RemoteDirectGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var context: RemoteDirectGuideContext
    @State private var copied = false
    private let embedded: Bool

    init(context: RemoteDirectGuideContext, embedded: Bool = false) {
        self.embedded = embedded
        _context = State(initialValue: context)
    }

    private var firstPairing: Bool { context == .firstPairing }

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
            Form {
                Section {
                    Label("Experimental features", systemImage: "flask")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Connect Android via your own domain name, no SimHelp Relay required. Real public network pairing and two-way audio are still waiting for acceptance by the real machine.")
                    Picker("Usage scenarios", selection: $context) {
                        ForEach(RemoteDirectGuideContext.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Before you start") {
                    requirement("New iPhone App", symbol: "iphone",
                        detail: "A version containing this experimental feature is required. Just use the version of Android that already supports one-time pairing, VoWLAN and PCM.")
                    requirement("Domain name and trusted certificate", symbol: "lock.shield",
                        detail: "For example phone.example.com. The certificate must match the domain name and has not expired. Skipping certificate verification is not supported.")
                    requirement("TLS gateway accessible from the outside world", symbol: "network",
                        detail: "The NAS or soft router needs to have inbound public IPv4 or IPv6 and be able to access Android from a trusted private network. Merely configuring DDNS does not mean being able to penetrate carrier NAT.")
                    DisclosureGroup("What should I do if there is no public network entrance?") {
                        Text("You can continue to use your existing private IP/Tailscale pairing. This domain name tutorial will not automatically establish NAT penetration; just ordinary website hosting space will not be able to forward PCM audio.")
                            .font(.subheadline)
                    }
                }

                Section("1 · Prepare Android and gateway") {
                    requirement("Start VoWLAN and PCM services", symbol: "antenna.radiowaves.left.and.right",
                        detail: "Let Android and the gateway be in the same trusted LAN. It is recommended to set DHCP address reservation for Android, such as 192.168.1.50.")
                    requirement("Resolve domain names and configure TLS", symbol: "server.rack",
                        detail: "The domain name points to the public network address reachable by the gateway, and port permission and trusted certificates are configured. You can use stunnel or nginx stream to forward the original TCP; ordinary web reverse proxies cannot carry PCM audio.")
                    if !firstPairing {
                        Text("First make sure that the Android has completed VoWLAN pairing. When there is only Bluetooth pairing and no VoWLAN key, VoWLAN pairing needs to be completed first.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Section {
                    if firstPairing {
                        portRow("Temporary pairing · HTTPS", external: "9443", target: "Android’s random port for this pairing window")
                    }
                    portRow("Call Control · HTTPS", external: "443", target: "Android actual control port, usually 7592")
                    portRow("Audio · TCP TLS", external: "17593", target: "Android actual PCM port, usually 7593")
                    if firstPairing {
                        Text("Click "Start One-time Pairing" on Android, and then change the backend port for temporary pairing forwarding to the port displayed in the window. The new window may change the port, please update simultaneously.")
                            .font(.subheadline)
                    }
                    DisclosureGroup("View gateway configuration examples") {
                        Text("The following is an example of stunnel server. Please replace the domain name certificate path, Android address and actual port, and then load the configuration according to the gateway's service management method.")
                            .font(.subheadline)
                        Text(gatewayExample)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            UIPasteboard.general.string = gatewayExample
                            copied = true
                        } label: {
                            Label(copied ? "Example copied" : "Copy configuration example",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("copyRemoteDirectExample")
                    }
                } header: {
                    Text("2 · Configure port forwarding")
                } footer: {
                    Text("iPhone → Gateway TLS entry → Android private network interface. Ports are examples only, the iPhone should fill in the actual external port. Do not map the Android plaintext interface directly to the public network; audio and control must point to the same Android.")
                }

                Section(firstPairing ? "3 · Encrypted pairing on iPhone" : "3 · Verify and save the domain name") {
                    Text(firstPairing
                        ? "Return to the pairing page, select "Public Domain Name", fill in the domain name, HTTPS pairing port, HTTPS control port, TLS audio port and Android six-digit verification code, and then click "Connect and Encrypted Pairing"."
                        : "Return to "Self-created domain name direct connection", select the paired Android and turn on the enable switch, fill in the domain name, HTTPS control port and TLS audio port, and click "Verify and Save".")
                    Label("Fill in the domain name phone.example.com", systemImage: "text.cursor")
                    Text("Without https://, a path, or a port. The domain route is saved only after the certificate and this Android device identity are authenticated.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Section("4 · Verify calls and text messages") {
                    Text("Select Android device to use VoWLAN, Auto or VoWLAN+VoBLE mode. Let iPhone use an external network to test text messages, incoming calls, outgoing calls, and two-way sound. Just because the control entry is verified, it does not mean that the audio is available.")
                    if firstPairing {
                        Label("After pairing is completed, close the temporary pairing entrance", systemImage: "lock")
                        Text("Only control and audio TLS entries remain; temporarily turn them on when re-pairing later.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Domain name direct connection will not automatically turn on Relay. Enable pure local mode when you need to completely disable Relay; successful direct connection does not mean that you can continue to receive incoming calls after the iOS lock screen, and this feature does not add background push.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Section("Encountered a problem") {
                    DisclosureGroup("Pairing successful, but control portal verification failed") {
                        Text("The pairing key is retained. Check whether the certificate, domain name resolution and control port are forwarded to the same Android, and then select the device in "Self-created domain name direct connection" to try again without deleting the device first.")
                    }
                    DisclosureGroup("Can be controlled, but there is no sound during calls") {
                        Text("Checks that the audio port uses raw TCP TLS forwarding, is passed, and that the Android PCM service is started. HTTP web proxy and regular Cloudflare web proxy are not replacements for PCM forwarding.")
                    }
                    DisclosureGroup("The external network is available, but the Wi-Fi at home is not available.") {
                        Text("The router may not support NAT flowback. First use the cellular network to verify the public network entrance, and continue to use the original direct connection address for the LAN; do not turn off certificate verification to solve the problem.")
                    }
                }
            }
            .navigationTitle("Domain name direct connection tutorial")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text("Return to configuration")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .accessibilityIdentifier("dismissRemoteDirectGuide")
            }
            .onChange(of: context) { _ in copied = false }
    }

    private func requirement(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func portRow(_ title: String, external: String, target: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("External port \(external) → \(target)")
                .font(.subheadline).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private var gatewayExample: String {
        let common = """
        client = no
        sslVersionMin = TLSv1.2
        cert = /certs/phone.example.com/fullchain.pem
        key = /certs/phone.example.com/privkey.pem

        [airsim-control]
        accept = 0.0.0.0:443
        connect = 192.168.1.50:7592
        TIMEOUTidle = 120

        [airsim-pcm]
        accept = 0.0.0.0:17593
        connect = 192.168.1.50:7593
        TIMEOUTidle = 120
        """
        guard firstPairing else { return common }
        return common + """


        # Temporary: replace 45945 with the current pairing port.
        # Disable this entry after pairing.
        [airsim-pairing]
        accept = 0.0.0.0:9443
        connect = 192.168.1.50:45945
        TIMEOUTidle = 15
        """
    }
}
