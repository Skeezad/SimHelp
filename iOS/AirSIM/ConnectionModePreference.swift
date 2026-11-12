import Foundation

/// 用户明确选择的连接方式。只有 `automatic` 可以跨传输回退。
enum SimHelpConnectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case vowlan
    case bluetooth
    case cloud
    case automatic
    case localDual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vowlan: return "VoWLAN"
        case .bluetooth: return "Bluetooth"
        case .cloud: return "Cloud"
        case .automatic: return "automatic"
        case .localDual: return "VoWLAN+VoBLE"
        }
    }

    var detail: String {
        switch self {
        case .vowlan: return "Calls are directly connected using Wi-Fi, mobile hotspot or manual VPN address; manual self-check Relay can be used when purely local is turned off"
        case .bluetooth: return "Calls use Bluetooth control and audio; manual self-test Relay can be performed when purely local is turned off"
        case .cloud: return "Only use Relay, PushKit and CallKit"
        case .automatic: return "Automatic selection by availability of VoWLAN, Bluetooth, Cloud"
        case .localDual: return "Calls优先 Wi-Fi、其次蓝牙，途中不Switch音频链路；纯本地关闭时可手动自检 Relay"
        }
    }
}

enum CloudRelayStatusCopy {
    static func text(pureLocal: Bool, cloudOnline: Bool?, usesCloudCalls: Bool) -> String {
        if pureLocal { return "Pure local mode blocked" }
        guard let cloudOnline else { return "尚未检查，可手动自检" }
        let status = cloudOnline ? "Agent online" : "Agent has no valid heartbeat"
        return usesCloudCalls ? status : "Recents自检：\(status)"
    }
}

enum CloudSignalingPreference {
    static let key = "airsim.cloud-signaling-enabled"

    /// Relay/APNs is a notification channel, independent from call media.
    /// It defaults off for a fresh install and is enabled when cloud pairing is
    /// written or the user turns on "Cloud notification".
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: RelayEgressGate.persistenceKey) { return false }
        return false
    }

    static func set(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: key)
    }
}

enum ConnectionModePreference {
    static let key = "airsim.connection-mode"

    /// Kept for source compatibility with older call sites. Local/cloud
    /// notification is now an independent preference and never rewrites the
    /// selected media mode.
    static func selectingLocalOnly(_ enabled: Bool, from mode: SimHelpConnectionMode) -> SimHelpConnectionMode {
        mode
    }

    static func selected(defaults: UserDefaults = .standard) -> SimHelpConnectionMode {
        if let rawValue = defaults.string(forKey: key),
           let mode = SimHelpConnectionMode(rawValue: rawValue) {
            return mode
        }
        // 兼容升级前的两个布尔开关；不在读取时改写，避免测试套件和扩展进程副作用。
        if defaults.bool(forKey: LocalModePreference.key) { return .vowlan }
        if defaults.object(forKey: CloudModePreference.key) != nil,
           !defaults.bool(forKey: CloudModePreference.key) {
            return .vowlan
        }
        return .vowlan
    }

    static func set(
        _ mode: SimHelpConnectionMode,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: key)
        defaults.set(mode == .vowlan, forKey: LocalModePreference.key)
        defaults.set(
            mode == .cloud || mode == .automatic,
            forKey: CloudModePreference.key
        )
    }
}

enum WidgetConnectionModeCycle {
    static func next(after mode: SimHelpConnectionMode, pureLocal: Bool) -> SimHelpConnectionMode {
        let modes: [SimHelpConnectionMode] = pureLocal
            ? [.vowlan, .bluetooth, .localDual]
            : [.vowlan, .bluetooth, .localDual, .cloud, .automatic]
        guard let index = modes.firstIndex(of: mode) else { return modes[0] }
        return modes[(index + 1) % modes.count]
    }
}

/// The user-selected Android agent is a routing constraint, not just UI state.
/// Keeping it independent from the connection mode lets automatic mode choose
/// VoWLAN/VoBLE/cloud for one phone without silently jumping to another phone.
enum AndroidAgentBindingPreference {
    static let key = "airsim.bound-android-agent-id"

    static func selected(defaults: UserDefaults = .standard) -> String? {
        guard let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static func set(_ agentID: String?, defaults: UserDefaults = .standard) {
        let value = agentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty { defaults.removeObject(forKey: key) }
        else { defaults.set(value, forKey: key) }
    }

    static func permits(_ candidate: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let selected = selected(defaults: defaults) else { return true }
        return candidate == selected
    }
}

struct PairedAndroidDeviceRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let deviceName: String
    let agentKind: String?
}

