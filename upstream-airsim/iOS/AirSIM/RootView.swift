import SwiftUI
import UIKit

enum SystemCommunicationDestination: Equatable {
    case call(String)
    case message(String)
    case liveActivity(AirSIMLiveActivityAction, callID: String)
}

enum SystemCommunicationURL {
    static func destination(for url: URL) -> SystemCommunicationDestination? {
        if let action = AirSIMLiveActivityActionURL.parse(url) {
            return .liveActivity(action.action, callID: action.callID)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "tel" || scheme == "im" else {
            return nil
        }
        let prefixLength = scheme.count + 1
        guard url.absoluteString.count > prefixLength else { return nil }
        var target = String(url.absoluteString.dropFirst(prefixLength))
        while target.hasPrefix("//") { target.removeFirst(2) }
        target = String(target.split(separator: "?", maxSplits: 1).first ?? "")
        target = target.removingPercentEncoding ?? target
        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return scheme == "tel" ? .call(target) : .message(target)
    }
}

enum PhoneTab: String, CaseIterable, Identifiable {
    case dial = "dial"
    case recents = "recent calls"
    case messages = "Short message"
    case contacts = "Address book"
    case settings = "set up"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dial: return "circle.grid.3x3.fill"
        case .recents: return "clock.fill"
        case .messages: return "bubble.right.fill"
        case .contacts: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    // Reuse immutable symbol images when connection updates invalidate RootView.
    // Keep titles and native hit targets independent of artwork size.
    private static let tabImages: [PhoneTab: UIImage] = Dictionary(uniqueKeysWithValues:
        allCases.map { tab in
            (tab, UIImage(systemName: tab.icon, withConfiguration:
                UIImage.SymbolConfiguration(pointSize: 28, weight: .regular, scale: .default)) ?? UIImage())
        })

    var tabImage: UIImage { Self.tabImages[self] ?? UIImage() }

    var tabTitle: String {
        switch self {
        case .dial: return "Keypad"
        case .recents: return "recent"
        case .contacts: return "Contact person"
        default: return rawValue
        }
    }
}


/// Five major destinations using the system TabView；iOS 26 The native tab bar is responsible for Liquid Glass、
/// Long press to enlarge and interact with selected state，Avoid paging gestures and self-drawn buttons competing for horizontal sliding。
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("airsim.selected-tab") private var selectedTabRawValue = PhoneTab.dial.rawValue
    @State private var pendingSMSRecipient: String?
    @State private var messageListState = SMSConversationListState()
    @State private var conversationSender: String?
    @State private var showingConversation = false

    private var presentedCall: CallRecord? {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["AIRSIM_UI_FIXTURE"] == "sms-navigation",
           let preview = SMSNavigationFixture.previewCall { return preview }
#endif
        return model.inAppPresentedCall
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
                TabView(selection: selectedTabBinding) {
                    DialPadView()
                        .tag(PhoneTab.dial)
                        .tabItem { Label(L10n.t(PhoneTab.dial.tabTitle), systemImage: PhoneTab.dial.icon) }


                    RecentsView(onCall: dial, onMessage: composeMessage)
                        .tag(PhoneTab.recents)
                        .tabItem { Label(L10n.t(PhoneTab.recents.tabTitle), systemImage: PhoneTab.recents.icon) }

                        .badge(AirSIMWidgetSnapshot.badgeText(model.unseenMissedCallIDs.count))

                    Group {
                        if #available(iOS 17.0, *) {
                            AdaptiveMessagesView(pendingRecipient: $pendingSMSRecipient,
                                state: $messageListState, sender: $conversationSender,
                                showingConversation: $showingConversation,
                                openConversation: showSMSConversation)
                        } else {
                            NavigationStack {
                                MessagesView(
                                    pendingRecipient: $pendingSMSRecipient,
                                    state: $messageListState,
                                    openConversation: showSMSConversation
                                )
                                .navigationTitle(L10n.t("Short message"))
                                .navigationBarTitleDisplayMode(.large)
                                .toolbar { SMSConversationListToolbar(state: $messageListState) }
                                .navigationDestination(isPresented: $showingConversation) {
                                    if let sender = conversationSender {
                                        MessageThreadView(sender: sender)
                                            .id(sender)
                                            .toolbar(.hidden, for: .tabBar)
                                    }
                                }
                            }
                        }
                    }
                        .tag(PhoneTab.messages)
                        .tabItem { Label(L10n.t(PhoneTab.messages.tabTitle), systemImage: PhoneTab.messages.icon) }

                        .badge(AirSIMWidgetSnapshot.badgeText(model.unreadMessageIDs.count))

                    ContactsView(onCall: dial, onMessage: composeMessage)
                        .tag(PhoneTab.contacts)
                        .tabItem { Label(L10n.t(PhoneTab.contacts.tabTitle), systemImage: PhoneTab.contacts.icon) }


                    AirSIMSettingsView()
                        .tag(PhoneTab.settings)
                        .tabItem { Label(L10n.t(PhoneTab.settings.tabTitle), systemImage: PhoneTab.settings.icon) }

                }
                // Keep navigation state, but remove the underlying native tab
                // chrome from rendering, hit testing and VoiceOver during calls.
                // Duo promotes that chrome outside the SwiftUI content stack.
                .opacity(presentedCall == nil ? 1 : 0)
                .allowsHitTesting(presentedCall == nil)
                .accessibilityHidden(presentedCall != nil)
                .phoneTabBarAlwaysExpanded()
                .phoneTabSelectionFeedback(selectedTabRawValue)
                .tint(.blue)

