import Foundation

struct AppRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let state: String?
        init(name: String, browser_download_url: String, state: String? = "uploaded") {
            self.name = name; self.browser_download_url = browser_download_url; self.state = state
        }
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    let body: String?
}

struct AppUpdateCandidate: Equatable {
    let version: String
    let build: Int
    let page: URL
    let notes: String
    var identity: String { "\(version)#\(build)" }
}

enum AppReleasePolicy {
    static func needsNotes(installed: String, seen: String?) -> Bool { !installed.isEmpty && installed != seen }
    static func checkDue(lastAttempt: Date?, now: Date, manual: Bool, checking: Bool) -> Bool {
        !checking && (manual || lastAttempt == nil || now.timeIntervalSince(lastAttempt!) >= 86_400)
    }
    static func select(_ releases: [AppRelease], installed: String, build: Int) -> AppUpdateCandidate? {
        guard let local = parts(installed) else { return nil }
        var best: AppUpdateCandidate?
        let pattern = "^AirSIM-iOS-([0-9]{1,9}(?:\\.[0-9]{1,9}){2,3})-build([0-9]{1,9})(?:-sideload)?-unsigned\\.ipa$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for release in releases where !release.draft && !release.prerelease {
            let tag = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard let tagParts = parts(tag) else { continue }
            for asset in release.assets {
                guard asset.state == "uploaded",
                      let match = regex.firstMatch(in: asset.name, range: NSRange(asset.name.startIndex..., in: asset.name)),
                      let range = Range(match.range(at: 1), in: asset.name),
                      let remote = parts(String(asset.name[range])), compare(remote, local) >= 0,
                      // App hotfix tags can advance Android's fourth component while
                      // iOS keeps three marketing components and advances its own build.
                      (compare(remote, tagParts) == 0
                        || (tag.split(separator: ".").count == 4 && asset.name[range].split(separator: ".").count == 3
                            && Array(remote.prefix(3)) == Array(tagParts.prefix(3)))),
                      let buildRange = Range(match.range(at: 2), in: asset.name),
                      let remoteBuild = Int(asset.name[buildRange]), remoteBuild > build,
                      let url = URLComponents(string: asset.browser_download_url),
                      url.scheme == "https", url.host == "github.com", url.port == nil,
                      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                      url.percentEncodedPath == "/kai-wu-cortex/AirSIM/releases/download/\(release.tag_name)/\(asset.name)"
                else { continue }
                let version = String(asset.name[range])
                if let best, let previous = parts(best.version),
                   compare(remote, previous) < 0 || (compare(remote, previous) == 0 && remoteBuild <= best.build) { continue }
                guard let page = URL(string: "https://github.com/kai-wu-cortex/AirSIM/releases/tag/\(release.tag_name)") else { continue }
                best = AppUpdateCandidate(version: version, build: remoteBuild, page: page,
                    notes: String((release.body ?? "").prefix(6_000)))
            }
        }
        return best
    }
    private static func parts(_ value: String) -> [Int]? {
        guard value.range(of: "^[0-9]{1,9}(?:\\.[0-9]{1,9}){2,3}$", options: .regularExpression) != nil else { return nil }
        let numbers = value.split(separator: ".").compactMap { Int($0) }
        return numbers + Array(repeating: 0, count: 4 - numbers.count)
    }
    private static func compare(_ a: [Int], _ b: [Int]) -> Int {
        for (left, right) in zip(a, b) where left != right { return left < right ? -1 : 1 }
        return 0
    }
}
