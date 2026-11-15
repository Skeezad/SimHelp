import Foundation
import Combine

struct AppUpdateResult {
    let message: String
    let candidate: AppUpdateCandidate?
}

struct AppUpdateResultInbox {
    private var pending: AppUpdateResult?
    mutating func receive(_ result: AppUpdateResult) { pending = result }
    mutating func takeIfIdle(isActive: Bool, callBusy: Bool, hasModal: Bool) -> AppUpdateResult? {
        guard isActive, !callBusy, !hasModal else { return nil }
        defer { pending = nil }
        return pending
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var status = "Haven't checked for app updates yet"
    @Published private(set) var pendingUpdate: AppUpdateCandidate?
    @Published private(set) var needsNotes: Bool
    let installed: String
    let build: Int
    private let defaults: UserDefaults
    private let fetch: () async throws -> [AppRelease]
    private let now: () -> Date

    init(defaults: UserDefaults = .standard,
         installed: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         build: Int = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0,
         now: @escaping () -> Date = Date.init,
         fetch: @escaping () async throws -> [AppRelease] = AppReleaseClient.fetch) {
        self.defaults = defaults; self.installed = installed; self.build = build
        self.now = now; self.fetch = fetch
        needsNotes = false
    }

    func acknowledgeNotes() {
        defaults.set("\(installed)#\(build)", forKey: "airsim.app-update.notes-seen")
        needsNotes = false
    }
    func acknowledgeUpdate(_ candidate: AppUpdateCandidate) {
        defaults.set(candidate.identity, forKey: "airsim.app-update.notified")
        if pendingUpdate == candidate { pendingUpdate = nil }
    }
    func check(manual: Bool) async -> AppUpdateResult? {
        // Update checking and announcements are disabled in this build.
        return nil
    }
}

enum AppReleaseClient {
    static func fetch() async throws -> [AppRelease] {
        return []
    }
}
