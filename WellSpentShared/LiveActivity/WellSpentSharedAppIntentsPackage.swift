import AppIntents

/// Registers the App Intents that live in the statically linked shared
/// framework so consuming app and extension bundles retain their runtime types.
public struct WellSpentSharedAppIntentsPackage: AppIntentsPackage {}
