import SwiftUI

/// SimHelp iPhone/iPad entry: 三星 VoWLAN  and separateCloud Relay. 
@main
struct SimHelpIPadApp: App {
    // One lazy instance for both scene presentation and background widget intents.
    // Do not wait for onAppear, or create a second transport/CallKit owner.
    private static let productionModel = AppModel()
    @UIApplicationDelegateAdaptor(SimHelpNotificationDelegate.self) private var appDelegate
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
            SimHelpWidgetControlBridge.bootstrap = {
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
                // 必须在真正进入后台前启动Audio会话; 等到 .background 才启动时, 
                // iOS can 能already 经冻结进程, 后续Incoming call and SMS事件便无法继续等待. 
                model.willResignActive()
            case .background:
                model.didEnterBackground()
            default:
                break
            }
        }
    }
}
