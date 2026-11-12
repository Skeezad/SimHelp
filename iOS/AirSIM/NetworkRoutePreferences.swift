import Foundation

/// 用户在设置页追加的私有网段。内置 RFC1918 / 链路本地 / Tailscale CGNAT
/// 仍然默认生效；这里只做补充，不会让公网地址变成可信地址。
enum NetworkRoutePreferences {
    static let prefixesKey = "airsim.private-prefixes"

    struct Prefix: Equatable, Hashable, Sendable {
        let network: UInt32
        let bits: Int

        func contains(_ address: UInt32) -> Bool {
            guard bits > 0 else { return true }
            if bits >= 32 { return address == network }
            let mask: UInt32 = ~UInt32(0) << UInt32(32 - bits)
            return address & mask == network & mask
        }

        var text: String {
            "\(Self.format(network))/\(bits)"
        }

        static func format(_ value: UInt32) -> String {
            "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
        }
    }

    static func parseIPv4(_ host: String) -> UInt32? {
        let parts = host.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  !(part.count > 1 && part.first == "0"),
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let byte = UInt32(part), byte <= 255 else { return nil }
            value = (value << 8) | byte
        }
        return value
    }

    static func parse(_ text: String) -> Prefix? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        let slash = value.firstIndex(of: "/")
        let host = slash == nil ? value : String(value[value.startIndex..<slash!])
        var bits = 32
        if let slash {
            let raw = value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, raw.count <= 2, raw.allSatisfy({ $0.isNumber }),
                  let parsed = Int(raw), parsed <= 32 else { return nil }
            bits = parsed
        }
        guard let network = parseIPv4(host) else { return nil }
        let mask: UInt32 = bits <= 0 ? 0 : (bits >= 32 ? ~UInt32(0) : ~UInt32(0) << UInt32(32 - bits))
        return Prefix(network: network & mask, bits: bits)
    }

    static func parseAll(_ text: String) -> [Prefix] {
        var values: [Prefix] = []
        for item in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }) {
            guard let prefix = parse(String(item)), !values.contains(prefix) else { continue }
            values.append(prefix)
        }
        return values
    }

    static func storedText(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: prefixesKey) ?? ""
    }

    static func stored(defaults: UserDefaults = .standard) -> [Prefix] {
        parseAll(storedText(defaults: defaults))
    }

    static func save(_ text: String, defaults: UserDefaults = .standard) {
        defaults.set(text.trimmingCharacters(in: .whitespacesAndNewlines), forKey: prefixesKey)
    }

    /// 公网地址始终拒绝；内置私网与用户追加网段一起判定。
    static func permitsPrivateIPv4(_ host: String, custom: [Prefix]) -> Bool {
        guard let value = parseIPv4(host) else { return false }
        let first = UInt8((value >> 24) & 0xFF)
        let second = UInt8((value >> 16) & 0xFF)
        if first == 10 || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168) {
            return true
        }
        if first == 169 && second == 254 { return true }
        if first == 100 && (64...127).contains(second) { return true }
        // 127/8 只用于回环，手动配对不接受；自定义网段也不能把它放进来。
        if first == 127 { return false }
        return custom.contains { $0.contains(value) }
    }
}