            if let call = presentedCall {
                ActiveCallView(call: call)
                    .zIndex(1)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(PhoneBackdrop())
        .animation(.easeInOut(duration: 0.2), value: model.inAppPresentedCall?.id)
        .preferredColorScheme(settings.appearance.colorScheme)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let reminder = model.otherDeviceCallReminders.first {
                Button {
                    _ = model.openOtherDeviceCallNotification(reminder.userInfo)
                } label: {
                    Label("\(reminder.deviceName) Incoming calls · Other devices \(model.otherDeviceCallReminders.count)", systemImage: "phone.badge.waveform")
                        .font(.subheadline.weight(.semibold)).padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain).padding(.horizontal)
            }
        }
        .sheet(item: $model.focusedOtherDeviceCall) { reminder in
            OtherDeviceCallSheet(reminder: reminder).environmentObject(model)
        }
        .onOpenURL(perform: handleSystemCommunicationURL)
        .onAppear {
            if let info = OtherAndroidCallPresentationRequest.consume() { _ = model.openOtherDeviceCallNotification(info) }
            if let sender = IncomingSMSPresentationRequest.consume() {
                openSMSConversation(sender)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .airsimRemoteSMSReceived)) { _ in
            model.reloadMessagesFromLocalStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .airsimOpenSMSConversation)) { notification in
            let sender = IncomingSMSPresentationRequest.consume()
                ?? notification.userInfo?["sender"] as? String
            guard let sender else {
                selectedTab = .messages
                return
            }
            openSMSConversation(sender)
        }
        .onReceive(NotificationCenter.default.publisher(for: .airsimOpenIncomingCall)) { _ in
            model.presentCurrentCallInApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .airsimOpenOtherAndroidCall)) { notification in
            let info = OtherAndroidCallPresentationRequest.consume() ?? notification.userInfo ?? [:]
            _ = model.openOtherDeviceCallNotification(info)
        }
        .alert(L10n.t("mistake"), isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage?.isEmpty == false },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var selectedTabBinding: Binding<PhoneTab> {
        Binding(
            get: { PhoneTab(rawValue: selectedTabRawValue) ?? .dial },
            set: { newTab in
                guard newTab.rawValue != selectedTabRawValue else { return }
                selectedTabRawValue = newTab.rawValue
            }
        )
    }

    private var selectedTab: PhoneTab {
        get { PhoneTab(rawValue: selectedTabRawValue) ?? .dial }
        nonmutating set { selectedTabRawValue = newValue.rawValue }
    }

    private func dial(_ number: String) {
        showingConversation = false
        model.numberInput = number
        selectedTab = .dial
        Task { await model.dial() }
    }

    private func composeMessage(_ number: String) {
        showingConversation = false
        pendingSMSRecipient = number
        selectedTab = .messages
    }

    private func openSMSConversation(_ sender: String) {
        model.reloadMessagesFromLocalStore()
        showSMSConversation(sender)
    }

    private func showSMSConversation(_ sender: String) {
        selectedTab = .messages
        conversationSender = sender
        showingConversation = true
    }

    private func handleSystemCommunicationURL(_ url: URL) {
        if let target = AirSIMWidgetDestination.parse(url) {
            // Widget links only navigate. Never treat a widget tap as a dial or
            // SMS-send command, and never retarget an established call.
            if let id = target.agentID,
               !model.callLifecycleSnapshot.state.representsCall,
               !IPhoneCloudCallSession.shared.hasActiveCall,
               model.pairedAndroidAgents.contains(where: { $0.id == id }) {
                model.bindAndroidAgent(id)
            }
            switch target.destination {
            case .status: selectedTab = .settings
            case .dial: selectedTab = .dial
            case .messages: selectedTab = .messages
            case .contacts: selectedTab = .contacts
            case .recents: selectedTab = .recents
            }
            return
        }
        switch SystemCommunicationURL.destination(for: url) {
        case let .call(number):
            dial(number)
        case let .message(recipient):
            composeMessage(recipient)
        case let .liveActivity(action, callID):
            // Legacy links still open the app; use the same unified path as intents
            // so a stale island is dismissed instead of showing a Bluetooth-call error.
            Task { _ = await model.performLiveActivityAction(action, callID: callID) }
        case nil:
            break
        }
    }
}

