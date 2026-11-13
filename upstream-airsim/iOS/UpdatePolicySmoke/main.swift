import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ why: String) {
    checks += 1
    guard value() else { fatalError(why) }
}
func release(_ tag: String, _ asset: String, draft: Bool = false, beta: Bool = false,
             host: String = "https://github.com/kai-wu-cortex/AirSIM/releases/download") -> AppRelease {
    AppRelease(tag_name: tag, draft: draft, prerelease: beta,
        assets: [.init(name: asset, browser_download_url: "\(host)/\(tag)/\(asset)")], body: "notes")
}
check(AppReleasePolicy.needsNotes(installed: "0.9.8#92", seen: nil), "first install notes missing")
check(!AppReleasePolicy.needsNotes(installed: "0.9.8#92", seen: "0.9.8#92"), "notes repeated")
check(AppReleasePolicy.needsNotes(installed: "0.9.8#93", seen: "0.9.8#92"), "new build notes missing")
let now = Date(timeIntervalSince1970: 100_000)
check(AppReleasePolicy.checkDue(lastAttempt: nil, now: now, manual: false, checking: false), "initial check")
check(!AppReleasePolicy.checkDue(lastAttempt: now, now: now.addingTimeInterval(1), manual: false, checking: false), "no polling")
check(AppReleasePolicy.checkDue(lastAttempt: now, now: now.addingTimeInterval(86_400), manual: false, checking: false), "daily check")
check(AppReleasePolicy.checkDue(lastAttempt: now, now: now, manual: true, checking: false), "manual check")
check(!AppReleasePolicy.checkDue(lastAttempt: nil, now: now, manual: true, checking: true), "single-flight check")
check(!AppReleasePolicy.checkDue(lastAttempt: now.addingTimeInterval(1), now: now, manual: false, checking: false), "clock rollback")
let stable = release("v0.10.0", "AirSIM-iOS-0.10.0-build100-sideload-unsigned.ipa")
let old = release("v0.9.8", "AirSIM-iOS-0.9.8-build92-unsigned.ipa")
let agent = release("v9.0.0", "airsim-avf-agent_9.0.0-1_arm64.deb")
let android = release("v8.0.0", "AirSIM-Android-Standalone-8.0.0.apk")
let draft = release("v7.0.0", "AirSIM-iOS-7.0.0-build105-unsigned.ipa", draft: true)
let beta = release("v6.0.0", "AirSIM-iOS-6.0.0-build106-unsigned.ipa", beta: true)
let found = AppReleasePolicy.select([agent, android, old, stable, draft, beta], installed: "0.9.8", build: 92)
check(found?.version == "0.10.0", "numeric order/platform/stable filtering")
check(found?.page.absoluteString == "https://github.com/kai-wu-cortex/AirSIM/releases/tag/v0.10.0", "canonical page")
check(AppReleasePolicy.select([old], installed: "0.9.8", build: 94) == nil, "no build downgrade")
let rebuild = release("v0.9.8", "AirSIM-iOS-0.9.8-build95-unsigned.ipa")
check(AppReleasePolicy.select([rebuild], installed: "0.9.8", build: 94)?.build == 95, "same version newer build")
let hotfix = release("v0.9.8.1", "AirSIM-iOS-0.9.8-build95-sideload-unsigned.ipa")
check(AppReleasePolicy.select([hotfix], installed: "0.9.8", build: 94)?.build == 95,
      "app hotfix tag must recognize unchanged iOS marketing version with a new build")
check(AppReleasePolicy.select([hotfix], installed: "0.9.8", build: 94)?.page.absoluteString
      == "https://github.com/kai-wu-cortex/AirSIM/releases/tag/v0.9.8.1", "hotfix must link its real release")
check(AppReleasePolicy.select([rebuild], installed: "unknown", build: 94) == nil, "unknown installed version")
check(AppReleasePolicy.select([release("v1.0.0", "AirSIM-iOS-0.9.8-build99-unsigned.ipa")], installed: "0.9.8", build: 92) == nil, "tag/asset mismatch")
check(AppReleasePolicy.select([release("v1.0.0", "AirSIM-iOS-1.0.0-build99-unsigned.ipa", host: "https://evil.invalid")], installed: "0.9.8", build: 92) == nil, "untrusted host")
check(AppReleasePolicy.select([release("v1.0.0", "AirSIM-iOS-1.0.0-build90-unsigned.ipa")], installed: "0.9.8", build: 92) == nil, "known lower build")
let pendingAsset = AppRelease(tag_name: "v1.0.0", draft: false, prerelease: false,
    assets: [.init(name: "AirSIM-iOS-1.0.0-build100-unsigned.ipa", browser_download_url:
        "https://github.com/kai-wu-cortex/AirSIM/releases/download/v1.0.0/AirSIM-iOS-1.0.0-build100-unsigned.ipa", state: "starter")], body: nil)
