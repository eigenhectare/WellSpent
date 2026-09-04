import Testing

@testable import WellSpentWatch

struct WellSpentWatchFoundationTests {
    @Test
    func watchTargetLoads() {
        #expect(String(describing: WatchFoundationView.self) == "WatchFoundationView")
    }
}
