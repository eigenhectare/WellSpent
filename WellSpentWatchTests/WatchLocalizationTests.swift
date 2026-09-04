import Foundation
import Testing

@testable import WellSpentWatch

struct WatchLocalizationTests {
    @Test
    func pendingSyncCatalogUsesEnglishSingularAndPlural() {
        let english = Locale(identifier: "en_US")
        for (count, noun) in [(0, "items"), (1, "item"), (2, "items"), (123, "items")] {
            let copy = String(
                localized: "Pending sync, \(count) items. Cached projects remain available.", locale: english)
            #expect(copy == "Pending sync, \(count) \(noun). Cached projects remain available.")
        }
    }

    @Test
    func projectDataIsNeverUsedAsALocalizationKey() {
        for name in ["Running", "Paused", "100% %@ 🧾", "工程 / Client", "مرحبا", "e\u{301}"] {
            #expect(WatchProjectIdentity.displayName(name, redacted: false) == name)
            #expect(WatchProjectIdentity.displayName(name, redacted: true) == WatchProjectIdentity.privateName)
        }
    }

    @Test
    func watchBundleIncludesEnglishCatalog() throws {
        #expect(Bundle.main.localizations.contains("en"))
        let url = try #require(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"))
        let values = try #require(NSDictionary(contentsOf: url) as? [String: String])
        for key in ["Running", "Couldn’t pause", "Run saved", "Pause Timer", "Time goal reached"] {
            #expect(values[key] == key)
        }
        #expect(values["Toggle test privacy"] == nil)
    }
}
