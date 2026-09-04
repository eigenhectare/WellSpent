import Testing

@testable import WellSpentWatch

struct WatchAccessibilityPreferencesTests {
    @Test
    func fixtureOverridesCannotDisableSystemPreferences() {
        let system = WatchAccessibilityPreferences(
            reduceMotion: true, increaseContrast: true, differentiateWithoutColor: true)
        #expect(system.including(WatchAccessibilityPreferences()) == system)
    }

    @Test
    func preferencesMergeIndependentlyWithoutEnablingUnrequestedAdaptations() {
        let system = WatchAccessibilityPreferences(increaseContrast: true)
        let overrides = WatchAccessibilityPreferences(reduceMotion: true)
        #expect(
            system.including(overrides)
                == WatchAccessibilityPreferences(reduceMotion: true, increaseContrast: true))
        #expect(
            WatchAccessibilityPreferences().including(WatchAccessibilityPreferences())
                == WatchAccessibilityPreferences())
    }
}
