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
        needsNotes = AppReleasePolicy.needsNotes(installed: "\(installed)#\(build)",
            seen: defaults.string(forKey: "airsim.app-update.notes-seen"))
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
        status = "Updates are disabled in this personal build."
        return AppUpdateResult(message: status, candidate: nil)
        /*
        guard AppReleasePolicy.checkDue(lastAttempt: defaults.object(forKey: "airsim.app-update.attempt") as? Date,
            now: now(), manual: manual, checking: checking) else { return nil }
        checking = true
        defaults.set(now(), forKey: "airsim.app-update.attempt") // Failures are throttled too.
        defer { checking = false }
        do {
            let releases = try await fetch()
            try Task.checkCancellation()
            let candidate = AppReleasePolicy.select(releases, installed: installed, build: build)
            pendingUpdate = candidate.flatMap {
                defaults.string(forKey: "airsim.app-update.notified") == $0.identity ? nil : $0
            }
            status = candidate.map { "发现应用新版 \($0.version)（\($0.build)）" }
                ?? "未发现比Current更新的公开应用版本"
            return AppUpdateResult(message: status, candidate: candidate)
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled { return nil }
            status = "Check failed, please check the network or try again later; this does not mean you are up to date."
            return AppUpdateResult(message: status, candidate: nil)
        }
        */
    }
}

enum AppReleaseClient {
    static func fetch() async throws -> [AppRelease] {
        throw URLError(.unsupportedURL)
        /* let url = URL(string: "https://api.github.com/repos/kai-wu-cortex/SimHelp/releases?per_page=100")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SimHelp-App-Update", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == "api.github.com" else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in stream {
            guard data.count < 4 * 1_024 * 1_024 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return try await Task.detached(priority: .utility) {
            try JSONDecoder().decode([AppRelease].self, from: data)
        }.value */
    }
}
