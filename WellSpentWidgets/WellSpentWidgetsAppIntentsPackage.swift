import AppIntents
import WellSpentShared

/// Keeps the widget extension's App Intent registration aligned with the app.
struct WellSpentWidgetsAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [WellSpentSharedAppIntentsPackage.self]
    }
}