enum PairedAndroidDeviceStore {
    private static let recordsKey = "airsim.paired-android-devices.v1"
    private static let forgottenKey = "airsim.forgotten-android-devices.v1"
    private static let peripheralsKey = "airsim.android-device-peripherals.v1"

    static func records(defaults: UserDefaults = .standard) -> [PairedAndroidDeviceRecord] {
        guard let data = defaults.data(forKey: recordsKey),
              let values = try? JSONDecoder().decode([PairedAndroidDeviceRecord].self, from: data) else { return [] }
        return values.filter { permits($0.id, defaults: defaults) }
    }
    static func remember(_ record: PairedAndroidDeviceRecord, defaults: UserDefaults = .standard) {
        guard !record.id.isEmpty, permits(record.id, defaults: defaults) else { return }
        var values = records(defaults: defaults).filter { $0.id != record.id }
        values.append(record)
        defaults.set(try? JSONEncoder().encode(values), forKey: recordsKey)
    }
    static func forget(_ id: String, defaults: UserDefaults = .standard) {
        var forgotten = Set(defaults.stringArray(forKey: forgottenKey) ?? [])
        forgotten.insert(id)
        defaults.set(Array(forgotten), forKey: forgottenKey)
        defaults.set(try? JSONEncoder().encode(records(defaults: defaults)), forKey: recordsKey)
        if AndroidAgentBindingPreference.selected(defaults: defaults) == id {
            AndroidAgentBindingPreference.set(nil, defaults: defaults)
        }
    }
    static func permits(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        !(defaults.stringArray(forKey: forgottenKey) ?? []).contains(id)
    }
    static func hasForgottenDevices(defaults: UserDefaults = .standard) -> Bool {
        !(defaults.stringArray(forKey: forgottenKey) ?? []).isEmpty
    }
    static func allowPairing(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set((defaults.stringArray(forKey: forgottenKey) ?? []).filter { $0 != id }, forKey: forgottenKey)
    }
    static func rememberPeripheral(_ peripheralID: String, for id: String, defaults: UserDefaults = .standard) {
        var values = defaults.dictionary(forKey: peripheralsKey) as? [String: String] ?? [:]
        values[id] = peripheralID
        defaults.set(values, forKey: peripheralsKey)
    }
    static func permitsPeripheral(_ peripheralID: String, defaults: UserDefaults = .standard) -> Bool {
        let values = defaults.dictionary(forKey: peripheralsKey) as? [String: String] ?? [:]
        return !values.contains { $0.value == peripheralID && !permits($0.key, defaults: defaults) }
    }
    static func peripheralID(for id: String, defaults: UserDefaults = .standard) -> UUID? {
        guard permits(id, defaults: defaults),
              let value = (defaults.dictionary(forKey: peripheralsKey) as? [String: String])?[id] else { return nil }
        return UUID(uuidString: value)
    }
}

struct ConnectionModeRuntimePolicy: Equatable, Sendable {
    let mode: SimHelpConnectionMode

    var startsVoWLAN: Bool { mode == .vowlan || mode == .automatic || mode == .localDual }
    var startsBluetooth: Bool { mode == .bluetooth || mode == .automatic || mode == .localDual }
    var startsCloud: Bool { mode == .cloud || mode == .automatic }
    var allowsCrossModeFallback: Bool { mode == .automatic }

    /// CallKit is a legitimate native presentation for every real transport:
    /// VoWLAN, VoBLE, and cloud. Do not disable it merely because the media is
    /// local; system call UI and audio ownership must stay consistent.
    var usesCallKit: Bool { true }
}

/// 统一拨号路由选择。显式模式绝不借用其他链路；自动模式只在Calls建立前
/// 按 VoWLAN、VoBLE、Cloud顺序选择，建立后仍由 LockedCallTransport 固定。
enum DialRouteSelector {
    static func preferred(
        mode: SimHelpConnectionMode,
        vowlanReady: Bool,
        bluetoothReady: Bool,
        cloudReady: Bool
    ) -> CallTransport? {
        switch mode {
        case .vowlan:
            return vowlanReady ? .vowlan : nil
        case .bluetooth:
            return bluetoothReady ? .bluetooth : nil
        case .cloud:
            return cloudReady ? .cloud : nil
        case .localDual:
            if vowlanReady { return .vowlan }
            return bluetoothReady ? .bluetooth : nil
        case .automatic:
            if vowlanReady { return .vowlan }
            if bluetoothReady { return .bluetooth }
            if cloudReady { return .cloud }
            return nil
        }
    }
}
