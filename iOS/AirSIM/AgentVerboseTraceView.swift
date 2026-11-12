import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct AgentVerboseShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct AgentVerboseShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                        y: controller.view.bounds.midY,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AgentVerboseTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum AgentVerboseTraceFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case failures = "错误"
    case calls = "通话"
    case relay = "Relay / 云端"
    case vowlan = "VoWLAN"
    case voble = "VoBLE"
    case sms = "短信"

    var id: String { rawValue }

    func matches(source: String, category: String, isFailure: Bool) -> Bool {
        let category = category.lowercased()
        switch self {
        case .all: return true
        case .failures: return isFailure
        case .calls:
            return ["voice", "cloud-call", "cloud-call-control", "cloud-call-audio",
                    "cloud-media-health", "relay", "voble", "call-audio",
                    "callkit-audio", "call_transport"].contains(category)
        case .relay:
            return source == "RELAY" || category == "relay" || category.hasPrefix("cloud")
        case .vowlan: return ["vowlan", "call-audio"].contains(category)
        case .voble: return ["voble", "bluetooth"].contains(category)
        case .sms: return category == "sms"
        }
    }
}

private struct AgentVerboseTimelineItem: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let source: String
    let category: String
    let traceID: String?
    let title: String
    let detail: String
    let isFailure: Bool

    var systemImage: String {
        if isFailure { return "exclamationmark.triangle.fill" }
        switch category.lowercased() {
        case "vowlan": return "wifi"
        case "voble", "bluetooth": return "antenna.radiowaves.left.and.right"
        case "sms": return "message.fill"
        case "http": return "arrow.left.arrow.right"
        case "voice", "cloud-call", "cloud-call-control": return "waveform"
        case "relay": return "network"
        default: return source == "APP" ? "iphone" : "cpu"
        }
    }

    var tint: Color {
        if isFailure { return .red }
        switch category.lowercased() {
        case "vowlan": return .green
        case "voble", "bluetooth": return .cyan
        case "sms": return .green
        case "voice", "cloud-call", "cloud-call-control": return .purple
        case "relay": return .indigo
        case "http": return .blue
        default: return .secondary
        }
    }
}

@MainActor
final class AgentVerboseTraceViewModel: ObservableObject {
    @Published var enabled = false
    @Published var localEntries: [AgentVerboseTraceEntry] = []
    @Published var agentEvents: [ModuleDebugEvent] = []
    @Published var agentState = "仅本机日志"
    @Published private(set) var readingAgent = false
    @Published var errorMessage: String?
    @Published var exportText = "SimHelp Agent Verbose Trace\n"

    private let api: SimHelpAPI?
    private let recorder: AgentVerboseTraceRecorder
    private var lastSequence: UInt64 = 0
    private var clearGeneration = 0

    init(api: SimHelpAPI?, recorder: AgentVerboseTraceRecorder = .shared) {
        self.api = api; self.recorder = recorder
    }

    var canReadAgent: Bool { api != nil && !readingAgent }

