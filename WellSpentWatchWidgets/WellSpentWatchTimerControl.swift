import AppIntents
import SwiftUI
import WellSpentWatchStore
import WidgetKit

struct WellSpentWatchControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: WellSpentWatchFavoriteConfiguration) -> WatchSystemControlValue {
        .make(state: nil, favoriteID: nil, availableIDs: [])
    }

    @MainActor
    func currentValue(configuration: WellSpentWatchFavoriteConfiguration) async throws -> WatchSystemControlValue {
        guard let reader = try? WatchWidgetSnapshotReader(), let state = try? reader.read() else {
            return .make(state: nil, favoriteID: nil, availableIDs: [])
        }
        return .make(
            state: state, favoriteID: configuration.project?.id,
            availableIDs: Set(try reader.readProjectChoices().map(\.id)))
    }
}

struct WellSpentWatchTimerControl: ControlWidget {
    static let kind = "WellSpentWatchTimerControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: WellSpentWatchControlProvider()) { value in
            ControlWidgetButton(action: WellSpentWatchControlAction(request: value.request)) {
                Label(value.title, systemImage: value.symbol)
                    .controlWidgetStatus(Text(value.pendingSync ? "Pending sync" : "WellSpent"))
            }
        }
        .displayName("WellSpent Timer")
        .description("Start a favorite or recent project, pause, or resume. Opens WellSpent to save your action.")
    }
}
