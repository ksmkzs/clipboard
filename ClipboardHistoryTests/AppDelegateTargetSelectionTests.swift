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

    func testResolvedSpecialCopySourceTextPrefersPanelText() {
        let resolved = AppDelegate.resolvedSpecialCopySourceText(
            panelText: "panel text",
            clipboardText: "clipboard text"
        )

        XCTAssertEqual(resolved, "panel text")
    }

    func testResolvedSpecialCopySourceTextFallsBackToClipboardText() {
        let resolved = AppDelegate.resolvedSpecialCopySourceText(
            panelText: nil,
            clipboardText: "clipboard text"
        )

        XCTAssertEqual(resolved, "clipboard text")
    }

    func testResolvedSpecialCopySourceTextRejectsBlankValues() {
        let resolved = AppDelegate.resolvedSpecialCopySourceText(
            panelText: "   \n",
            clipboardText: "\n"
        )

        XCTAssertNil(resolved)
    }

    func testStandaloneEditorModeAfterSavingFileTransitionsManualNoteToFileBacked() {
        XCTAssertEqual(
            AppDelegate.standaloneEditorModeAfterSavingFile(currentMode: nil, destinationKind: .markdown),
            .fileBacked(.markdown)
        )
        XCTAssertEqual(
            AppDelegate.standaloneEditorModeAfterSavingFile(
                currentMode: .fileBacked(.text),
                destinationKind: .markdown
            ),
            .fileBacked(.text)
        )
        XCTAssertEqual(
            AppDelegate.standaloneEditorModeAfterSavingFile(
                currentMode: .codex,
                destinationKind: .markdown
            ),
            .codex
        )
    }

    func testShouldConvertManualNoteToFileBackedEditorOnlyForManualNotes() {
        XCTAssertTrue(
            AppDelegate.shouldConvertManualNoteToFileBackedEditor(
                currentMode: nil,
                itemIDPresent: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldConvertManualNoteToFileBackedEditor(
                currentMode: .fileBacked(.markdown),
                itemIDPresent: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldConvertManualNoteToFileBackedEditor(
                currentMode: .codex,
                itemIDPresent: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldConvertManualNoteToFileBackedEditor(
                currentMode: nil,
                itemIDPresent: false
            )
        )
    }

    func testPanelToggleActionOnlyClosesWhenPanelIsFrontmost() {
        XCTAssertEqual(
            AppDelegate.panelToggleAction(isVisible: false, isFrontmost: false),
            .showOrRaise
        )
        XCTAssertEqual(
            AppDelegate.panelToggleAction(isVisible: true, isFrontmost: false),
            .showOrRaise
        )
        XCTAssertEqual(
            AppDelegate.panelToggleAction(isVisible: true, isFrontmost: true),
            .close
        )
    }

    func testStandaloneDiscardActionDeletesPlaceholderDrafts() {
        XCTAssertEqual(
            AppDelegate.standaloneDiscardAction(
                isPlaceholderManualNote: true,
                hasSavedContent: false
            ),
            .deletePlaceholder
        )
        XCTAssertEqual(
            AppDelegate.standaloneDiscardAction(
                isPlaceholderManualNote: true,
                hasSavedContent: true
            ),
            .restoreOriginal
        )
        XCTAssertEqual(
            AppDelegate.standaloneDiscardAction(
                isPlaceholderManualNote: false,
                hasSavedContent: false
            ),
            .restoreOriginal
        )
    }

    func testStandaloneEditorHasUnsavedChangesRequiresTextDifferenceOnly() {
        XCTAssertFalse(
            AppDelegate.standaloneEditorHasUnsavedChanges(
                draftText: "same",
                lastPersistedText: "same"
            )
        )
        XCTAssertTrue(
            AppDelegate.standaloneEditorHasUnsavedChanges(
                draftText: "new",
                lastPersistedText: "old"
            )
        )
    }

    func testLocalHistoryDiffEngineTreatsTerminalNewlineAsEquivalentForPreviewDiff() {
        let result = LocalHistoryDiffEngine.compare(
            snapshotText: "alpha\nbeta\n",
            currentText: "alpha\nbeta"
        )

        XCTAssertEqual(result.summary, .zero)
        XCTAssertFalse(result.summary.hasChanges)
        XCTAssertFalse(result.isTruncated)
        XCTAssertFalse(result.isUnavailable)
    }

    func testLocalHistoryDiffEngineTreatsEmptySnapshotAsPureAdditions() {
        let result = LocalHistoryDiffEngine.compare(
            snapshotText: "",
            currentText: "alpha\nbeta"
        )

        XCTAssertEqual(result.summary, .init(additions: 2, removals: 0))
        XCTAssertEqual(result.lines.map(\.kind), [.added, .added])
    }

    func testLocalHistoryDiffEngineTreatsReturnToEmptyAsPureRemovals() {
        let result = LocalHistoryDiffEngine.compare(
            snapshotText: "alpha\nbeta",
            currentText: ""
        )

        XCTAssertEqual(result.summary, .init(additions: 0, removals: 2))
        XCTAssertEqual(result.lines.map(\.kind), [.removed, .removed])
    }

    func testLocalHistoryDiffEngineRepresentsReplacementAsRemovalThenAddition() {
        let result = LocalHistoryDiffEngine.compare(
            snapshotText: "alpha\nbeta\ngamma",
            currentText: "alpha\nBETA\ngamma"
        )

        XCTAssertEqual(result.summary, .init(additions: 1, removals: 1))
        XCTAssertEqual(result.lines.map(\.kind), [.unchanged, .removed, .added, .unchanged])
        XCTAssertEqual(result.lines[1].oldLineNumber, 2)
        XCTAssertEqual(result.lines[1].newLineNumber, nil)
        XCTAssertEqual(result.lines[2].oldLineNumber, nil)
        XCTAssertEqual(result.lines[2].newLineNumber, 2)
    }

    func testLocalHistoryDiffEngineCountsInsertedLinesAgainstCurrentDraft() {
        let result = LocalHistoryDiffEngine.compare(
            snapshotText: "one\nthree",
            currentText: "one\ntwo\nthree\nfour"
        )

        XCTAssertEqual(result.summary, .init(additions: 2, removals: 0))
        XCTAssertEqual(result.lines.map(\.kind), [.unchanged, .added, .unchanged, .added])
    }

    func testLocalHistoryDiffEnginePreservesBlankLineRemovals() {
        let result = LocalHistoryDiffEngine.compare(
            snapshotText: "a\n\nb",
            currentText: "a\nb"
        )

        XCTAssertEqual(result.summary, .init(additions: 0, removals: 1))
        XCTAssertEqual(result.lines.map(\.kind), [.unchanged, .removed, .unchanged])
        XCTAssertEqual(result.lines[1].text, "")
    }

    func testLocalHistoryDiffEngineFallsBackToSummaryOnlyWhenDiffIsTooLarge() {
        let snapshotText = (0..<180).map { "line-\($0)" }.joined(separator: "\n")
        let currentText = snapshotText + "\nline-180"

        let result = LocalHistoryDiffEngine.compare(
            snapshotText: snapshotText,
            currentText: currentText,
            maximumComparableLines: 100,
            maximumCellCount: 5_000
        )

        XCTAssertTrue(result.isTruncated)
        XCTAssertFalse(result.isUnavailable)
        XCTAssertEqual(result.summary, .init(additions: 1, removals: 0))
        XCTAssertTrue(result.lines.isEmpty)
    }

    func testLocalHistoryDiffEngineScenarioMatrix() {
        struct Scenario {
            let name: String
            let snapshotText: String
            let currentText: String
            let expectedSummary: LocalHistoryDiffEngine.Summary
            let expectedKinds: [LocalHistoryDiffEngine.LineKind]
            let expectedOldLineNumbers: [Int?]
            let expectedNewLineNumbers: [Int?]
        }

        let scenarios: [Scenario] = [
            Scenario(
                name: "terminal-newline-equivalent",
                snapshotText: "alpha\nbeta\n",
                currentText: "alpha\nbeta",
                expectedSummary: .zero,
                expectedKinds: [],
                expectedOldLineNumbers: [],
                expectedNewLineNumbers: []
            ),
            Scenario(
                name: "empty-to-text",
                snapshotText: "",
                currentText: "alpha\nbeta",
                expectedSummary: .init(additions: 2, removals: 0),
                expectedKinds: [.added, .added],
                expectedOldLineNumbers: [nil, nil],
                expectedNewLineNumbers: [1, 2]
            ),
            Scenario(
                name: "text-to-empty",
                snapshotText: "alpha\nbeta",
                currentText: "",
                expectedSummary: .init(additions: 0, removals: 2),
                expectedKinds: [.removed, .removed],
                expectedOldLineNumbers: [1, 2],
                expectedNewLineNumbers: [nil, nil]
            ),
            Scenario(
                name: "replacement",
                snapshotText: "alpha\nbeta\ngamma",
                currentText: "alpha\nBETA\ngamma",
                expectedSummary: .init(additions: 1, removals: 1),
                expectedKinds: [.unchanged, .removed, .added, .unchanged],
                expectedOldLineNumbers: [1, 2, nil, 3],
                expectedNewLineNumbers: [1, nil, 2, 3]
            ),
            Scenario(
                name: "insertions",
                snapshotText: "one\nthree",
                currentText: "one\ntwo\nthree\nfour",
                expectedSummary: .init(additions: 2, removals: 0),
                expectedKinds: [.unchanged, .added, .unchanged, .added],
                expectedOldLineNumbers: [1, nil, 2, nil],
                expectedNewLineNumbers: [1, 2, 3, 4]
            ),
            Scenario(
                name: "blank-line-removal",
                snapshotText: "a\n\nb",
                currentText: "a\nb",
                expectedSummary: .init(additions: 0, removals: 1),
                expectedKinds: [.unchanged, .removed, .unchanged],
                expectedOldLineNumbers: [1, 2, 3],
                expectedNewLineNumbers: [1, nil, 2]
            ),
            Scenario(
                name: "crlf-normalization",
                snapshotText: "alpha\r\nbeta\r\n",
                currentText: "alpha\nbeta",
                expectedSummary: .zero,
                expectedKinds: [],
                expectedOldLineNumbers: [],
                expectedNewLineNumbers: []
            )
        ]

        for scenario in scenarios {
            let result = LocalHistoryDiffEngine.compare(
                snapshotText: scenario.snapshotText,
                currentText: scenario.currentText
            )

            XCTAssertEqual(result.summary, scenario.expectedSummary, scenario.name)
            XCTAssertEqual(result.lines.map(\.kind), scenario.expectedKinds, scenario.name)
            XCTAssertEqual(result.lines.map(\.oldLineNumber), scenario.expectedOldLineNumbers, scenario.name)
            XCTAssertEqual(result.lines.map(\.newLineNumber), scenario.expectedNewLineNumbers, scenario.name)
            XCTAssertFalse(result.isTruncated, scenario.name)
            XCTAssertFalse(result.isUnavailable, scenario.name)
            XCTAssertEqual(result.summary.hasChanges, scenario.expectedSummary.hasChanges, scenario.name)
        }
    }

    func testShouldRestoreAccessoryActivationPolicyOnlyWhenNoClipboardWindowsRemain() {
        XCTAssertTrue(
            AppDelegate.shouldRestoreAccessoryActivationPolicy(
                currentEditorHasFileURL: false,
                hasAnyClipboardWindowVisible: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldRestoreAccessoryActivationPolicy(
                currentEditorHasFileURL: true,
                hasAnyClipboardWindowVisible: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldRestoreAccessoryActivationPolicy(
                currentEditorHasFileURL: false,
                hasAnyClipboardWindowVisible: true
            )
        )
    }

    func testShouldStartLocalHistoryServicesOnlyOutsideAutomatedTests() {
        XCTAssertTrue(
            AppDelegate.shouldStartLocalHistoryServices(isRunningAutomatedTests: false)
        )
        XCTAssertFalse(
            AppDelegate.shouldStartLocalHistoryServices(isRunningAutomatedTests: true)
        )
    }

    func testUserDefaultsAppSettingsStorePersistsLocalHistoryPolicies() {
        let suiteName = "AppDelegateTargetSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(userDefaults: defaults)
        var settings = AppSettings.default
        settings.localFileHistoryDeletedSourceBehavior = .deleteAfterGracePeriod
        settings.localFileHistoryOrphanGracePeriodDays = 21
        settings.localFileHistoryConfirmDestructiveActions = false

        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.localFileHistoryDeletedSourceBehavior, .deleteAfterGracePeriod)
        XCTAssertEqual(loaded.localFileHistoryOrphanGracePeriodDays, 21)
        XCTAssertFalse(loaded.localFileHistoryConfirmDestructiveActions)
    }
}
