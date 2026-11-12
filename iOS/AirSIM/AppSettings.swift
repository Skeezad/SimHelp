import SwiftUI
import UIKit

enum AppInformation {
    // SimHelp personal build: no vendor update or telemetry endpoint.
    static let repositoryURL = URL(string: "about:blank")!
    static let releasesURL = repositoryURL
    static var version: String { version(info: Bundle.main.infoDictionary ?? [:]) }

    static func version(info: [String: Any]) -> String {
        let name = (info["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let build = (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let build else { return name ?? "Unknown version" }
        return "\(name ?? "UnknownVersion") (\(build))"
    }
}

/// 集中提供移动device名称, 避免 iPhone 上继续出现硬编码的 iPad 文案. 
enum DeviceContext {
    static var displayName: String {
        UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
    }

    static var symbolName: String {
        UIDevice.current.userInterfaceIdiom == .phone ? "iphone" : "ipad"
    }
}

/// iPhone/iPad 端保留 Mac 版的外观选项. 
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.t("Follow the system")
        case .light: return L10n.t("light color")
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.t("Follow the system")
        case .zh: return "English"
        case .en: return "English"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: L10n.appearanceKey) }
    }
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: L10n.languageKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = AppAppearance(rawValue: defaults.string(forKey: L10n.appearanceKey) ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: L10n.languageKey) ?? "") ?? .system
    }
}

///  and  Mac 版一致的轻量本地化方案, 避免首版引入重复字符串资源. 
enum L10n {
    static let appearanceKey = "airsim.appearance"
    static let languageKey = "airsim.language"

    static var effectiveLanguage: AppLanguage {
        let saved = AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .system
        if saved != .system { return saved }
        return .en
    }

    static func t(_ key: String) -> String {
        guard effectiveLanguage == .en else { return key }
        return english[key] ?? key
    }

    private static let english: [String: String] = [
        "dial": "Dial", "Recents": "Recents", "recent calls": "Recents", "Short message": "Messages", "Contact person": "Contacts", "Contacts": "Contacts", "set up": "Settings",
        "Enter number": "Enter number", "Answer": "Accept", "Reject": "Decline", "hang up": "End", "mute": "Mute",
        "Unmute": "Unmute", "speaker": "Speaker", "recording": "Record", "Stop recording": "Stop Recording", "In call": "On Call",
        "Waiting to answer": "Waiting", "No call records yet": "No Recents", "new information": "New Message", "recipient": "To",
        "SMS content": "Message", "send": "Send", "Sent": "Sent", "Cancel": "Cancel", "Refresh": "Refresh", "No SMS yet": "No Messages",
        "Automatically clean module text messages after reading": "Auto-clean module SMS after reading", "Clear all text messages": "Clear all SMS",
        "Search for a name or number": "Search name or number", "Grant access to Contacts": "Allow Contacts Access", "Address book is empty": "No contacts",
        "Search names, numbers or text messages": "Search name, number or message", "No matching text message found": "No matching messages",
        "state": "Status", "Universal": "General", "network": "Network", "position": "Location", "eSIM / Card": "eSIM / Card",
        "AT debugging": "AT Debug", "Network diagnostics": "Network Diagnostics", "Operator": "Operator", "SIM card": "SIM Card",
        "network mode": "Network Mode", "signal strength": "Signal", "Download speed": "Download", "upload speed": "Upload",
        "This traffic": "Session Data", "Allow 4G Internet access": "Allow 4G Data", "Check 4G outlet": "Check 4G Route",
        "Check proxy exit": "Check Proxy Route", "Restart module": "Reboot Module", "GPS positioning": "GPS Positioning",
        "Waiting for positioning": "Waiting for fix", "coordinate": "Coordinates", "satellite": "Satellites", "Card type": "Card Type",
        "Download new profile": "Download New Profile", "Address book detection": "Phonebook Check", "AT command": "AT Command",
        "Send AT": "Send AT", "Appearance": "Appearance", "display mode": "Display Mode", "language": "Language", "Follow the system": "Follow System",
        "light color": "Light", "Dark": "Dark", "module agent": "Module Agent", "online": "Online", "Offline": "Offline",
        "Not viewed": "Unseen", "Mark as read": "Mark as Read", "Mark all as read": "Mark All as Read",
        "%d unread SMS": "%d unread messages",
        "Missed": "Missed", "Incoming call": "Incoming", "exhale": "Outgoing", "Processing": "Working", "keep": "Save",
        "delete": "Delete", "switch": "Switch", "Rename": "Rename", "Error": "Error",
        "Clear": "Clear", "Clear number": "Clear number",
        "copy": "Copy", "Select text": "Select", "More…": "More…",
        "Select SMS": "Select Message", "Deselect": "Cancel Selection",
        "Delete selected text messages": "Delete Selected Messages", "Share selected text messages": "Share Selected Messages",
        "%d items selected": "%d Selected", "Delete selected %d SMS?": "Delete %d Messages?",
        "Copy latest text message": "Copy Latest Message", "Copy entire conversation": "Copy Conversation",
        "Copy SMS": "Copy Messages",
        "SMS operation": "Message Actions", "Select session": "Select Conversations",
        "Complete selection": "Done", "Delete selected conversations": "Delete Selected Conversations",
        "1 text message": "1 Message", "%d text messages": "%d Messages",
        "Only the records in SimHelp on this iPhone will be deleted, and the Android text messages will not be deleted.": "Only deletes records in SimHelp on this iPhone, not SMS on Android."
    ]
}
