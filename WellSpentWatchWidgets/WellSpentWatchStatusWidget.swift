import SwiftUI
import WellSpentWatchStore
import WidgetKit

struct WellSpentWatchStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WellSpentWatchStatusEntry {
        WellSpentWatchStatusEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WellSpentWatchStatusEntry) -> Void) {
        // Gallery previews never read a real project, even after privacy opt-in.
        completion(context.isPreview ? placeholder(in: context) : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WellSpentWatchStatusEntry>) -> Void) {
        let entry = loadEntry()
        let dates = entry.state?.timelineDates(from: entry.date) ?? [entry.date]
        completion(
            Timeline(
                entries: dates.map { WellSpentWatchStatusEntry(date: $0, state: entry.state) },
                policy: .after(entry.date.addingTimeInterval(30 * 60))
            ))
    }

    private func loadEntry() -> WellSpentWatchStatusEntry {
        let state = try? WatchWidgetSnapshotReader().read()
        return WellSpentWatchStatusEntry(date: .now, state: state)
    }
}

struct WellSpentWatchStatusWidget: Widget {
    let kind = WatchWidgetState.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WellSpentWatchStatusProvider()) { entry in
            WellSpentWatchStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("WellSpent")
        .description("See billable time, paused status, or recent projects. Names stay private by default.")
        .supportedFamilies([
            .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular,
        ])
    }
}
