import AppIntents
import BillableHoursShared

/// Makes shared Live Activity intents available when iOS executes them in the
/// already-running app process.
struct BillableHoursAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [BillableHoursSharedAppIntentsPackage.self]
    }
}
