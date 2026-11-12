import SwiftUI
import UIKit
import UserNotifications

/// SimHelp 只引导 Android Pairing; not 检查旧模块固件 or Network. 
struct SimHelpFirstConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("airsim.first-connection-complete") private var completed = false
    @AppStorage(ConnectionModePreference.key) private var connectionModeRaw = ConnectionModePreference.selected().rawValue
    @State private var showingPairing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 76, height: 76)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Android phone")
                        .font(.largeTitle.bold())
                    Text("SimHelp can independently connect to Android phones via VoWLAN, Bluetooth or Cloud Relay.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Label("Launch SimHelp and Audio Bridge on your Android phone", systemImage: "1.circle.fill")
                    Label(selectedMode == .bluetooth ? "Turn on Bluetooth on both devices" : "Prepare for network or Bluetooth by selected mode", systemImage: "2.circle.fill")
                    Label("Check the pairing security code and complete the authentication", systemImage: "3.circle.fill")
                }
                .font(.body.weight(.medium))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))

                Picker("connection mode", selection: $connectionModeRaw) {
                    ForEach(SimHelpConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: connectionModeRaw) { rawValue in
                    guard let mode = SimHelpConnectionMode(rawValue: rawValue) else { return }
                    model.setConnectionMode(mode)
                }
                Text(selectedMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Start pairing", systemImage: "lock.shield") {
                    showingPairing = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                if selectedMode == .localDual {
                    NavigationLink("Add Bluetooth device") { VoBLEPairingView().environmentObject(model) }
                        .frame(maxWidth: .infinity)
                }

                Button("Pair later in settings") { completed = true }
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationTitle("SimHelp")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPairing, onDismiss: {
                if model.vowlan.availability.isOnlineForDisplay || model.voble.state == .ready { completed = true }
            }) {
                NavigationStack {
                    Group {
                        if selectedMode == .bluetooth {
                            VoBLEPairingView()
                        } else {
                            SamsungPairingView()
                        }
                    }
                        .environmentObject(model)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingPairing = false }
                            }
                        }
                }
            }
        }
    }

    private var selectedMode: SimHelpConnectionMode {
        SimHelpConnectionMode(rawValue: connectionModeRaw) ?? .automatic
    }
}

#Preview("Paired devices · Empty list") {
    Form { Section("Android connection") { PairedAndroidDeviceRows(devices: [], onDelete: { _ in }) } }
}

#Preview("Paired devices · Online and offline") {
    Form {
        Section("Android connection") {
            PairedAndroidDeviceRows(devices: [
                .init(id: "preview-flip", deviceName: "Samsung Flip7", phoneNumber: "+10000000001",
                      agentKind: "standalone", cloudOnline: false, vowlanOnline: false,
                      bluetoothOnline: true, isCurrent: true),
                .init(id: "preview-vivo", deviceName: "vivo X60", phoneNumber: nil,
                      agentKind: "standalone", cloudOnline: false, vowlanOnline: false, isCurrent: false)
            ], onDelete: { _ in })
        }
    }
}

private struct PairedAndroidDeviceRows: View {
    let devices: [AndroidAgentPresentation]
    let onDelete: (AndroidAgentPresentation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paired device").font(.subheadline.weight(.semibold))
            if devices.isEmpty {
                Text("No pairing record yet").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.deviceName).font(.subheadline.weight(.medium))
                        Text(device.phoneNumber ?? "Number not provided").font(.caption).foregroundStyle(.secondary)
                        Text(connectionText(device)).font(.caption2).foregroundStyle(.secondary)
                        if let pairing = VoWLANPairingRecordStore.records()
                            .first(where: { $0.agentID == device.id }) {
                            Text("Local pairing record · \(pairing.id.prefix(8)) · \(pairing.endpoints.count) addresses")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive) { onDelete(device) } label: {
                        Image(systemName: "trash").padding(10)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(device.deviceName) Pairing record")
                }
            }
            Text("The current information will be re-read when reconnecting, and the number will not be saved in offline records.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func connectionText(_ device: AndroidAgentPresentation) -> String {
        let routes = [device.vowlanOnline ? "VoWLAN online" : nil,
                      device.bluetoothOnline ? "VoBLE online" : nil,
                      device.cloudOnline ? "Cloud online" : nil].compactMap { $0 }
        return routes.isEmpty ? "Offline·Read again next time you connect" : routes.joined(separator: " · ")
    }
}

private struct PureLocalSlideControl: View {
    let enabled: Bool
    let busy: Bool
    let blockedByCall: Bool
    let action: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var dragTranslation: CGFloat = 0
    @Namespace private var glassNamespace

    private var isInteractive: Bool { !busy && !blockedByCall }
    private var title: String {
        if busy { return "Switching connection strategy" }
        if blockedByCall { return "Cannot be switched during a call" }
        return enabled ? "Pure local mode is enabled" : "Slide to enable pure local mode"
    }

    private var statusText: String { enabled ? "Local connection only · Cloud disabled" : "Run by connection preference" }
    private var tint: Color { enabled ? .green : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: enabled ? "network.badge.shield.half.filled" : "network")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if busy { ProgressView().controlSize(.small) }
                else {
                    Text(enabled ? "Already turned on" : "Closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(enabled ? Color.green : Color.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background((enabled ? Color.green : Color.secondary).opacity(0.1), in: Capsule())
                }
            }

            // Keep instructions above the glass surface so material blending
            // and the moving thumb cannot obscure them in either appearance.
            slideInstruction

