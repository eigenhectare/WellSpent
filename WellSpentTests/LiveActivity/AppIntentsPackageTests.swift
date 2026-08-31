import AppIntents
import WellSpentShared
import XCTest

@testable import WellSpent

final class AppIntentsPackageTests: XCTestCase {
    func testAppIncludesSharedLiveActivityIntentPackage() {
        XCTAssertTrue(
            WellSpentAppIntentsPackage.includedPackages.contains {
                ObjectIdentifier($0) == ObjectIdentifier(WellSpentSharedAppIntentsPackage.self)
            }
        )
    }
}
