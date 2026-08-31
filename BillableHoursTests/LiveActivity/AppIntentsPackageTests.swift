import AppIntents
import BillableHoursShared
import XCTest

@testable import BillableHours

final class AppIntentsPackageTests: XCTestCase {
    func testAppIncludesSharedLiveActivityIntentPackage() {
        XCTAssertTrue(
            BillableHoursAppIntentsPackage.includedPackages.contains {
                ObjectIdentifier($0) == ObjectIdentifier(BillableHoursSharedAppIntentsPackage.self)
            }
        )
    }
}
