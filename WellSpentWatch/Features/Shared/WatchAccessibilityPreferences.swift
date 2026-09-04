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
