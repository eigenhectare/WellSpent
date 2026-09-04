#if DEBUG
    import SwiftUI

    // Keep fixture type names distinct from this file's name so the Release
    // byte audit checks code markers, not a harmless compiler source-file path.

    @MainActor
    final class WatchAccessibilityFixtureSettings: ObservableObject {
        static let shared = WatchAccessibilityFixtureSettings()
        @Published var redacted = ProcessInfo.processInfo.arguments.contains("-ui-test-privacy-redacted")
        let showsToggle = ProcessInfo.processInfo.arguments.contains("-ui-test-privacy-toggle")
        let reducedLuminance = ProcessInfo.processInfo.arguments.contains("-ui-test-reduced-luminance")
        let largestText = ProcessInfo.processInfo.arguments.contains("-ui-test-largest-text")
        let boldText = ProcessInfo.processInfo.arguments.contains("-ui-test-bold-text")
        let increasedContrast = ProcessInfo.processInfo.arguments.contains("-ui-test-increased-contrast")
        let reducedMotion = ProcessInfo.processInfo.arguments.contains("-ui-test-reduced-motion")
        let differentiateWithoutColor = ProcessInfo.processInfo.arguments.contains("-ui-test-without-color")
    }

    struct WatchAccessibilityFixtureEnvironment: ViewModifier {
        @ObservedObject private var settings = WatchAccessibilityFixtureSettings.shared
        @Environment(\.isLuminanceReduced) private var reducedLuminance
        @Environment(\.redactionReasons) private var redactionReasons
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.legibilityWeight) private var legibilityWeight

        func body(content: Content) -> some View {
            content
                .environment(\.isLuminanceReduced, reducedLuminance || settings.reducedLuminance)
                .environment(\.redactionReasons, redactionReasons.union(settings.redacted ? .privacy : []))
                .environment(\.dynamicTypeSize, settings.largestText ? .accessibility5 : dynamicTypeSize)
                .environment(\.legibilityWeight, settings.boldText ? .bold : legibilityWeight)
                // These system values are read-only in SwiftUI. Inject app
                // adaptation inputs without pretending to change OS settings.
                .environment(
                    \.watchAccessibilityFixtureOverrides,
                    WatchAccessibilityPreferences(
                        reduceMotion: settings.reducedMotion,
                        increaseContrast: settings.increasedContrast,
                        differentiateWithoutColor: settings.differentiateWithoutColor))
        }
    }

    struct WatchPrivacyFixtureToggle: View {
        @ObservedObject private var settings = WatchAccessibilityFixtureSettings.shared
        var body: some View {
            if settings.showsToggle {
                Button {
                    settings.redacted.toggle()
                } label: {
                    Image(systemName: settings.redacted ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44)
                        .background(.black, in: Circle())
                }
                .buttonStyle(.plain)
                .unredacted()
                .accessibilityLabel("Toggle test privacy")
                .accessibilityValue(settings.redacted ? "Private" : "Visible")
                .accessibilityIdentifier("watch.test.privacy-toggle")
            }
        }
    }
#endif
