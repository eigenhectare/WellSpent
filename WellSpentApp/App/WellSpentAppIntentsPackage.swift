import AppIntents
import WellSpentShared

/// Makes shared Live Activity intents available when iOS executes them in the
/// already-running app process.
struct WellSpentAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [WellSpentSharedAppIntentsPackage.self]
    }
}