            GeometryReader { proxy in
                let knob: CGFloat = 48
                let inset: CGFloat = 4
                let travel = max(1, proxy.size.width - knob - inset * 2)
                let directionalDrag = enabled ? -dragTranslation : dragTranslation
                let progress = min(1, max(0, directionalDrag / travel))
                let restingOffset = enabled ? travel : 0
                let movingOffset = enabled ? restingOffset - progress * travel : progress * travel

                Group {
                    if #available(iOS 26.0, *), !reduceTransparency {
                        GlassEffectContainer(spacing: 6) {
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(.clear)
                                    .glassEffect(
                                        .regular.tint(tint.opacity(0.12)),
                                        in: .capsule
                                    )
                                    .glassEffectID("pure-local-track", in: glassNamespace)

                                sliderThumb(knob: knob)
                                    .glassEffect(
                                        .regular.tint(tint.opacity(enabled ? 0.72 : 0.58)).interactive(),
                                        in: .circle
                                    )
                                    .glassEffectID("pure-local-thumb", in: glassNamespace)
                                    .offset(x: inset + movingOffset)
                            }
                        }
                    } else {
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .fill(tint.opacity(0.12))
                                }
                            sliderThumb(knob: knob)
                                .background(tint, in: Circle())
                                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                                .offset(x: inset + movingOffset)
                        }
                    }
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .updating($dragTranslation) { value, state, _ in
                            guard isInteractive else { return }
                            state = value.translation.width
                        }
                        .onEnded { value in
                            guard isInteractive else { return }
                            let distance = enabled ? -value.translation.width : value.translation.width
                            guard distance >= travel * 0.78 else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            action(enabled)
                        }
                )
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.82), value: dragTranslation)
            }
            .frame(height: 56)
        }
        .padding(.vertical, 4)
        .opacity(isInteractive ? 1 : 0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("pure local mode")
        .accessibilityValue("\(enabled ? "already 开启" : "already 关闭"), \(statusText)")
        .accessibilityHint(blockedByCall ? "You can switch after ending the call" : (enabled ? "Double-click to turn off pure local mode" : "Double-click to enable pure local mode"))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action(enabled)
        }
        .accessibilityIdentifier("pureLocalModeSlider")
    }

    private var slideInstruction: some View {
        Text(busy ? "Switching, please wait." : blockedByCall ? "Please end the current call first" : (enabled ? "Slide left to close" : "Slide right to open"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    private func sliderThumb(knob: CGFloat) -> some View {
        Circle()
            .fill(.clear)
            .frame(width: knob, height: knob)
            .overlay {
                if busy { ProgressView().tint(.white) }
                else {
                    Image(systemName: enabled ? "chevron.left.2" : "chevron.right.2")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

private struct RemoteDirectSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var agentID = ""
    @State private var enabled = false
    @State private var host = ""
    @State private var controlPort = "443"
    @State private var pcmPort = "7593"
    @State private var message = ""
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                RemoteDirectGuideEntry(context: .existingDevice)
            }

            Section {
                Picker("Paired device", selection: $agentID) {
                    Text("Choose an Android phone").tag("")
                    ForEach(model.pairedDeviceHistory) { device in
                        Text(device.deviceName).tag(device.id)
                    }
                }
                Toggle("Enable self-created domain name direct connection", isOn: $enabled)
                    .disabled(agentID.isEmpty)
            } footer: {
                Text("Experimental features, real public network pairing and two-way audio are still pending acceptance by real devices. Configure NAS or soft route encryption entrance for mobile phones that have been paired through private network or public network domain names. Save after verification, Relay will not be automatically turned on.")
            }
            .disabled(saving || model.vowlan.callInProgress() || model.activeCall != nil || model.remoteCall != nil || model.pendingOutgoingCall != nil)
            if enabled {
                Section("remote entrance") {
                    TextField("DDNS domain name, such as phone.example.com", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("HTTPS control port", text: $controlPort).keyboardType(.numberPad)
                    TextField("TLS audio port", text: $pcmPort).keyboardType(.numberPad)
                }
                .disabled(saving || model.vowlan.callInProgress() || model.activeCall != nil || model.remoteCall != nil || model.pendingOutgoingCall != nil)
            }
            Section {
                Button(enabled ? "Verify and save" : "Save Close") {
                    saving = true
                    let target = agentID
                    saveTask = Task { @MainActor in
                        defer { saving = false }
                        do {
                            let route = enabled ? try RemoteDirectConfiguration.route(agentID: target,
                                host: host, controlPort: controlPort, pcmPort: pcmPort) : nil
                            try await model.configureRemoteDirect(agentID: target, route: route)
                            message = route == nil ? "The self-created Domain direct connection of this device has been turned off." :
                                "Control portal and device authentication passed and saved. Audio access needs to be verified during the actual call."
                        } catch is CancellationError {
                            message = "Configuration canceled. Please verify again."
                        } catch { message = error.localizedDescription }
                    }
                }
                .disabled(agentID.isEmpty || saving || model.vowlan.callInProgress() || model.activeCall != nil || model.remoteCall != nil || model.pendingOutgoingCall != nil)
                if saving { ProgressView("Verifying remote device...") }
                if !message.isEmpty { Text(message).font(.footnote) }
            } footer: {
                Text("After selecting VoWLAN or automatic mode, the LAN is given priority. If it is unreachable, try to create a self-made domain name. The NAS needs to provide TLS forwarding with valid certificates for control and audio respectively; web reverse proxy alone is not enough to transmit audio. This option does not provide background push notification for incoming calls and cannot be changed during a call.")
            }
        }
        .navigationTitle("Self-built Domain direct connection (experimental)")
        .onAppear {
            if agentID.isEmpty { agentID = model.pairedDeviceHistory.first?.id ?? "" }
            load()
        }
        .onChange(of: agentID) { _ in load() }
        .onDisappear { saveTask?.cancel() }
    }

    private func load() {
        let route = VoWLANManualRouteStore.routes().first { $0.agentID == agentID && $0.isRemote }
        enabled = route != nil
        host = route?.host ?? ""
        controlPort = route.map { String($0.controlPort) } ?? "443"
        pcmPort = route.map { String($0.pcmPort) } ?? "7593"
        message = ""
    }
}

/// Typed navigation keeps drafts in the settings owner while details come and go.
enum SimHelpSettingsPage: Hashable, Identifiable {
    case home, local, connections, mode, add, pairAuto, pairManual, pairDomain
    case device(String), deviceInfo(String)
    case status, network, prefixes, bluetooth, bluetoothPair, bluetoothStatus, relay, tls, tlsGuide
    case calls, background, forwarding, widgets, order, widgetGuide, islandGuide
    case preferences, accessibility, help, diagnostics, localCheck, cloudCheck, permissions
    case logs, feedback, feedbackPreview, guide, networkGuide, about

    var id: String {
        switch self {
        case .device(let id): return "device-\(id)"
        case .deviceInfo(let id): return "deviceInfo-\(id)"
        default: return String(describing: self)
        }
    }
    var title: String {
        switch self {
        case .home: return "set up"
        case .local: return "pure local mode"
        case .connections: return "Connections and devices"
        case .mode: return "Call connection method"
        case .add: return "Add device"
        case .pairAuto: return "Automatically discover pairs"
        case .pairManual: return "Manual address pairing"
        case .pairDomain: return "Public domain name matching"
        case .device: return "Device details"
        case .deviceInfo: return "Address and pairing information"
        case .status: return "Current connection details"
        case .network: return "LAN and VPN"
        case .prefixes: return "Custom private network segment"
        case .bluetooth: return "Bluetooth connection"
        case .bluetoothPair: return "Bluetooth pairing"
        case .bluetoothStatus: return "Bluetooth link status"
        case .relay: return "Cloud Relay"
        case .tls: return "Direct connection to public domain name"
        case .tlsGuide: return "Domain name direct connection tutorial"
        case .calls: return "Incoming calls and text messages"
        case .background: return "Running in the background"
        case .forwarding: return "Notification forwarding"
        case .widgets: return "Smart island and widgets"
        case .order: return "Device display order"
        case .widgetGuide: return "Home screen widget"
        case .islandGuide: return "Lock screen and smart island"
        case .preferences: return "Appearance and Preferences"
        case .accessibility: return "Language and Accessibility"
        case .help: return "Help and diagnostics"
        case .diagnostics: return "Check connection"
        case .localCheck: return "local connection check"
        case .cloudCheck: return "Cloud connection self-test"
        case .permissions: return "System permissions"
        case .logs: return "Detailed logs and technical information"
        case .feedback: return "Submit feedback"
        case .feedbackPreview: return "Upload content range"
        case .guide: return "User guide"
        case .networkGuide: return "Connection preparation and troubleshooting"
        case .about: return "About SimHelp"
        }
    }
}

enum SimHelpSettingsPolicy {
    static func canSelect(_ mode: SimHelpConnectionMode, pureLocal: Bool, callBusy: Bool) -> Bool {
        !callBusy && !(pureLocal && mode == .cloud)
    }

    /// Accept existing self-hosted HTTP deployments as well as HTTPS. Never
    /// silently replace invalid input with the maintainer's default Relay.
    static func validRelayURL(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        return value
    }
}


/// Only visible home values participate in diffing. PCM counters, history updates
/// and unrelated AppModel publications do not invalidate the scrolling sections.
struct SimHelpSettingsHomeSnapshot: Equatable {
    let deviceID: String?
    let deviceName: String
    let connectionDetail: String
    let modeTitle: String
    let version: String
    let pureLocalEnabled: Bool
    let pureLocalBusy: Bool
    let callBusy: Bool
    let pureLocalError: String?
    let language: String
}

private struct SimHelpSettingsLink: View {
    let page: SimHelpSettingsPage
    let icon: String
    var detail: String? = nil

    var body: some View {
        NavigationLink(value: page) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(.blue).frame(width: 26)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("settings.link.\(page.id)")
    }
}

// Keep the Form inside the equality boundary so its Sections retain native
// row identity, hit testing and value-based navigation registration.
private struct SimHelpSettingsHomeContent: View, Equatable {
    let snapshot: SimHelpSettingsHomeSnapshot
    // This binding addresses stable owner state, not a closure capturing an old
    // model snapshot. The owner rechecks live call/busy state before any action.
    @Binding var requestedPureLocalMode: Bool?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.snapshot == rhs.snapshot }

    private func link(_ page: SimHelpSettingsPage, _ icon: String, detail: String? = nil) -> some View {
        SimHelpSettingsLink(page: page, icon: icon, detail: detail)
    }

    var body: some View {
        Form {
            Section {
                PureLocalSlideControl(enabled: snapshot.pureLocalEnabled,
                    busy: snapshot.pureLocalBusy, blockedByCall: snapshot.callBusy) { current in
                    requestedPureLocalMode = !current
                }
                NavigationLink("Learn about pure local mode", value: SimHelpSettingsPage.local)
                    .font(.footnote)
                if let error = snapshot.pureLocalError { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                if let deviceID = snapshot.deviceID {
                    NavigationLink(value: SimHelpSettingsPage.device(deviceID)) {
                        Label {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(snapshot.deviceName).font(.headline)
                                Text(snapshot.connectionDetail)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "iphone.radiowaves.left.and.right").foregroundStyle(.blue) }
                        .padding(.vertical, 6)
                    }
                } else {
                    link(.add, "iphone.badge.plus", detail: "Connect your Android phone or U30 Air")
                }
            }
            Section {
                link(.connections, "antenna.radiowaves.left.and.right", detail: snapshot.modeTitle)
                link(.calls, "phone", detail: "Incoming call notification, SMS and forwarding")
                link(.widgets, "rectangle.on.rectangle", detail: "Desktop and lock screen display")
                link(.preferences, "paintpalette")
            }
            Section {
                link(.help, "questionmark.circle")
                link(.about, "info.circle", detail: snapshot.version)
            }
        }
    }
}

struct SimHelpSettingsView: View {
    private enum SelfTestPhase {
        case idle
        case running
        case completed
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appUpdates: AppUpdateController
    @Environment(\.scenePhase) private var updateScenePhase
    @State private var appUpdatePresentation: AppUpdatePresentation?
    @State private var appUpdateInbox = AppUpdateResultInbox()
    @State private var updateViewVisible = false
    @AppStorage(ConnectionModePreference.key) private var connectionModeRaw = ConnectionModePreference.selected().rawValue
    @AppStorage(CloudSignalingPreference.key) private var cloudSignalingEnabled = CloudSignalingPreference.isEnabled()
    @AppStorage(BackgroundStandbyPreference.key) private var backgroundStandbyEnabled = false
    @AppStorage(LiveActivityVisibilityPreference.key) private var liveActivityEnabled = true
    @AppStorage(SMSVerificationCodeClipboard.enabledKey) private var autoCopySMSCode = true
    @AppStorage(FeedbackUploader.descriptionKey) private var feedbackDescription = ""
    @AppStorage(FeedbackUploader.remarkKey) private var feedbackRemark = ""
    @State private var feedbackUploadStatus = ""
    @State private var feedbackUploading = false
    @State private var relayURL = RelayConfiguration.effectiveURL(
        stored: UserDefaults.standard.string(forKey: "airsim.push-relay-url"),
        buildSetting: Bundle.main.object(forInfoDictionaryKey: "SimHelpPushRelayURL") as? String,
        bundleID: Bundle.main.bundleIdentifier
    )
    @State private var message: String?
    @State private var selfTestPhase: SelfTestPhase = .idle
    @State private var selfTestReport: CloudSelfTestReport?
    @State private var selfTestTask: Task<Void, Never>?
    @State private var deletingDevice: AndroidAgentPresentation?
    @State private var deviceDeletionInProgress = false
    @State private var deviceDeletionError: String?
    @State private var networkPrefixesText = NetworkRoutePreferences.storedText()
    @State private var networkPrefixError: String?
    @AppStorage(RelayEgressGate.persistenceKey) private var pureLocalEnabled = false
    @State private var pureLocalBusy = false
    @State private var pureLocalError: String?
    @State private var requestedPureLocalMode: Bool?
    @State private var diagnosticCloudOnline: Bool?
    @FocusState private var networkPrefixesFocused: Bool
    @FocusState private var feedbackFocusedField: FeedbackFocusedField?

    private enum FeedbackFocusedField: Hashable {
        case description
        case remark
    }

    @State private var path: [SimHelpSettingsPage] = []
    @State private var localCheckRunning = false
    @State private var localCheckDate: Date?
    @State private var localCheckStatus: String?
    @State private var notificationPermission = "Reading"
    @State private var relaySaving = false
    @State private var selfTestCopied = false

    var body: some View {
        NavigationStack(path: $path) {
            settingsForm(.home)
                .navigationDestination(for: SimHelpSettingsPage.self) { page in
                    destination(page)
                }
        }
        // Keep lifecycle ownership outside the root Form: pushing a detail must
        // not cancel a diagnostic or discard the user's pending update result.
        .task { await model.refreshPairedDeviceInformation() }
        .fullScreenCover(item: $appUpdatePresentation, onDismiss: presentManualAppUpdateIfIdle) { presentation in
            AppUpdateSheet(presentation: presentation, updates: appUpdates)
        }
        .onAppear { updateViewVisible = true; presentManualAppUpdateIfIdle() }
        .onChange(of: requestedPureLocalMode) { requested in
            guard let requested else { return }
            requestedPureLocalMode = nil
            Task { @MainActor in await setPureLocalMode(requested) }
        }
        .onChange(of: model.activeCall?.id) { _ in handleUpdateCallChange() }
        .onChange(of: model.remoteCall?.id) { _ in handleUpdateCallChange() }
        .onChange(of: model.pendingOutgoingCall?.id) { _ in handleUpdateCallChange() }
        .onChange(of: updateScenePhase) { phase in
            presentManualAppUpdateIfIdle()
            if phase == .active { Task { await readNotificationPermission() } }
        }
        .onChange(of: model.errorMessage) { _ in presentManualAppUpdateIfIdle() }
        .confirmationDialog("Forgot this device?",
            isPresented: Binding(get: { deletingDevice != nil }, set: { if !$0 { deletingDevice = nil } }),
            titleVisibility: .visible, presenting: deletingDevice) { device in
            Button("Forgot \(device.deviceName)", role: .destructive) {
                deviceDeletionInProgress = true
                Task {
                    defer { deviceDeletionInProgress = false }
                    do {
                        try await model.forgetAndroidDevice(device.id)
                        if case .device = path.last { path.removeLast() }
                    } catch { deviceDeletionError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Clear the local pairing and cache, and do not delete the mobile phone system text messages and call records. Pairing is required for reuse; remote credentials on offline devices are not automatically revoked.")
        }
        .onDisappear {
            updateViewVisible = false
            selfTestTask?.cancel()
            selfTestTask = nil
            if selfTestPhase == .running { selfTestPhase = .idle }
        }
    }

    @ViewBuilder
    private func destination(_ page: SimHelpSettingsPage) -> some View {
        switch page {
        case .pairAuto: SamsungPairingView(initialMethod: .automatic)
        case .pairManual: SamsungPairingView(initialMethod: .privateIP)
        case .pairDomain: SamsungPairingView(initialMethod: .publicDomain)
        case .bluetoothPair: VoBLEPairingView()
        case .tls: RemoteDirectSettingsView()
        case .tlsGuide: RemoteDirectGuideView(context: .firstPairing, embedded: true)
        case .forwarding: NotificationForwardingView()
        case .logs: AgentVerboseTraceView(api: model.verboseDiagnosticsAPI)
        default: settingsForm(page)
        }
    }

    private func settingsForm(_ page: SimHelpSettingsPage) -> some View {
        Group {
            if page == .home {
                SimHelpSettingsHomeContent(snapshot: homeSnapshot,
                    requestedPureLocalMode: $requestedPureLocalMode).equatable()
            } else {
                Form { pageContent(page) }
            }
        }
            .formStyle(.grouped)
            .settingsSoftScrollEdge()
            .scrollDismissesKeyboard(.interactively)

            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(page == .home ? .large : .inline)
            .accessibilityIdentifier("settings.page.\(page.id)")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { feedbackFocusedField = nil; networkPrefixesFocused = false }
                }
            }
    }

    private func link(_ page: SimHelpSettingsPage, _ icon: String, detail: String? = nil) -> some View {
        SimHelpSettingsLink(page: page, icon: icon, detail: detail)
    }

    @ViewBuilder
    private func pageContent(_ page: SimHelpSettingsPage) -> some View {
        switch page {
        case .home:
            EmptyView() // The home Form owns its value-based update boundary.
        case .local:
            Section { pureLocalControl }
            Section("After opening") {
                Label("Only direct connection via VoWLAN, Bluetooth or VPN", systemImage: "checkmark.shield")
                Label("Block SimHelp Cloud Notifications, Relay and Feedback Uploads", systemImage: "cloud.slash")
                Text("Will not fall back to Relay when Local link is unavailable. GitHub version checking is not affected, and Android third-party notification forwarding is still handled by its independent SettingsControl.")
                Text("When Android is offline, it cannot be confirmed that the cross-terminal policy has been synchronized. Please check the Android status after reconnecting.")
            }
        case .connections:
            Section { link(.mode, "arrow.triangle.branch", detail: selectedMode.title) }
            deviceListSection
            Section { link(.status, "waveform.path.ecg") }
        case .mode:
            Section {
                ForEach(SimHelpConnectionMode.allCases) { mode in
                    Button { selectMode(mode) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: modeIcon(mode)).frame(width: 24).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title).foregroundStyle(.primary)
                                Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if selectedMode == mode { Image(systemName: "checkmark").foregroundStyle(.blue) }
                        }.padding(.vertical, 6)
                    }
                    .disabled(!SimHelpSettingsPolicy.canSelect(mode, pureLocal: pureLocalEnabled, callBusy: updateCallBusy))
                    .accessibilityIdentifier("settings.mode.\(mode.rawValue)")
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                }
            } footer: {
                Text(updateCallBusy ? "It can be switched after the call ends." : pureLocalEnabled
                    ? "Pure local is turned on, automatic mode only tries local links." : "This is the connection preference. The actual link is subject to the device status; it does not affect the manual cloud self-check.")
            }
        case .add:
            Section {
                Text("First open the one-time pairing window in Android SimHelp, and then select the connection method.")
                link(.pairAuto, "wifi", detail: "Same Wi-Fi or Android hotspot")
                link(.pairManual, "network", detail: "Manual IP, Tailscale or other VPN")
                link(.bluetoothPair, "wave.3.right", detail: "Check security codes on both ends")
                link(.pairDomain, "lock.shield", detail: "Experimental · Requires trusted TLS certificate")
            }
        case .device(let id): deviceSections(id)
        case .deviceInfo(let id): deviceInformation(id)
        case .status: connectionStatusSection
        case .network:
            Section {
                LabeledContent("VoWLAN", value: VoWLANStatusCopy.text(for: model.vowlan.availability))
                Button("Rediscover and verify", systemImage: "arrow.clockwise") { checkLocalConnection() }
                    .disabled(localCheckRunning || updateCallBusy)
                if localCheckRunning { ProgressView("Checking direct connect gateway...") }
                if let localCheckStatus { Text(localCheckStatus).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                link(.pairManual, "network")
                link(.prefixes, "slider.horizontal.3", detail: "Only special intranets need to be modified.")
                link(.networkGuide, "book")
            }
        case .prefixes: networkPrefixesSection
        case .bluetooth:
            bluetoothSection
            Section { link(.bluetoothStatus, "waveform.path.ecg") }
        case .bluetoothStatus:
            Section { LabeledContent("connection status", value: voBLEStatus) }
            bluetoothDiagnosticsSection
            Section {
                Text("These are current Bluetooth status, not a full call test. Passing the control certification does not mean that the audio has been tested.")
                link(.bluetoothPair, "wave.3.right")
                link(.permissions, "hand.raised")
            }
        case .relay: relaySections
        case .calls:
            Section {
                Toggle(isOn: Binding(get: { !pureLocalEnabled && cloudSignalingEnabled }, set: {
                    cloudSignalingEnabled = $0
                    model.setCloudSignalingEnabled($0)
                })) { Label("Cloud notification", systemImage: "bell") }
                    .disabled(pureLocalEnabled || pureLocalBusy)
                    .accessibilityIdentifier("cloudSignaling")
            } footer: {
                Text(pureLocalEnabled ? "Pure local mode has blocked cloud notifications, and the original preferences will be restored after closing." : "Used for background call notification without changing the audio connection method of the call.")
            }
            smsSection
            Section {
                link(.background, "moon")
                link(.permissions, "hand.raised")
                link(.forwarding, "paperplane", detail: "Android sends notification to third party")
            }
        case .background: backgroundSection
        case .widgets:
            liveActivitySection
            Section {
                link(.order, "arrow.up.arrow.down")
                link(.widgetGuide, "rectangle.on.rectangle")
                link(.islandGuide, "platter.filled.top.iphone")
            }
        case .order:
            if model.liveActivityOrderedAgents.isEmpty {
                Section { Text("You can adjust the display order after pairing devices.").foregroundStyle(.secondary); link(.add, "plus.circle") }
            } else { deviceOrderSection }
        case .preferences:
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
            }
            Section { link(.accessibility, "accessibility") }
        case .help:
            Section { link(.diagnostics, "stethoscope", detail: "Local, Bluetooth and cloud status"); link(.permissions, "hand.raised") }
            Section { link(.logs, "doc.text.magnifyingglass"); link(.feedback, "bubble.left.and.bubble.right") }
            Section { link(.guide, "book") }
        case .diagnostics:
            Section {
                link(.localCheck, "wifi")
                link(.bluetoothStatus, "wave.3.right")
                link(.cloudCheck, "cloud", detail: pureLocalEnabled ? "Not runnable in pure local mode" : nil)
            }
        case .localCheck:
            Section {
                Button("Check local connection", systemImage: "stethoscope") { checkLocalConnection() }
                    .disabled(localCheckRunning || updateCallBusy)
                if localCheckRunning { ProgressView("Verifying gateway...") }
                if let localCheckStatus {
                    Text(localCheckStatus)
                    if let localCheckDate { Text(localCheckDate, style: .time).font(.caption).foregroundStyle(.secondary) }
                } else { Text("Clicking to verify that the gateway is paired does not dial or read audio.").foregroundStyle(.secondary) }
            }
            Section {
                Text(updateCallBusy ? "You can recheck the connection after the call ends." : "Gateway verification only confirms the control link, and PCM two-way audio requires actual call testing.")
                link(.network, "wifi"); link(.permissions, "hand.raised"); link(.logs, "doc.text")
            }
        case .cloudCheck:
            cloudSelfTestSection
            if selfTestPhase == .completed, selfTestReport?.allPassed == false {
                Section("Next") {
                    link(.relay, "cloud")
                    link(.permissions, "hand.raised")
                    link(.logs, "doc.text.magnifyingglass")
                }
            }
        case .permissions: permissionSections
        case .feedback:
            feedbackSection
            Section { link(.feedbackPreview, "hand.raised") }
        case .feedbackPreview:
            Section("Manual upload range") {
                Text("Upload application and system versions, device models, connection status, diagnostic records and readable Android logs.")
                Text("Call audio will not be recorded or uploaded. Don't paste passwords, verification codes, pairing keys, or other personal information in descriptions and notes.")
                Text("Log processing and original TXT export are different processes; please check the content of the original export before sharing.")
            }
            Section("your text") {
                Text(feedbackDescription.isEmpty ? "Description not filled in" : feedbackDescription).textSelection(.enabled)
                Text(feedbackRemark.isEmpty ? "Remarks not filled in" : feedbackRemark).textSelection(.enabled)
            }
            Section { Text("Submit only if you click \"Upload Feedback\"; fail as a draft. This page only shows the upload range, not a full preview of what the server actually receives.").font(.footnote) }
        case .about: aboutSection
        case .guide:
            Section {
                link(.add, "iphone.badge.plus")
                link(.networkGuide, "network")
                link(.tlsGuide, "lock.shield")
                link(.background, "moon")
                link(.widgetGuide, "rectangle.on.rectangle")
            }
        case .networkGuide:
            guideSection("LAN and hotspot", steps: ["Connect both devices to the same Wi-Fi, or let the iPhone connect to the Android hotspot.", "Android opens a one-time pairing window; when automatic discovery is unavailable, Android's IP and current pairing port are used.", "Pair authentication and audio preparation are separate steps. After the gateway has been authenticated, actual calls still need to be tested."])
            guideSection("Tailscale vs. other VPNs", steps: ["Both ends join the same tunnel and allow mutual access.", "Fill in the Android address within the VPN, not the iPhone address. The pairing port and control and audio ports must all be accessible.", "Tailscale's 100.64/10 has built-in support, no need to open SimHelp cloud calling."])
            Section { link(.pairManual, "network"); link(.localCheck, "stethoscope") }
        case .widgetGuide:
            guideSection("Add widget", steps: ["Long press an empty space on the home screen and select Edit → Add Widget.", "Search for SimHelp, select a size and add it.", "Large size shows up to 5 recent calls and text messages per column; medium size shows summary by space.", "The device and mode buttons can be switched within the widget; the recording entrance opens the corresponding content."])
            Section { Text("The widget displays the recently synchronized information, and the update frequency is scheduled by the system. Pairing data and unread tags require opening the app for synchronization."); link(.order, "arrow.up.arrow.down") }
        case .islandGuide:
            guideSection("Smart island and lock screen", steps: ["Display the device status after turning on \"Show Smart Island\".", "The system will limit the duration of real-time activities, and expiration does not mean that the device is offline.", "Returning to the SimHelp frontend resumes presentation; incoming PushKit/CallKit links are independent of live activity."])
            Section { Text("Don't treat background keepalives or live activities as a guarantee that you'll receive a call after force-quitting the app.") }
        case .accessibility:
            Section {
                Picker("language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            }
            guideSection("Follow iPhone Settings", steps: ["Adjust text size, reduce dynamic effects or reduce transparency in System Settings → Accessibility.", "SimHelp's lists and forms follow the system text size, and important states use both text and icons.", "The slider also supports VoiceOver on/off operations without the need for precise dragging."])
        default: EmptyView()
        }
    }

    private var homeSnapshot: SimHelpSettingsHomeSnapshot {
        let devices = model.pairedDeviceHistory
        let device = devices.first(where: \.isCurrent) ?? devices.first
        let connection = model.connectionModePresentation
        return SimHelpSettingsHomeSnapshot(deviceID: device?.id,
            deviceName: device?.deviceName ?? "", connectionDetail: connection.status + " · " + connection.title,
            modeTitle: selectedMode.title, version: AppInformation.version,
            pureLocalEnabled: pureLocalEnabled, pureLocalBusy: pureLocalBusy,
            callBusy: updateCallBusy, pureLocalError: pureLocalError,
            language: settings.language.rawValue)
    }

    private var pureLocalControl: some View {
        PureLocalSlideControl(enabled: pureLocalEnabled, busy: pureLocalBusy, blockedByCall: updateCallBusy) { current in
            Task { @MainActor in await setPureLocalMode(!current) }
        }
    }

    private var deviceListSection: some View {
        Section("Paired device") {
            ForEach(model.pairedDeviceHistory) { device in
                NavigationLink(value: SimHelpSettingsPage.device(device.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.deviceName)
                        Text(device.isCurrent ? "Current device" : "Pairing saved").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            link(.add, "plus.circle")
        }
    }

    @ViewBuilder
    private func deviceSections(_ id: String) -> some View {
        if let device = model.pairedDeviceHistory.first(where: { $0.id == id }) {
            Section {
                Text(device.deviceName).font(.title2.bold())
                LabeledContent("Number", value: device.phoneNumber ?? "The operator did not provide a number")
                LabeledContent("VoWLAN", value: device.vowlanOnline ? "online" : "Not connected")
                LabeledContent("Bluetooth", value: device.bluetoothOnline ? "online" : "Not connected")
                LabeledContent("Cloud", value: device.cloudOnline ? "online" : "Not confirmed online yet")
            }
            Section { link(.deviceInfo(id), "info.circle"); link(.diagnostics, "stethoscope") }
            Section {
                Button("Forgot this device", role: .destructive) { deviceDeletionError = nil; deletingDevice = device }
                    .disabled(deviceDeletionInProgress || updateCallBusy)
                if let deviceDeletionError { Text(deviceDeletionError).font(.footnote).foregroundStyle(.red) }
            } footer: { Text("Only the local pairing will be cleared; the mobile phone system text messages or call records will not be deleted.") }
        } else {
            Section { Text("The local pairing record for this device has been removed."); link(.add, "plus.circle") }
        }
    }

    @ViewBuilder
    private func deviceInformation(_ id: String) -> some View {
        Section("Device identity") { Text("Identity … \(id.suffix(8) )").font(.body.monospaced()).textSelection(.enabled) }
        if let record = VoWLANPairingRecordStore.records().first(where: { $0.agentID == id }) {
            Section {
                LabeledContent("local record", value: String(record.id.prefix(8)))
                LabeledContent("Endpoint saved", value: "\(record.endpoints.count)")
                ForEach(Array(record.endpoints.enumerated()), id: \.offset) { _, endpoint in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(endpoint.host).textSelection(.enabled)
                        Text("Control \(endpoint.controlPort) · Audio \(endpoint.pcmPort) · \(endpoint.tls == true ? "TLS" : "Private network direct connection")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("The pairing key is stored in the local secure storage and is not displayed on the page.").font(.footnote)
            }
        }
    }

    private var relaySections: some View {
        Group {
            Section {
                LabeledContent("Cloud call", value: pureLocalEnabled ? "Purely local blocked" : runtimePolicy.startsCloud ? "Current mode enabled" : "Current is not used")
                TextField("https://relay.example.com", text: $relayURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("settings.relayURL")
                Button(relaySaving ? "Saving…" : "Save Relay address") { saveRelay() }
                    .disabled(pureLocalEnabled || updateCallBusy || relaySaving)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text(pureLocalEnabled ? "Pure local mode has blocked Relay, please turn off pure local mode first." : "Saving an address is a separate step from device registration. If you are not currently using cloud calling, you can also perform manual self-check.")
            }
            Section { link(.cloudCheck, "stethoscope") }
        }
    }

    private var permissionSections: some View {
        Group {
            Section {
                LabeledContent("NotificationPermission", value: notificationPermission)
                Text("Please check the local network and Bluetooth permissions in the system settings. iOS does not provide a unified query interface, and failure to connect does not necessarily mean that permission is denied.")
                Button("Open SimHelp System Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section {
                Text("The Android side also needs to check phone calls, text messages, and Shizuku/Root audio bridge authorization. PCM two-way audio is only verified during a call.")
                link(.diagnostics, "stethoscope")
            }
        }.task { await readNotificationPermission() }
    }

    private func guideSection(_ title: String, steps: [String]) -> some View {
        Section(title) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                Label(text, systemImage: "\(index + 1).circle").padding(.vertical, 6)
            }
        }
    }

    private func selectMode(_ mode: SimHelpConnectionMode) {
        guard SimHelpSettingsPolicy.canSelect(mode, pureLocal: pureLocalEnabled, callBusy: updateCallBusy) else { return }
        connectionModeRaw = mode.rawValue
        model.setConnectionMode(mode)
        // Mode changes do not invalidate read-only cloud diagnostic results.
    }

    private func checkLocalConnection() {
        guard !localCheckRunning, !updateCallBusy else { return }
        localCheckRunning = true
        Task { @MainActor in
            defer { localCheckRunning = false }
            model.vowlan.restartBrowsing()
            await model.vowlan.probeNow()
            localCheckDate = Date()
            localCheckStatus = VoWLANStatusCopy.text(for: model.vowlan.availability)
        }
    }

    private func saveRelay() {
        guard !pureLocalEnabled, !updateCallBusy, !relaySaving else { return }
        guard let value = SimHelpSettingsPolicy.validRelayURL(relayURL) else {
            message = "Enter a complete http:// or https:// address without credentials, query parameters, or fragments."
            return
        }
        relaySaving = true
        VoIPPushController.shared.updateRelayURL(value)
        relayURL = VoIPPushController.shared.configuredRelayURL()
        selfTestTask?.cancel(); selfTestReport = nil; selfTestPhase = .idle
        diagnosticCloudOnline = nil
        message = "The address has been saved; please run a self-check to confirm the device registration status."
        Task { @MainActor in
            defer { relaySaving = false }
            if let (api, _) = await model.readyVoWLANRoute() {
                await VoIPPushController.shared.syncRegistration(with: api)
            }
            if !pureLocalEnabled { await model.refreshCloudStatusForDiagnostics() }
        }
    }

    private func readNotificationPermission() async {
        let value = await UNUserNotificationCenter.current().notificationSettings()
        switch value.authorizationStatus {
        case .authorized: notificationPermission = "allowed"
        case .provisional, .ephemeral: notificationPermission = "Temporarily allowed"
        case .denied: notificationPermission = "Not allowed"
        case .notDetermined: notificationPermission = "Not requested"
        @unknown default: notificationPermission = "Please confirm in system settings"
        }
    }

    private var backgroundSection: some View {
        Section {
            Toggle("Background mute audio keep alive", isOn: $backgroundStandbyEnabled)
                .onChange(of: backgroundStandbyEnabled) { enabled in
                    model.setBackgroundStandbyEnabled(enabled)
                }
                .accessibilityIdentifier("backgroundStandby")
            Text(backgroundStandbyEnabled
                 ? "Enabled: The app plays mute audio when it exits to the background, and tries to maintain polling, CallKit and Push processing; this will significantly increase power consumption."
                 : "Off: Does not play background silent audio to reduce power consumption; iOS can still be woken up through PushKit, but background polling may be suspended.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("background keepalive")
        } footer: {
            Text("This is a global switch that will stop all background mute audio keep-alive paths when turned off; it will not turn off VoWLAN, Bluetooth, or Cloud Push functionality.")
        }
    }

    private var connectionStatusSection: some View {
        Section("Current connection") {
            LabeledContent("Current mode", value: model.connectionModePresentation.title)
            LabeledContent("connection status", value: model.connectionModePresentation.status)
            LabeledContent("VoWLAN", value: VoWLANStatusCopy.text(for: model.vowlan.availability))
            LabeledContent(
                "Cloud Relay",
                value: CloudRelayStatusCopy.text(pureLocal: pureLocalEnabled,
                    cloudOnline: runtimePolicy.startsCloud ? model.cloudAgentStatus?.cloudOnline : diagnosticCloudOnline,
                    usesCloudCalls: runtimePolicy.startsCloud)
            )
            if !pureLocalEnabled && !runtimePolicy.startsCloud {
                Text("The current call uses the local link; cloud calling is not enabled, but Relay, registration, and Agent heartbeats can still be manually checked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(model.connectionModePresentation.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let connectionMessage = model.connectionMessage, !connectionMessage.isEmpty {
                Text(connectionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var networkPrefixesSection: some View {
        Section {
            // 单行输入 + 默认回车键:  by “返回”直接收起键盘, 多行输入会让回车变成换行. 
            TextField("For example 30.0.0.0/8, 100.64.0.0/10", text: $networkPrefixesText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($networkPrefixesFocused)
                .onSubmit {
                    networkPrefixesFocused = false
                    saveNetworkPrefixes()
                }
                .accessibilityIdentifier("privateNetworkPrefixes")
            if let networkPrefixError {
                Text(networkPrefixError).font(.footnote).foregroundStyle(.red)
            } else {
                Text("Separate multiple network segments with commas, such as 30.0.0.0/8, 100.64.0.0/10. Save and re-pair or rediscover to use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Save private network segment") {
                networkPrefixesFocused = false
                saveNetworkPrefixes()
            }
            .accessibilityIdentifier("savePrivateNetworkPrefixes")
        } header: {
            Text("private network")
        } footer: {
            Text("Built-in support for 10/8, 172.16/12, 192.168/16, 169.254/16 and 100.64/10 (Tailscale)."
                + "Public network addresses are never considered private network segments.")
        }
    }

    private var bluetoothSection: some View {
        Section("Bluetooth connection") {
            LabeledContent("VoBLE", value: voBLEStatus)
            link(.bluetoothPair, "wave.3.right")
            Button("Rescan Bluetooth Agent", systemImage: "arrow.clockwise") {
                model.vobleHub.radio.rescan()
            }
            .disabled(!runtimePolicy.startsBluetooth)
        }
    }

    private var bluetoothDiagnosticsSection: some View {
        Section("Bluetooth diagnostics (desensitized)") {
            let diagnostics = model.vobleDiagnostics
            LabeledContent("Certification", value: diagnostics.peerAuthenticated ? "pass" : "Not completed")
            LabeledContent("PCM", value: diagnostics.pcmReady ? "Running" : "To be started")
            LabeledContent("coding", value: diagnostics.codec)
            LabeledContent("Send queue", value: "\(diagnostics.queuedFrames) / 8 frames")
            LabeledContent("dropped frames", value: "\(diagnostics.droppedFrames)")
            LabeledContent("jitter buffer", value: "\(diagnostics.jitterFrames) frame")
            LabeledContent("recent errors", value: diagnostics.lastError.rawValue)
            Text("Diagnostics do not display numbers, keys, nonces, authentication tags, or audio content.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var liveActivitySection: some View {
        Section {
            Toggle(isOn: $liveActivityEnabled) {
                Label("Show smart island", systemImage: "platter.filled.top.iphone")
            }
            .onChange(of: liveActivityEnabled) { enabled in
                model.setLiveActivityEnabled(enabled)
            }
        } header: {
            Text("Smart Island and real-time activities")
        } footer: {
            Text("Closing ends SimHelp's smart island and lock screen real-time activities; calls and text messages can still be used normally.")
        }
    }

    private var deviceOrderSection: some View {
        Section {
            ForEach(model.liveActivityOrderedAgents) { agent in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.deviceName)
                            .fixedSize(horizontal: false, vertical: true)
                        if let number = agent.phoneNumber, !number.isEmpty {
                            Text(number)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggleLiveActivityAgentPin(agent.id)
                    } label: {
                        Image(systemName: LiveActivityAgentOrder.isPinned(agent.id)
                            ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(LiveActivityAgentOrder.isPinned(agent.id)
                        ? "Unpin \(agent.deviceName)" : "Pin \(agent.deviceName)")
                    Button {
                        model.moveLiveActivityAgent(agent.id, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Move up \(agent.deviceName)")
                    Button {
                        model.moveLiveActivityAgent(agent.id, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Move down \(agent.deviceName)")
                }
            }
        } header: {
            Text("Device display order")
        } footer: {
            Text("Top devices are pinned to the front; the rest are sorted here. Each page of Smart Island displays up to 5 units, and the button in the upper right corner turns to the next page.")
        }
    }

    private var cloudSelfTestSection: some View {
        Section {
            Button {
                startCloudSelfTest()
            } label: {
                HStack {
                    Label("Run Cloud Mode Self-Test", systemImage: "stethoscope")
                    Spacer()
                    if selfTestPhase == .running {
                        ProgressView()
                    }
                }
            }
            .disabled(pureLocalEnabled || selfTestPhase == .running)

            if let report = selfTestReport {
                ForEach(report.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selfTestSymbol(for: step.state))
                            .foregroundStyle(selfTestColor(for: step.state))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .textSelection(.enabled)
                            Text(step.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                if selfTestPhase == .completed {
                    Text(report.allPassed ? "Cloud mode self-test passed" : "The self-test failed, please follow the failed steps to repair and try again.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(report.allPassed ? .green : .orange)
                    Button {
                        UIPasteboard.general.string = report.copyText
                        selfTestCopied = true
                    } label: {
                        Label(selfTestCopied ? "Self-test results copied" : "Copy self-test results", systemImage: "doc.on.doc")
                    }
                    .font(.footnote)
                }
            }
        } header: {
            Text("Cloud connection self-test")
        } footer: {
            Text(pureLocalEnabled
                ? "Pure local mode is turned on and access to Relay is prohibited; after it is turned off, manual self-test can be performed."
                : "Verify the local Push credentials, Relay identity, device registration, Agent record, 150-second heartbeat and command routing in sequence; failure steps will give specific stuck points, and no dialing or SMS will be sent.")
        }
    }

    private var smsSection: some View {
        Section("Short message") {
            Toggle("Automatically copy verification code to clipboard", isOn: $autoCopySMSCode)
            Text("After receiving the new verification code text message, it will be automatically copied so that the system keyboard can display paste suggestions. The current clipboard content will be overwritten and can be closed at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("about") {
            LabeledContent("project", value: "SimHelp")
            LabeledContent("Version", value: AppInformation.version)
                .textSelection(.enabled)
            Button("Updates to the current version") { appUpdatePresentation = .notes }
            Button(appUpdates.checking ? "Checking for app updates…" : "Check for app updates") {
                Task {
                    if let result = await appUpdates.check(manual: true) {
                        appUpdateInbox.receive(result)
                        presentManualAppUpdateIfIdle()
                    }
                }
            }
            .disabled(appUpdates.checking)
            Text(appUpdates.status).font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Update channel", value: AppUpdateChannel.title)
            Link("GitHub repository", destination: AppInformation.repositoryURL)
            Link("Version release and download", destination: AppInformation.releasesURL)
        }
    }

    private var feedbackSection: some View {
        Section("feedback") {
            TextField("User description (optional)", text: $feedbackDescription, axis: .vertical)
                .accessibilityIdentifier("settings.feedbackDescription")
                .lineLimit(2...4)
                .focused($feedbackFocusedField, equals: .description)
                .submitLabel(.done)
                .onSubmit { feedbackFocusedField = nil }
            TextField("Remarks (optional)", text: $feedbackRemark, axis: .vertical)
                .lineLimit(2...4)
                .focused($feedbackFocusedField, equals: .remark)
                .submitLabel(.done)
                .onSubmit { feedbackFocusedField = nil }
            Button {
                guard !pureLocalEnabled else { return }
                feedbackFocusedField = nil
                feedbackUploading = true
                feedbackUploadStatus = "Collecting and uploading..."
                Task {
                    defer { feedbackUploading = false }
                    let result = await FeedbackUploader.shared.upload(
                        trigger: "manual",
                        eventID: UUID().uuidString,
                        api: model.verboseDiagnosticsAPI,
                        model: model
                    )
                    feedbackUploadStatus = result
                }
            } label: {
                Label(feedbackUploading ? "Uploading…" : "Upload feedback", systemImage: "paperplane")
            }
            .disabled(feedbackUploading || pureLocalEnabled)
            if pureLocalEnabled { Text("Pure local mode has blocked uploads, drafts will remain.").font(.footnote) }
            if !feedbackUploadStatus.isEmpty {
                Text(feedbackUploadStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Only manually upload diagnostic information. Please check the upload scope first to avoid including personal information in the text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func setPureLocalMode(_ enabled: Bool) async {
        guard !pureLocalBusy else { return }
        selfTestTask?.cancel()
        selfTestPhase = .idle
        selfTestReport = nil
        diagnosticCloudOnline = nil
        guard !updateCallBusy else { pureLocalError = "Unable to switch to pure local mode during a call"; return }
        pureLocalBusy = true; pureLocalError = nil
        defer { pureLocalBusy = false }
        if enabled {
            UserDefaults.standard.set(connectionModeRaw, forKey: "airsim.pure-local.prior-mode")
            UserDefaults.standard.set(cloudSignalingEnabled, forKey: "airsim.pure-local.prior-cloud")
            RelayEgressGate.shared.setPersistentBlocked(true)
            pureLocalEnabled = true
            guard await RelayEgressGate.shared.disableAndDrain() else {
                pureLocalError = "The cloud connection has not been completely drained, please try again later."
                return
            }
            cloudSignalingEnabled = false
            model.setCloudSignalingEnabled(false)
            connectionModeRaw = SimHelpConnectionMode.localDual.rawValue
            model.setConnectionMode(.localDual)
        } else {
            do {
                try RelayEgressGate.shared.enableAfterRestore()
                RelayEgressGate.shared.setPersistentBlocked(false)
                pureLocalEnabled = false
                let raw = UserDefaults.standard.string(forKey: "airsim.pure-local.prior-mode") ?? SimHelpConnectionMode.automatic.rawValue
                let cloud = UserDefaults.standard.object(forKey: "airsim.pure-local.prior-cloud") as? Bool ?? true
                connectionModeRaw = raw
                cloudSignalingEnabled = cloud
                model.setCloudSignalingEnabled(cloud)
                model.setConnectionMode(SimHelpConnectionMode(rawValue: raw) ?? .automatic)
            } catch { pureLocalError = "Local exit not yet Done: \(error.localizedDescription)" }
        }
    }

    private var updateCallBusy: Bool {
        model.activeCall != nil || model.remoteCall != nil || model.pendingOutgoingCall != nil
    }

    private func handleUpdateCallChange() {
        if updateCallBusy { appUpdatePresentation = nil }
        else { presentManualAppUpdateIfIdle() }
    }

    private func presentManualAppUpdateIfIdle() {
        if let result = appUpdateInbox.takeIfIdle(isActive: updateViewVisible && updateScenePhase == .active,
            callBusy: updateCallBusy, hasModal: appUpdatePresentation != nil || model.errorMessage != nil) {
            appUpdatePresentation = .result(result)
        }
    }

    private func startCloudSelfTest() {
        guard !pureLocalEnabled, !RelayEgressGate.shared.isBlocked else { return }
        selfTestTask?.cancel()
        selfTestCopied = false
        selfTestPhase = .running
        selfTestReport = .initial
        selfTestTask = Task { @MainActor in
            let report = await VoIPPushController.shared.runCloudSelfTest { update in
                guard !Task.isCancelled else { return }
                selfTestReport = update
            }
            guard !Task.isCancelled else { return }
            selfTestReport = report
            selfTestPhase = .completed
            if runtimePolicy.startsCloud {
                await model.refreshCloudStatusForDiagnostics()
            } else {
                // Explicit diagnostics must not use the automatic cloud-mode fetch guard.
                let status = try? await VoIPPushController.shared.fetchCloudAgentStatusForDiagnostics(allowLocalMode: true)
                guard !Task.isCancelled, !pureLocalEnabled else { return }
                diagnosticCloudOnline = status?.cloudOnline
            }
        }
    }

    private var selectedMode: SimHelpConnectionMode {
        SimHelpConnectionMode(rawValue: connectionModeRaw) ?? .automatic
    }

    private var runtimePolicy: ConnectionModeRuntimePolicy {
        ConnectionModeRuntimePolicy(mode: selectedMode)
    }

    private func saveNetworkPrefixes() {
        // 单行输入can 能包含粘贴进来的换行, 统一视 for 分隔符. 
        let invalid = networkPrefixesText
            .split { $0 == "," || $0 == ";" || $0.isWhitespace }
            .map(String.init)
            .filter { NetworkRoutePreferences.parse($0) == nil }
        guard invalid.isEmpty else {
            networkPrefixError = "The network segment format is invalid: \(invalid.joined(separator:", "))"
            return
        }
        NetworkRoutePreferences.save(networkPrefixesText)
        networkPrefixError = nil
        // 端点白名单在建立connect时重new 读取, 发现流程requires重new 开始才能生效. 
        model.vowlan.restartBrowsing()
    }

    private var voBLEStatus: String {
        switch model.vobleHub.pairingState {
        case .stopped: return runtimePolicy.startsBluetooth ? "To be started" : "Current mode is off"
        case .bluetoothUnavailable: return "Bluetooth is not available"
        case .scanning: return "discovering"
        case .connecting, .connected: return "Connecting"
        case .authenticating: return "Authenticating"
        case .ready: return "Certified"
        case .failed(let message): return "Failure: \(message)"
        }
    }

    private func modeIcon(_ mode: SimHelpConnectionMode) -> String {
        switch mode {
        case .localDual: return "wifi.circle"
        case .vowlan: return "wifi"
        case .bluetooth: return "wave.3.right"
        case .cloud: return "cloud"
        case .automatic: return "arrow.triangle.branch"
        }
    }

    private func selfTestSymbol(for state: CloudSelfTestStepState) -> String {
        switch state {
        case .pending: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func selfTestColor(for state: CloudSelfTestStepState) -> Color {
        switch state {
        case .pending: return .secondary
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        }
    }
}

import Foundation
import SwiftUI

enum NotificationForwardingChannel: String, CaseIterable, Codable, Identifiable, Sendable {
    case bark, discord, slack, wecom, feishu, telegram, qq, webhook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bark: return "Bark"
        case .discord: return "Discord"
        case .slack: return "Slack"
        case .wecom: return "Enterprise WeChat"
        case .feishu: return "Feishu custom robot"
        case .telegram: return "Telegram Bot"
        case .qq: return "QQ Official Bot"
        case .webhook: return "Universal Webhook"
        }
    }
}

struct NotificationForwardingDestination: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var enabled = true
    var name = ""
    var channel: NotificationForwardingChannel = .webhook
    var webhookURL = ""
    var token = ""
    var chatID = ""
    var deviceKey: String? = nil
    var secret = ""
    var sendSMS = true
    var sendIncomingCall = true
    var sendMissedCall = true
    var includeBody = true
    var includeNumber = true
    var template = """{event}
    Device: {device}
    Number: {number}
    Sender: {sender}
    Content: {content}
    Time: {time}"""
    var missedTemplate: String? = nil


    /// Match the Android forwarder's required inputs without contacting a service.
    var validationMessage: String? {
        guard enabled else { return nil }
        let value = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = URLComponents(string: value)
        if !value.isEmpty {
            guard let parts, ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
                  let host = parts.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
                  parts.user == nil, parts.password == nil, parts.fragment == nil else {
                return "Please enter a valid webhook address."
            }
        }
        switch channel {
        case .bark:
            if !value.isEmpty && parts?.scheme?.lowercased() != "https" { return "Bark addresses require HTTPS." }
            let pathKey = parts?.path.split(separator: "/").last.map(String.init) ?? ""
            if (deviceKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               value.isEmpty || pathKey.isEmpty || pathKey == "push" { return "Please fill in the Bark Device Key." }
        case .telegram, .qq:
            if chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Please fill in Chat ID or OpenID." }
            if (value.isEmpty || channel == .qq), token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Please fill in Bot Token."
            }
        default:
            if value.isEmpty { return "Please fill in the webhook address." }
        }
        return nil
    }
}

struct NotificationForwardingConfig: Codable, Equatable, Sendable {
    var enabled = false
    var destinations: [NotificationForwardingDestination] = []
}

enum NotificationForwardingStore {
    static let key = "airsim.notification-forwarding"

    static func load(defaults: UserDefaults = .standard) -> NotificationForwardingConfig {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(NotificationForwardingConfig.self, from: data) else {
            return NotificationForwardingConfig()
        }
        return value
    }

    static func save(_ value: NotificationForwardingConfig, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

struct NotificationForwardingView: View {
    @State private var config = NotificationForwardingStore.load()
    @State private var editing: NotificationForwardingDestination?
    @State private var showingAdd = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable notification forwarding", isOn: $config.enabled)
                Text("The configuration is sent to Android with the next pairing. Android sends webhooks directly, without relying on Relay, APNs, or whether the iPhone is running.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Forward target") {
                ForEach(config.destinations) { destination in
                    Button {
                        editing = destination
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(destination.name.isEmpty ? destination.channel.title : destination.name)
                                Text(destination.channel.title + (destination.enabled ? "" : "· Deactivated"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    config.destinations.remove(atOffsets: offsets)
                    save()
                }
                Button {
                    showingAdd = true
                } label: {
                    Label("Add forwarding target", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Notification forwarding")
        .onChange(of: config) { _ in save() }
        .sheet(isPresented: $showingAdd) {
            NotificationForwardingEditor(destination: NotificationForwardingDestination()) { value in
                config.destinations.append(value)
                save()
            }
        }
        .sheet(item: $editing) { destination in
            NotificationForwardingEditor(destination: destination) { value in
                if let index = config.destinations.firstIndex(where: { $0.id == value.id }) {
                    config.destinations[index] = value
                }
                save()
            }
        }
    }

    private func save() {
        // Delivered only inside the next encrypted pairing registration; never
        // upload webhook URLs/tokens to Relay or APNs.
        NotificationForwardingStore.save(config)
    }
}

private struct NotificationForwardingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var destination: NotificationForwardingDestination
    @State private var confirmingDiscard = false
    let onSave: (NotificationForwardingDestination) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    TextField("Note name", text: $destination.name)
                    Picker("channel", selection: $destination.channel) {
                        ForEach(NotificationForwardingChannel.allCases) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    Toggle("enable", isOn: $destination.enabled)
                }
                Section("connect") {
                    TextField("Webhook URL", text: $destination.webhookURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if destination.channel == .bark {
                        TextField("Bark Device Key (fill in when URL does not contain key)", text: Binding(
                            get: { destination.deviceKey ?? "" },
                            set: { destination.deviceKey = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                    }
                    if destination.channel == .telegram || destination.channel == .qq {
                        SecureField("Bot Token", text: $destination.token)
                            .textInputAutocapitalization(.never)
                    }
                    if destination.channel == .telegram || destination.channel == .qq {
                        TextField("Chat ID / OpenID", text: $destination.chatID)
                    }
                    if destination.channel == .feishu {
                        SecureField("Signature Secret (optional)", text: $destination.secret)
                            .textInputAutocapitalization(.never)
                    }
                }
                if let validation = destination.validationMessage {
                    Section { Text(validation).font(.footnote).foregroundStyle(.red) }
                }
                Section("event") {
                    Toggle("Short message", isOn: $destination.sendSMS)
                    Toggle("Incoming call", isOn: $destination.sendIncomingCall)
                    Toggle("missed call", isOn: $destination.sendMissedCall)
                    Toggle("Contains text message text", isOn: $destination.includeBody)
                    Toggle("Contains numbers", isOn: $destination.includeNumber)
                }
                Section {
                    NavigationLink("Message template") {
                        Form {
                Section {
                    TextEditor(text: $destination.template)
                        .frame(minHeight: 150)
                        .font(.system(.footnote, design: .monospaced))
                    Text("Available placeholders: {event} {device} {number} {sender} {content} {time}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("SMS/call format")
                }
                Section {
                    TextEditor(text: Binding(
                        get: { destination.missedTemplate ?? "{event}\\nDevice: {device}\\nNumber: {number}\\nTime: {time}" },
                        set: { destination.missedTemplate = $0 }
                    ))
                        .frame(minHeight: 100)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Missed call format")
                }
                        }.navigationTitle("Message template")
                    }
                }

            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Forward target")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .confirmationDialog("Give up this edit?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Give up editing", role: .destructive) { dismiss() }
                Button("Continue editing", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { confirmingDiscard = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("keep") {
                        guard destination.validationMessage == nil else { return }
                        onSave(destination)
                        dismiss()
                    }
                    .disabled(destination.validationMessage != nil)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

@MainActor
final class FeedbackUploader {
    static let shared = FeedbackUploader()
    static let descriptionKey = "airsim.feedback-description"
    static let remarkKey = "airsim.feedback-remark"
    private static let endpoint: URL? = nil

    private init() {}

    static func permitsUpload(trigger: String) -> Bool { trigger == "manual" }

    func upload(trigger: String, eventID: String, api: SimHelpAPI?, model: AppModel?) async -> String {
        return "Feedback upload is disabled in this personal build."
        /*
        // Reject before collecting Android logs or contacting either endpoint.
        guard Self.permitsUpload(trigger: trigger) else { return "Automatic feedback upload is turned off, please upload manually" }
        guard !RelayEgressGate.shared.isBlocked else { return "Pure local mode is on, feedback upload is off" }

        let snapshot: AgentFeedbackSnapshot?
        if let api {
            snapshot = try? await api.feedbackSnapshot()
        } else {
            snapshot = nil
        }
        let trace = await AgentVerboseTraceRecorder.shared.exportText(agentEvents: [])
        // Keep the newest Android rows; a prefix loses the call/crash window that
        // triggered this feedback.
        let androidLog = String((snapshot?.bridgeLog ?? "").suffix(400_000))
        let pcm = Self.pcm(from: androidLog)
        let audio = Self.audioDiagnostics(trace: trace, snapshot: snapshot)
        let mode = ConnectionModePreference.selected()
        let modeValue: String
        switch mode {
        case .vowlan, .localDual: modeValue = "vowlan"
        case .bluetooth: modeValue = "voble"
        case .cloud: modeValue = "cloud"
        case .automatic: modeValue = "auto"
        }
        let device = UIDevice.current
        let body: [String: Any] = [
            "feedback_id": UUID().uuidString,
            "trigger": trigger,
            "platform": snapshot == nil ? "iOS" : "Both",
            "app_version": AppInformation.version,
            "ios_version": device.systemVersion,
            "iphone_model": device.model,
            "android_model": snapshot?.model ?? "",
            "android_sdk": snapshot?.sdk ?? 0,
            "connection_mode": modeValue,
            "route": mode.title,
            "relay_status": "unknown",
            "pcm": pcm,
            "audio": audio,
            "crash": CrashDiagnosticsStore.shared.recent(),
            "error_summary": "",
            "description": UserDefaults.standard.string(forKey: Self.descriptionKey) ?? "",
            "remark": UserDefaults.standard.string(forKey: Self.remarkKey) ?? "",
            "ios_trace": String(trace.prefix(250_000)),
            "android_log": androidLog,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return "Feedback data generation failed"
        }
        guard let endpoint = Self.endpoint else { return "Feedback upload is disabled in this personal build." }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        do {
            let (responseData, response) = try await RelayEgressGate.shared.send(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "Upload failed (HTTP \( (response as? HTTPURLResponse) ?.statusCode ?? 0))"
            }
            if let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let url = object["url"] as? String, !url.isEmpty {
                return "Uploaded: \(url)"
            }
            return "Uploaded to Notion"
        } catch {
            return "Upload failed: \(error.localizedDescription)"
        }
        */
    }

    private static func audioDiagnostics(trace: String, snapshot: AgentFeedbackSnapshot?) -> [String: Any] {
        let lines = trace.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = lines.lastIndex { $0.contains("phase=answer_observed") } ?? 0
        let relevant = lines[start...]
        var stages: [String] = []
        var startupMilliseconds = 0
        for line in relevant {
            // Trace lines are formatted as "[APP]...AUDIO CallsAudio start".
            guard line.contains("AUDIO CallsAudio start") else { continue }
            if let phase = Self.value(after: "phase=", in: line), !phase.isEmpty,
               !stages.contains(phase) { stages.append(phase) }
            let phase = Self.value(after: "phase=", in: line) ?? ""
            if phase != "stopped", phase != "failed",
               let duration = Int(Self.value(after: "duration_ms=", in: line) ?? "") {
                startupMilliseconds = max(startupMilliseconds, duration)
            }
        }
        let expected = ["answer_observed", "phone_start", "engine_ready", "agent_register",
                        "pcm_ready", "first_downlink", "agent_ready", "stopped"]
        let missing = expected.filter { !stages.contains($0) }
        let telecom = snapshot?.audio?.telecomState ?? ""
        let clientClosed = snapshot?.audio?.pcmClientClosed ?? false
        let pcmHealth = String((snapshot?.audio?.pcmHealth ?? "").prefix(500))
        let summary = "stages=\(stages.joined(separator: ",")); missing=\(missing.joined(separator: ",")); "
            + "telecom=\(telecom); pcm_client_closed=\(clientClosed); pcm=\(pcmHealth)"
        return [
            "stages": stages,
            "missing": missing,
            "startup_ms": startupMilliseconds,
            "pcm_client_closed": clientClosed,
            "telecom_state": telecom,
            "summary": summary,
        ]
    }

    private static func value(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        return line[range.upperBound...].split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    }

    private static func pcm(from log: String) -> [String: Any] {
        let route = value("pcm_route", in: log)
        let capture = value("pcm_capture", in: log)
        let initialized = value("pcm_initialized", in: log) == "true"
        let verified = route == "verified"
        let down = Int(value("pcm_down_peak", in: log)) ?? 0
        let up = Int(value("pcm_up_peak", in: log)) ?? 0
        let downBytes = Int(value("pcm_down_bytes", in: log)) ?? 0
        let upBytes = Int(value("pcm_up_bytes", in: log)) ?? 0
        let mode: String
        if !initialized || route.isEmpty {
            mode = "not_connected"
        } else if route == "verified" && down > 0 && up > 0 {
            mode = "vowlan_direct_full_duplex"
        } else if route == "verified" && down > 0 {
            mode = "vowlan_direct_downlink_only"
        } else if route == "verified" && up > 0 {
            mode = "vowlan_direct_uplink_only"
        } else {
            mode = "vowlan_direct_silent"
        }
        return [
            "mode": mode,
            "route": route,
            "capture_source": capture.isEmpty ? "" : "voice_downlink",
            "initialized": initialized,
            "route_verified": verified,
            "capture": capture.isEmpty ? "unverified" : capture,
            "down_peak": down,
            "up_peak": up,
            "down_bytes": downBytes,
            "up_bytes": upBytes,
            "failure": value("pcm_failure", in: log),
        ]
    }

    private static func value(_ key: String, in log: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: key) + "=([^\\s]+)") else { return "" }
        let range = NSRange(log.startIndex..<log.endIndex, in: log)
        guard let match = expression.firstMatch(in: log, range: range),
              let valueRange = Range(match.range(at: 1), in: log) else { return "" }
        return String(log[valueRange])
    }
}


private extension View {
    @ViewBuilder
    func settingsSoftScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            // Let the system blend scrolling content into the navigation chrome,
            // including Duo's changing safe area and accessibility settings.
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
