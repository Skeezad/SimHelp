import SwiftUI
import WidgetKit

struct SimHelpDeviceWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SimHelpWidgetSnapshot
}
struct SimHelpDeviceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimHelpDeviceWidgetEntry {
        .init(date: Date(), snapshot: .preview())
    }
    func getSnapshot(in context: Context, completion: @escaping (SimHelpDeviceWidgetEntry) -> Void) {
        completion(.init(date: Date(), snapshot: context.isPreview ? .preview() : SimHelpWidgetStore().load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimHelpDeviceWidgetEntry>) -> Void) {
        let now = Date(), snapshot = SimHelpWidgetStore().load()
        let entries = ([now] + snapshot.expirationDates(after: now)).map {
            SimHelpDeviceWidgetEntry(date: $0, snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}
struct SimHelpDeviceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SimHelpWidgetSnapshot.kind, provider: SimHelpDeviceWidgetProvider()) { entry in
            SimHelpDeviceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("安卓设备与最近通话")
        .description("Check the recently synchronized connection status and quickly open dialing, text messages and contacts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
private struct SimHelpDeviceWidgetEntryView: View {
    let entry: SimHelpDeviceWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        } else {
            content.padding(family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular ? 0 : 16)
                .background(family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular
                            ? Color.clear : Color(uiColor: .systemBackground))
        }
    }
    private var content: some View {
        SimHelpDeviceWidgetView(snapshot: entry.snapshot, date: entry.date, family: family)
    }
}