check(AppReleasePolicy.select([pendingAsset], installed: "0.9.8", build: 92) == nil, "unfinished upload must not be offered")
do {
    _ = try JSONDecoder().decode([AppRelease].self, from: Data("{\"message\":\"API rate limit exceeded\"}".utf8))
    check(false, "GitHub error object must not parse as no updates")
} catch { check(true, "error rejected") }
print("AppReleasePolicy: \(checks) checks passed")

// Exercise persistent side effects and transport failures, not view/source text.
let suite = "AirSIM.UpdateTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
var requests = 0
let controller = await MainActor.run {
    AppUpdateController(defaults: defaults, installed: "0.9.8", build: 92, now: { now }, fetch: {
        requests += 1; return [stable]
    })
}
await MainActor.run {
    check(controller.needsNotes, "notes pending before actual display")
    controller.acknowledgeNotes()
    check(!controller.needsNotes, "acknowledged notes remain pending")
    check(!AppUpdateController(defaults: defaults, installed: "0.9.8", build: 92).needsNotes,
          "acknowledgement must survive process recreation")
    check(AppUpdateController(defaults: defaults, installed: "0.9.8", build: 93).needsNotes,
          "new build must show notes despite same marketing version")
}
let result = await controller.check(manual: false)
check(result?.candidate?.build == 100, "transport result not surfaced")
_ = await controller.check(manual: false)
check(requests == 1, "repeated foreground requests")
_ = await controller.check(manual: true)
check(requests == 2, "manual check must bypass cooldown")
await MainActor.run { controller.acknowledgeUpdate(result!.candidate!) }
let pending = controller.pendingUpdate
check(pending == nil, "same update must not be automatically repeated")
let failingSuite = "AirSIM.UpdateTests.\(UUID().uuidString)"
let failingDefaults = UserDefaults(suiteName: failingSuite)!
let failure = await MainActor.run {
    AppUpdateController(defaults: failingDefaults, installed: "0.9.8", build: 92, now: { now }, fetch: {
        throw URLError(.notConnectedToInternet)
    })
}
let failed = await failure.check(manual: true)
check(failed != nil && failed?.candidate == nil && failed?.message.contains("失败") == true,
      "offline failure must not claim latest version")
let automaticRetry = await failure.check(manual: false)
check(automaticRetry == nil, "failure must not trigger foreground request storm")

// A suspended real controller operation proves coalescing while transport is in flight.
let concurrentSuite = "AirSIM.UpdateTests.\(UUID().uuidString)"
let concurrentDefaults = UserDefaults(suiteName: concurrentSuite)!
var waiting: CheckedContinuation<[AppRelease], Never>?
let concurrent = await MainActor.run {
    AppUpdateController(defaults: concurrentDefaults, installed: "0.9.8", build: 92, now: { now }, fetch: {
        await withCheckedContinuation { waiting = $0 }
    })
}
let inFlight = Task { await concurrent.check(manual: false) }
for _ in 0..<10_000 { if waiting != nil { break }; await Task.yield() }
check(waiting != nil, "fixture transport did not enter")
let duplicate = await concurrent.check(manual: true)
check(duplicate == nil && concurrent.checking, "manual duplicate must join/skip while checking")
waiting!.resume(returning: [stable])
let completed = await inFlight.value
check(completed?.candidate?.build == 100 && !concurrent.checking, "single in-flight result missing")
var inbox = AppUpdateResultInbox()
inbox.receive(completed!) // Transport returned after a call began.
check(inbox.takeIfIdle(isActive: true, callBusy: true, hasModal: false) == nil,
      "late manual result must not cover a call")
check(inbox.takeIfIdle(isActive: false, callBusy: false, hasModal: false) == nil,
      "manual result must not present in background")
check(inbox.takeIfIdle(isActive: true, callBusy: false, hasModal: true) == nil,
      "manual result must wait for another sheet")
check(inbox.takeIfIdle(isActive: true, callBusy: false, hasModal: false)?.candidate?.build == 100,
      "delayed result must survive call/background/modal and show once idle")
check(inbox.takeIfIdle(isActive: true, callBusy: false, hasModal: false) == nil,
      "manual result must not be shown twice")
defaults.removePersistentDomain(forName: suite)
failingDefaults.removePersistentDomain(forName: failingSuite)
concurrentDefaults.removePersistentDomain(forName: concurrentSuite)
print("App updates including lifecycle: \(checks) checks passed")