    func run() async {
        enabled = await recorder.isEnabled()
        await refresh()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(enabled ? 1 : 2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        Task {
            await recorder.setEnabled(value)
            await refresh()
        }
    }

    func refresh() async {
        localEntries = await recorder.snapshot()
        await rebuildExport()
    }

    // Remote reads are opt-in, not a one-second HTTP/Relay polling loop.
    func readAgent() async {
        guard let api, !readingAgent else { return }
        readingAgent = true
        defer { readingAgent = false }
        let generation = clearGeneration
        do {
            let snapshot = try await api.moduleDebug(after: lastSequence, limit: 600)
            guard generation == clearGeneration else { return }
            merge(snapshot.events)
            lastSequence = max(lastSequence, snapshot.debug.latestSequence)
            agentState = "Agent \(snapshot.agent.version) · seq \(snapshot.debug.latestSequence)"
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == clearGeneration else { return }
            agentState = "Agent 不可达"
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func clear() async {
        clearGeneration &+= 1
        await recorder.clear()
        localEntries = []
        agentEvents = []
        lastSequence = 0
        agentState = "本机日志已清除（不修改安卓日志）"
        errorMessage = nil
        await refresh()
    }

    /// Materialize the export outside SwiftUI's FileDocument machinery. The
    /// share sheet only needs a stable file URL and cannot race the once-per-second
    /// trace refresh.
    func writeExportFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimHelp-Verbose-\(Int(Date().timeIntervalSince1970)).txt")
        try Data(exportText.utf8).write(to: url, options: .atomic)
        return url
    }

    fileprivate var timeline: [AgentVerboseTimelineItem] {
        let local = localEntries.map { entry in
            let fields = (entry.fields ?? [:])
                .filter { $0.key != "trace_id" }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " · ")
            let detail = [fields, entry.detail]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return AgentVerboseTimelineItem(
                id: "app-\(entry.id.uuidString)",
                timestamp: entry.timestamp,
                source: entry.source ?? "APP",
                category: entry.category ?? "http",
                traceID: entry.traceID == "--------" ? nil : entry.traceID,
                title: "\(entry.method) \(entry.path)",
                detail: entry.elapsedMilliseconds.map { "\(detail) · \($0) ms" } ?? detail,
                isFailure: entry.stage == .failure
            )
        }
        let remote = agentEvents.compactMap { event -> AgentVerboseTimelineItem? in
            if event.category == "http", event.summary.hasPrefix("GET /api/debug") { return nil }
            let fields = event.fields ?? [:]
            let fieldText = fields
                .filter { $0.key != "trace_id" }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " · ")
            let parts = [event.direction, fieldText, event.payload]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
            let statusFailure = Int(fields["status"] ?? "").map { $0 >= 400 } ?? false
            return AgentVerboseTimelineItem(
                id: "agent-\(event.sequence)",
                timestamp: Self.parse(event.timestamp),
                source: "AGENT",
                category: event.category,
                traceID: fields["trace_id"],
                title: event.summary,
                detail: parts.joined(separator: "\n"),
                isFailure: event.direction == "error" || statusFailure
            )
        }
        return (local + remote).sorted {
            if $0.timestamp == $1.timestamp { return $0.id < $1.id }
            return $0.timestamp < $1.timestamp
        }
    }

    private func merge(_ newEvents: [ModuleDebugEvent]) {
        let known = Set(agentEvents.map(\.sequence))
        agentEvents.append(contentsOf: newEvents.filter { !known.contains($0.sequence) })
        if agentEvents.count > 2_000 { agentEvents.removeFirst(agentEvents.count - 2_000) }
    }

    private func rebuildExport() async {
        let remote = agentEvents.map {
            AgentVerboseRemoteEvent(
                sequence: $0.sequence,
                timestamp: $0.timestamp,
                category: $0.category,
                direction: $0.direction ?? "",
                summary: $0.summary,
                payload: $0.payload ?? "",
                fields: $0.fields ?? [:]
            )
        }
        exportText = await recorder.exportText(agentEvents: remote)
    }

