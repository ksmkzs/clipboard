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

    func testHelpPanelPlacementUsesRightSideWhenSpaceExists() {
        let placement = AppDelegate.helpPanelPlacement(
            for: NSRect(x: 100, y: 120, width: 320, height: 420),
            within: NSRect(x: 20, y: 20, width: 1200, height: 800),
            helpSize: NSSize(width: 400, height: 420),
            gap: 14
        )

        XCTAssertEqual(placement.side, .right)
        XCTAssertFalse(placement.frame.intersects(NSRect(x: 100, y: 120, width: 320, height: 420)))
    }

    func testHelpPanelPlacementUsesLeftSideWhenRightSideWouldOverlapEdge() {
        let placement = AppDelegate.helpPanelPlacement(
            for: NSRect(x: 860, y: 120, width: 320, height: 420),
            within: NSRect(x: 20, y: 20, width: 1200, height: 800),
            helpSize: NSSize(width: 340, height: 420),
            gap: 14
        )

        XCTAssertEqual(placement.side, .left)
        XCTAssertFalse(placement.frame.intersects(NSRect(x: 860, y: 120, width: 320, height: 420)))
    }

    func testHelpPanelPlacementCentersWhenNeitherSideFits() {
        let placement = AppDelegate.helpPanelPlacement(
            for: NSRect(x: 160, y: 80, width: 320, height: 420),
            within: NSRect(x: 20, y: 20, width: 640, height: 560),
            helpSize: NSSize(width: 420, height: 420),
            gap: 14
        )

        XCTAssertEqual(placement.side, .centered)
        XCTAssertEqual(placement.frame.width, 420)
        XCTAssertEqual(placement.frame.height, 420)
    }

    func testAuxiliaryWindowPlacementStaysInsideVisibleFrameWhenRightSideWouldOverflow() {
        let frame = AppDelegate.auxiliaryWindowPlacement(
            anchorFrame: NSRect(x: 1040, y: 120, width: 320, height: 420),
            visibleFrame: NSRect(x: 20, y: 20, width: 1280, height: 820),
            windowSize: NSSize(width: 620, height: 560),
            gap: 16
        )

        XCTAssertGreaterThanOrEqual(frame.minX, 20)
        XCTAssertGreaterThanOrEqual(frame.minY, 20)
        XCTAssertLessThanOrEqual(frame.maxX, 1300)
        XCTAssertLessThanOrEqual(frame.maxY, 840)
    }

    func testExternalEditorCloseOutcomePersistsOnlyWhenCommitRequested() {
        XCTAssertEqual(
            AppDelegate.externalEditorCloseOutcome(commitRequested: true, isOrphaned: false),
            .persistAndSignal
        )
        XCTAssertEqual(
            AppDelegate.externalEditorCloseOutcome(commitRequested: false, isOrphaned: false),
            .signalOnly
        )
        XCTAssertEqual(
            AppDelegate.externalEditorCloseOutcome(commitRequested: false, isOrphaned: true),
            .discardOrphan
        )
    }

    func testParseCodexOpenRequestSupportsProjectRootMetadata() {
        let request = """
        12345678-1234-1234-1234-1234567890ab
        /tmp/codex-draft.md
        /Users/example/project
        """

        let parsed = AppDelegate.parseCodexOpenRequest(request)

        XCTAssertEqual(parsed?.sessionID, "12345678-1234-1234-1234-1234567890ab")
        XCTAssertEqual(parsed?.fileURL.path, "/tmp/codex-draft.md")
        XCTAssertEqual(parsed?.projectRootURL?.path, "/Users/example/project")
    }

    func testParseCodexOpenRequestSupportsSessionStateMetadata() {
        let request = """
        12345678-1234-1234-1234-1234567890ab
        /tmp/codex-draft.md
        /Users/example/project
        /Users/example/Library/Application Support/ClipboardHistory/Codex/State/12345678-1234-1234-1234-1234567890ab.alive
        """

        let parsed = AppDelegate.parseCodexOpenRequest(request)

        XCTAssertEqual(parsed?.sessionID, "12345678-1234-1234-1234-1234567890ab")
        XCTAssertEqual(parsed?.fileURL.path, "/tmp/codex-draft.md")
        XCTAssertEqual(parsed?.projectRootURL?.path, "/Users/example/project")
        XCTAssertEqual(parsed?.sessionStateURL?.lastPathComponent, "12345678-1234-1234-1234-1234567890ab.alive")
    }

    func testParseCodexOpenRequestSupportsLegacyTwoLineFormat() {
        let request = """
        12345678-1234-1234-1234-1234567890ab
        /tmp/codex-draft.md
        """

        let parsed = AppDelegate.parseCodexOpenRequest(request)

        XCTAssertEqual(parsed?.sessionID, "12345678-1234-1234-1234-1234567890ab")
        XCTAssertEqual(parsed?.fileURL.path, "/tmp/codex-draft.md")
        XCTAssertNil(parsed?.projectRootURL)
    }
}