/// Neutral system background shared by all phone pages.
struct PhoneBackdrop: View {
    var body: some View {
        Color(uiColor: .systemBackground).ignoresSafeArea()
    }
}

/// Key content appears to be native to the system. Liquid Glass，The old system is rolled back to the system material。
struct PhoneCard: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        } else {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
    }
}

struct PhoneGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let glass = interactive
                ? Glass.regular.tint(tint).interactive()
                : Glass.regular.tint(tint)
            content.glassEffect(
                glass,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                }
        }
    }
}

/// Custom toolbar materials are only used if the system shared background is hidden ToolbarItem，Make sure there is only one layer of glass at all times。
private struct PhoneToolbarGlassMorph: ViewModifier {
    let id: String
    @Namespace private var glassNamespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                content
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID(id, in: glassNamespace)
                    .glassEffectTransition(.materialize)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.82)))
        } else {
            content
        }
    }
}

/// iOS 26 Hide the automatically generated sharing button background in the navigation bar，Reuse the single layer of deformable glass above；
/// The old system will continue to be handed over to ToolbarItem Use platform default styles。
@ToolbarContentBuilder
func phoneMorphingToolbarItem<Content: View>(
    placement: ToolbarItemPlacement,
    id: String,
    @ViewBuilder content: () -> Content
) -> some ToolbarContent {
    if #available(iOS 26.0, *) {
        ToolbarItem(placement: placement) {
            content().phoneToolbarGlassMorph(id: id)
        }
        .sharedBackgroundVisibility(.hidden)
    } else {
        ToolbarItem(placement: placement, content: content)
    }
}

extension View {
    func phoneCard() -> some View { modifier(PhoneCard()) }

    func phoneGlassSurface(
        cornerRadius: CGFloat = 18,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(PhoneGlassSurface(
            cornerRadius: cornerRadius,
            tint: tint,
            interactive: interactive
        ))
    }

    @ViewBuilder
    func phoneTabBarAlwaysExpanded() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }

    func phoneToolbarGlassMorph(id: String) -> some View {
        modifier(PhoneToolbarGlassMorph(id: id))
    }

    @ViewBuilder
    func phoneTabSelectionFeedback(_ trigger: String) -> some View {
        if #available(iOS 17.0, *) {
            sensoryFeedback(.selection, trigger: trigger)
        } else {
            self
        }
    }
}