    private static func parse(_ value: String) -> Date {
        if let date = fractionalFormatter.date(from: value) { return date }
        return wholeFormatter.date(from: value) ?? .distantPast
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct AgentVerboseTraceView: View {
    @StateObject private var model: AgentVerboseTraceViewModel
    @State private var filter: AgentVerboseTraceFilter = .all
    @State private var selectedItem: AgentVerboseTimelineItem?
    @State private var showingClearConfirmation = false
    @State private var shareItem: AgentVerboseShareItem?

    init(api: SimHelpAPI? = nil) {
        _model = StateObject(wrappedValue: AgentVerboseTraceViewModel(api: api))
    }

    var body: some View {
        List {
                Section {
                    Toggle(isOn: Binding(get: { model.enabled }, set: model.setEnabled)) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Verbose 模式")
                                Text(model.enabled ? "记录通话、VoWLAN、VoBLE 与云端链路事件" : "关闭详细采集，保留基础音频启动记录")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(model.enabled ? .orange : .secondary)
                        }
                    }

                    LabeledContent("Agent 通道", value: model.agentState)
                    LabeledContent("本机链路", value: "\(model.localEntries.count) 条")
                    LabeledContent("Agent 事件", value: "\(model.agentEvents.count) 条")
                    Button {
                        Task { await model.readAgent() }
                    } label: {
                        HStack {
                            Label("手动读取安卓日志", systemImage: "arrow.down.doc")
                            if model.readingAgent { ProgressView() }
                        }
                    }
                    .disabled(!model.canReadAgent)
                } header: {
                    Text("链式调试")
                } footer: {
                    Text("本机日志支持蓝牙及离线记录，不自动请求 Relay 或安卓。手动读取需有已验证的 VoWLAN 连接。日志可能包含电话号码、短信正文和设备标识；排查结束后请关闭 Verbose，分享前检查内容。")
                }

                Section {
                    Picker("筛选", selection: $filter) {
                        ForEach(AgentVerboseTraceFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("实时命令链路") {
                    if filteredTimeline.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("暂无链路事件").font(.headline)
                            Text(model.enabled ? "执行拨号、短信、设置或 AT 操作后会实时显示。" : "请先开启 Verbose 链路模式。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(filteredTimeline) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                timelineRow(item)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .contextMenu {
                                Button("复制本条", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = "\(item.title)\n\(item.detail)"
                                }
                            }
                        }
                    }
                }
        }
        .navigationTitle("Verbose 日志调试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        await model.refresh()
                        do {
                            shareItem = AgentVerboseShareItem(url: try model.writeExportFile())
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享 TXT 调试日志")
                Button(role: .destructive) { showingClearConfirmation = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task { await model.run() }
        .refreshable { await model.refresh() }
        .sheet(item: $shareItem, onDismiss: {
            if let url = shareItem?.url { try? FileManager.default.removeItem(at: url) }
            shareItem = nil
        }) { item in
            AgentVerboseShareSheet(url: item.url)
        }
        .sheet(item: $selectedItem) { item in
            AgentVerboseTraceDetailView(item: item)
        }
        .confirmationDialog("清除本机调试日志？不会删除安卓日志、短信或通话记录。", isPresented: $showingClearConfirmation) {
            Button("清除本机日志", role: .destructive) { Task { await model.clear() } }
            Button("取消", role: .cancel) {}
        }
    }

    private var filteredTimeline: [AgentVerboseTimelineItem] {
        model.timeline.filter { item in
            filter.matches(source: item.source, category: item.category, isFailure: item.isFailure)
        }
    }

    private func timelineRow(_ item: AgentVerboseTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(item.tint)
                .frame(width: 28, height: 28)
                .background(item.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.source)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.source == "APP" ? .blue : .purple)
                    Text(Self.timeFormatter.string(from: item.timestamp))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let traceID = item.traceID {
                        Text("#\(traceID)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isFailure ? .red : .primary)
                    .lineLimit(2)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

private struct AgentVerboseTraceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: AgentVerboseTimelineItem

    var body: some View {
        NavigationStack {
            List {
                Section("事件") {
                    LabeledContent("来源", value: item.source)
                    LabeledContent("分类", value: item.category)
                    if let traceID = item.traceID { LabeledContent("Trace ID", value: traceID) }
                    LabeledContent("时间", value: item.timestamp.formatted(.iso8601))
                }
                Section("命令") {
                    Text(item.title).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                if !item.detail.isEmpty {
                    Section("完整内容") {
                        Text(item.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("链路详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = "\(item.title)\n\(item.detail)"
                    }
                }
            }
        }
    }
}
