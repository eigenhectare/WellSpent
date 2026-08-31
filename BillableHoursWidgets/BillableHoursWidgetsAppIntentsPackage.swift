import AppIntents
import BillableHoursShared

/// Keeps the widget extension's App Intent registration aligned with the app.
struct BillableHoursWidgetsAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [BillableHoursSharedAppIntentsPackage.self]
    }
}
