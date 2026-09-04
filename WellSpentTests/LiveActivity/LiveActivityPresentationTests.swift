import SwiftUI
import WellSpentShared
import XCTest

@MainActor
final class LiveActivityPresentationTests: XCTestCase {
    func testRenderAllFamiliesWithRunningPausedEndedReviewAndPrivateState() throws {
        let now = Date.now
        let start = now.addingTimeInterval(-5025)
        let scenarios: [(String, WellSpentActivityAttributes.ContentState)] = [
            (
                "running",
                .init(
                    phase: .running, projectName: "Design review", showsProjectName: true,
                    countedSeconds: 1200, currentSegmentStartedAt: now.addingTimeInterval(-900), revision: 3)
            ),
            ("paused", .init(phase: .paused, countedSeconds: 5025, revision: 4, watchConfirmationPending: true)),
            ("ended", .init(phase: .stopped, endedAt: now, countedSeconds: 5025, revision: 5)),
            (
                "review",
                .init(
                    phase: .running, projectName: "Hidden client", showsProjectName: true,
                    countedSeconds: 5025, revision: 6, requiresReview: true)
            ),
            (
                "private",
                .init(
                    phase: .running, projectName: "Hidden client", showsProjectName: false,
                    countedSeconds: 5025, currentSegmentStartedAt: now, revision: 7)
            ),
        ]
        for family in WellSpentActivityPresentation.Family.allCases {
            for (name, state) in scenarios {
                let width: CGFloat
                switch family {
                case .lockScreen: width = 390
                case .expanded: width = 350
                case .compact: width = 76
                case .minimal: width = 32
                case .watchMirror: width = 184
                }
                let content = WellSpentActivityPresentation(
                    runID: UUID(), startedAt: start, state: state, family: family
                )
                .environment(\.colorScheme, .dark)
                .foregroundStyle(.white)
                .frame(width: width)
                .background(.black)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage, "Render \(family.rawValue)/\(name)")
                XCTAssertEqual(image.size.width, width)
                if family == .lockScreen || family == .expanded {
                    XCTAssertLessThanOrEqual(image.size.height, 160, "Live Activity system height: \(name)")
                }
                if family == .watchMirror {
                    XCTAssertLessThanOrEqual(image.size.height, 120, "Small mirrored card: \(name)")
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "activity-\(family.rawValue)-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testNamedCardRedactionAndAlwaysOnUseGenericLabel() throws {
        let state = WellSpentActivityAttributes.ContentState(
            phase: .paused, projectName: "Sensitive project", showsProjectName: true,
            countedSeconds: 1234, revision: 3)
        for dimmed in [false, true] {
            let content = WellSpentActivityPresentation(
                runID: UUID(), startedAt: .now, state: state, family: .lockScreen
            )
            .environment(\.isLuminanceReduced, dimmed)
            .environment(\.redactionReasons, dimmed ? [] : .privacy)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .frame(width: 390)
            .background(.black)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = dimmed ? "activity-always-on-private" : "activity-privacy-redacted"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
