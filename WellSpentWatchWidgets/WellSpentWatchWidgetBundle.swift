import SwiftUI
import WidgetKit

@main
struct WellSpentWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WellSpentWatchStatusWidget()
        WellSpentWatchTimerControl()
    }
}
