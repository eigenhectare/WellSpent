import SwiftUI

/// All app-owned screens use the same system privacy signals, including sheets.
@propertyWrapper
struct WatchPrivacyRedaction: DynamicProperty {
    @Environment(\.isLuminanceReduced) private var reducedLuminance
    @Environment(\.redactionReasons) private var redactionReasons

    init() {}
    var wrappedValue: Bool { reducedLuminance || redactionReasons.contains(.privacy) }
}

extension View {
    @ViewBuilder
    func watchAccessibilityPreviewEnvironment() -> some View {
        #if DEBUG
            modifier(WatchAccessibilityFixtureEnvironment())
        #else
            self
        #endif
    }

    func watchPrivateScreen(
        title: LocalizedStringKey = "WellSpent", elapsedSeconds: TimeInterval? = nil
    ) -> some View {
        modifier(WatchPrivateScreenModifier(title: title, elapsedSeconds: elapsedSeconds))
    }

    @ViewBuilder
    func watchPrivacyFixtureToggle() -> some View {
        #if DEBUG
            overlay(alignment: .bottomTrailing) { WatchPrivacyFixtureToggle() }
        #else
            self
        #endif
    }
}

private struct WatchPrivateScreenModifier: ViewModifier {
    let title: LocalizedStringKey
    let elapsedSeconds: TimeInterval?
    @WatchPrivacyRedaction private var hidesPrivateContent

    func body(content: Content) -> some View {
        ZStack {
            // Keep the original view alive: wrist-down must not discard a note,
            // tag selection, navigation position, or an in-flight save.
            content
                .opacity(hidesPrivateContent ? 0 : 1)
                .accessibilityHidden(hidesPrivateContent)
                .allowsHitTesting(!hidesPrivateContent)
            if hidesPrivateContent {
                ScrollView {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill").accessibilityHidden(true)
                        Text(title).font(.headline)
                        if let elapsedSeconds {
                            Text(WatchDurationText.digital(elapsedSeconds))
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .accessibilityLabel(WatchDurationText.spoken(elapsedSeconds))
                        }
                        Text("Private details hidden")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                // This overlay contains no user data. Explicitly opt it out
                // of inherited redaction so native List rendering cannot
                // blank the safe explanation along with the private rows.
                .unredacted()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("watch.privacy.screen")
            }
        }
        .watchPrivacyFixtureToggle()
    }
}
