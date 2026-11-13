import SwiftUI

/// AirSIM iPhone/iPad Entrance：Samsung VoWLAN 与独立云端 Relay。
@main
struct AirSIMIPadApp: App {
    // One lazy instance for both scene presentation and background widget intents.
    // Do not wait for onAppear, or create a second transport/CallKit owner.
    private static let productionModel = AppModel()
    @UIApplicationDelegateAdaptor(AirSIMNotificationDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @StateObject private var settings = AppSettings()
    @StateObject private var appUpdates: AppUpdateController
    @Environment(\.scenePhase) private var scenePhase
    private let uiTestDefaults: UserDefaults?

    init() {
#if DEBUG && targetEnvironment(simulator)
        let fixture = SMSNavigationFixture.fromLaunchEnvironment()
        _model = StateObject(wrappedValue: fixture?.model ?? Self.productionModel)
        _appUpdates = StateObject(wrappedValue: fixture?.updates ?? AppUpdateController())
        uiTestDefaults = fixture?.defaults
#else
        _model = StateObject(wrappedValue: Self.productionModel)
        _appUpdates = StateObject(wrappedValue: AppUpdateController())
        uiTestDefaults = nil
#endif
        if uiTestDefaults == nil {
            AirSIMWidgetControlBridge.bootstrap = {
                // A locked cold launch must not overwrite protected history or
                // take ownership away from an incoming PushKit call handler.
                guard UIApplication.shared.isProtectedDataAvailable,
                      !CallKitController.shared.managesCurrentCall else { return }
                _ = Self.productionModel
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.contacts)
                .environmentObject(model.audio)
                .environmentObject(settings)
                .environmentObject(appUpdates)
                .defaultAppStorage(uiTestDefaults ?? .standard)
                .onAppear {
                    guard uiTestDefaults == nil else { return }
                    WatchCallCoordinator.shared.configure(model: model)
                    WatchCallCoordinator.shared.start()
                    model.start(sceneIsActive: scenePhase == .active)
                }
        }
        .onChange(of: scenePhase) { phase in
            guard uiTestDefaults == nil else { return }
            switch phase {
            case .active:
                model.didBecomeActive()
            case .inactive:
                // The audio session must be started before actually entering the background；wait until .background Just started，
                // iOS The process may have been frozen，You will no longer be able to wait for subsequent calls and text messages.。
                model.willResignActive()
            case .background:
                model.didEnterBackground()
            default:
                break
            }
        }
    }
}
