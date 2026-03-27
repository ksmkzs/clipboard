import XCTest
@testable import ClipboardHistory

final class AppDelegateTargetSelectionTests: XCTestCase {
    func testPrefersFrontmostAppOverStalePlacementAndPrevious() {
        let decision = AppDelegate.TargetAppDecision(
            frontmostPID: 200,
            placementPID: 100,
            previousPID: 100,
            currentPID: 999,
            frontmostTerminated: false,
            placementTerminated: false,
            previousTerminated: false
        )

        XCTAssertEqual(AppDelegate.preferredTargetPID(for: decision), 200)
    }

    func testFallsBackToPlacementWhenFrontmostIsCurrentApp() {
        let decision = AppDelegate.TargetAppDecision(
            frontmostPID: 999,
            placementPID: 100,
            previousPID: 50,
            currentPID: 999,
            frontmostTerminated: false,
            placementTerminated: false,
            previousTerminated: false
        )

        XCTAssertEqual(AppDelegate.preferredTargetPID(for: decision), 100)
    }

    func testFallsBackToPreviousWhenFrontmostAndPlacementUnavailable() {
        let decision = AppDelegate.TargetAppDecision(
            frontmostPID: nil,
            placementPID: 100,
            previousPID: 50,
            currentPID: 999,
            frontmostTerminated: true,
            placementTerminated: true,
            previousTerminated: false
        )

        XCTAssertEqual(AppDelegate.preferredTargetPID(for: decision), 50)
    }

    func testReturnsNilWhenOnlyCurrentAppExists() {
        let decision = AppDelegate.TargetAppDecision(
            frontmostPID: 999,
            placementPID: 999,
            previousPID: 999,
            currentPID: 999,
            frontmostTerminated: false,
            placementTerminated: false,
            previousTerminated: false
        )

        XCTAssertNil(AppDelegate.preferredTargetPID(for: decision))
    }
}
