import SwiftUI

struct WatchAccessibilityPreferences: Equatable, Sendable {
    var reduceMotion = false
    var increaseContrast = false
    var differentiateWithoutColor = false

    func including(_ overrides: Self) -> Self {
        Self(
            reduceMotion: reduceMotion || overrides.reduceMotion,
            increaseContrast: increaseContrast || overrides.increaseContrast,
            differentiateWithoutColor: differentiateWithoutColor || overrides.differentiateWithoutColor)
    }
}

@propertyWrapper
struct WatchAccessibilitySettings: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    #if DEBUG
        @Environment(\.watchAccessibilityFixtureOverrides) private var fixtureOverrides
    #endif

    init() {}
    var wrappedValue: WatchAccessibilityPreferences {
        let system = WatchAccessibilityPreferences(
            reduceMotion: reduceMotion,
            increaseContrast: contrast == .increased, differentiateWithoutColor: differentiateWithoutColor)
        #if DEBUG
            return system.including(fixtureOverrides)
        #else
            return system
        #endif
    }
}

enum WatchDesign {
    static let canvas = Color.black
    static let panel = Color(red: 17 / 255, green: 45 / 255, blue: 60 / 255)
    static let foreground = Color(red: 250 / 255, green: 246 / 255, blue: 236 / 255)
    static let amber = Color(red: 255 / 255, green: 193 / 255, blue: 106 / 255)
    static let teal = Color(red: 142 / 255, green: 217 / 255, blue: 209 / 255)
    static let muted = Color(red: 176 / 255, green: 190 / 255, blue: 197 / 255)
    static let end = Color(red: 158 / 255, green: 38 / 255, blue: 55 / 255)
}

private struct WatchPanel: ViewModifier {
    @WatchAccessibilitySettings private var accessibilitySettings
    let fill: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        .white.opacity(accessibilitySettings.increaseContrast ? 0.8 : 0.08),
                        lineWidth: accessibilitySettings.increaseContrast ? 1.5 : 0.5
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func watchPanel(fill: Color = WatchDesign.panel, cornerRadius: CGFloat = 16) -> some View {
        modifier(WatchPanel(fill: fill, cornerRadius: cornerRadius))
    }
}

struct WatchActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var foreground = WatchDesign.amber
    var fill = WatchDesign.panel

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .watchPanel(fill: fill)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.55)
    }
}

#if DEBUG
    private struct WatchAccessibilityFixtureOverridesKey: EnvironmentKey {
        static let defaultValue = WatchAccessibilityPreferences()
    }
    extension EnvironmentValues {
        var watchAccessibilityFixtureOverrides: WatchAccessibilityPreferences {
            get { self[WatchAccessibilityFixtureOverridesKey.self] }
            set { self[WatchAccessibilityFixtureOverridesKey.self] = newValue }
        }
    }
#endif
