import SwiftUI

@main
struct SimHelpWatchApp: App {
    @StateObject private var callSession = WatchCallSession()

    var body: some Scene {
        WindowGroup {
            WatchCallView()
                .environmentObject(callSession)
        }
    }
}