/// The entire TabView is the root of the outer navigation stack. Its native
/// bar fades with that root, below the opaque conversation being pushed/popped.
private struct PhoneTabBarNavigationFade: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var nativeTabBar: UITabBar?

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            transitionTabBar(visible: true, animated: animated)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            transitionTabBar(visible: false, animated: animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let bar = findTabBar() { Self.settle(bar, visible: true) }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if let bar = nativeTabBar { Self.settle(bar, visible: false) }
        }


        private func findTabBar() -> UITabBar? {
            if let nativeTabBar { return nativeTabBar }
            func find(in controller: UIViewController) -> UITabBar? {
                if let tabs = controller as? UITabBarController { return tabs.tabBar }
                for child in controller.children {
                    if let bar = find(in: child) { return bar }
                }
                return nil
            }
            var ancestor = parent
            while let controller = ancestor {
                if let bar = find(in: controller) {
                    nativeTabBar = bar
                    return bar
                }
                ancestor = controller.parent
            }
            return nil
        }

        private func transitionTabBar(visible: Bool, animated: Bool) {
            guard let bar = findTabBar() else { return }
            bar.isUserInteractionEnabled = false
            bar.accessibilityElementsHidden = true
            guard animated, !UIAccessibility.isReduceMotionEnabled,
                  let coordinator = transitionCoordinator else {
                Self.settle(bar, visible: visible)
                return
            }
            let queued = coordinator.animateAlongsideTransition(in: bar, animation: { _ in
                bar.alpha = visible ? 1 : 0
            }, completion: { context in
                let finalVisible = context.isCancelled ? !visible : visible
                Self.settle(bar, visible: finalVisible)
            })
            if !queued { Self.settle(bar, visible: visible) }
        }

        private static func settle(_ bar: UITabBar, visible: Bool) {
            bar.alpha = visible ? 1 : 0
            bar.isUserInteractionEnabled = visible
            bar.accessibilityElementsHidden = !visible
        }
    }
}

/// One split-view hierarchy survives folding/resizing without recreating the
/// thread composer. Compact columns are managed by the system's back gesture.
@available(iOS 17.0, *)
private struct AdaptiveMessagesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var pendingRecipient: String?
    @Binding var state: SMSConversationListState
    @Binding var sender: String?
    @Binding var showingConversation: Bool
    let openConversation: (String) -> Void
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            MessagesView(pendingRecipient: $pendingRecipient, state: $state,
                         openConversation: openConversation)
                .navigationTitle(L10n.t("Short message"))
                .navigationBarTitleDisplayMode(.large)
                .toolbar { SMSConversationListToolbar(state: $state) }
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let sender, showingConversation {
                MessageThreadView(sender: sender)
                    .id(sender)
            } else {
                ContentUnavailableView("Select a conversation", systemImage: "message",
                    description: Text("Select a message from the left, or create a new one."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(horizontalSizeClass == .compact && showingConversation ? .hidden : .automatic, for: .tabBar)
        .onChange(of: showingConversation) { _, showing in
            compactColumn = showing ? .detail : .sidebar
        }
        .onChange(of: compactColumn) { _, column in
            if horizontalSizeClass == .compact && column == .sidebar {
                showingConversation = false
            }
        }
        .onAppear { compactColumn = showingConversation ? .detail : .sidebar }
    }
}


/// Inherit the system Bold Text preference for semantic text throughout the app.
struct PhoneBoldText: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        content.fontWeight(legibilityWeight == .bold ? .bold : nil)
    }
}

/// Explicit point-size fonts need to respond to Bold Text as well.
private struct PhoneAccessibleFont: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight
    var size: CGFloat? = nil
    var style: Font.TextStyle? = nil
    var weight: Font.Weight = .regular
    var design: Font.Design = .default

    private var effectiveWeight: Font.Weight {
        guard legibilityWeight == .bold else { return weight }
        switch weight {
        case .ultraLight, .thin, .light: return .medium
        case .regular: return .semibold
        case .medium: return .bold
        case .semibold, .bold: return .heavy
        default: return .black
        }
    }

    func body(content: Content) -> some View {
        if let size {
            content.font(.system(size: size, weight: effectiveWeight, design: design))
        } else if let style {
            content.font(.system(style, design: design)
                .weight(legibilityWeight == .bold ? .bold : weight))
        } else {
            content.font(.body)
        }
    }
}

extension View {
    func phoneFont(size: CGFloat, weight: Font.Weight = .regular,
                   design: Font.Design = .default) -> some View {
        modifier(PhoneAccessibleFont(size: size, weight: weight, design: design))
    }

    func phoneFont(_ style: Font.TextStyle, design: Font.Design = .default) -> some View {
        modifier(PhoneAccessibleFont(style: style, design: design))
    }
}
