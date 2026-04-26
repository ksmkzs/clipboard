import XCTest
@testable import ClipboardHistory

final class AppDelegateTargetSelectionTests: XCTestCase {
    func testPrefersFrontmostAppOverStalePlacementAndPrevious() {
        let decision = PlacementTargetDecision(
            frontmostPID: 200,
            placementPID: 100,
            previousPID: 100,
            currentPID: 999,
            frontmostTerminated: false,
            placementTerminated: false,
            previousTerminated: false
        )

        XCTAssertEqual(PasteTargetingService.preferredPlacementTargetPID(for: decision), 200)
    }

    func testFallsBackToPlacementWhenFrontmostIsCurrentApp() {
        let decision = PlacementTargetDecision(
            frontmostPID: 999,
            placementPID: 100,
            previousPID: 50,
            currentPID: 999,
            frontmostTerminated: false,
            placementTerminated: false,
            previousTerminated: false
        )

        XCTAssertEqual(PasteTargetingService.preferredPlacementTargetPID(for: decision), 100)
    }

    func testFallsBackToPreviousWhenFrontmostAndPlacementUnavailable() {
        let decision = PlacementTargetDecision(
            frontmostPID: nil,
            placementPID: 100,
            previousPID: 50,
            currentPID: 999,
            frontmostTerminated: true,
            placementTerminated: true,
            previousTerminated: false
        )

        XCTAssertEqual(PasteTargetingService.preferredPlacementTargetPID(for: decision), 50)
    }

    func testReturnsNilWhenOnlyCurrentAppExists() {
        let decision = PlacementTargetDecision(
            frontmostPID: 999,
            placementPID: 999,
            previousPID: 999,
            currentPID: 999,
            frontmostTerminated: false,
            placementTerminated: false,
            previousTerminated: false
        )

        XCTAssertNil(PasteTargetingService.preferredPlacementTargetPID(for: decision))
    }

    func testHelpPanelPlacementUsesRightSideWhenSpaceExists() {
        let placement = WindowShellPolicy.helpPanelPlacement(
            for: NSRect(x: 100, y: 120, width: 320, height: 420),
            within: NSRect(x: 20, y: 20, width: 1200, height: 800),
            helpSize: NSSize(width: 400, height: 420),
            gap: 14
        )

        XCTAssertEqual(placement.side, .right)
        XCTAssertFalse(placement.frame.intersects(NSRect(x: 100, y: 120, width: 320, height: 420)))
    }

    func testHelpPanelPlacementUsesLeftSideWhenRightSideWouldOverlapEdge() {
        let placement = WindowShellPolicy.helpPanelPlacement(
            for: NSRect(x: 860, y: 120, width: 320, height: 420),
            within: NSRect(x: 20, y: 20, width: 1200, height: 800),
            helpSize: NSSize(width: 340, height: 420),
            gap: 14
        )

        XCTAssertEqual(placement.side, .left)
        XCTAssertFalse(placement.frame.intersects(NSRect(x: 860, y: 120, width: 320, height: 420)))
    }

    func testHelpPanelPlacementCentersWhenNeitherSideFits() {
        let placement = WindowShellPolicy.helpPanelPlacement(
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
        let frame = WindowShellPolicy.auxiliaryWindowPlacement(
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

    func testExternalSelectionCopyPolicyRequiresPasteboardChange() {
        let resolved = GlobalTransformCopyPolicy.resolvedCopiedText(
            ExternalSelectionCopySnapshot(
                previousChangeCount: 10,
                currentChangeCount: 10,
                copiedText: "selected text"
            )
        )

        XCTAssertNil(resolved)
    }

    func testExternalSelectionCopyPolicyUsesCopiedTextAfterPasteboardChange() {
        let resolved = GlobalTransformCopyPolicy.resolvedCopiedText(
            ExternalSelectionCopySnapshot(
                previousChangeCount: 10,
                currentChangeCount: 11,
                copiedText: "line one\nline two"
            )
        )

        XCTAssertEqual(resolved, "line one\nline two")
    }

    func testExternalSelectionCopyPolicyRejectsBlankCopiedText() {
        let resolved = GlobalTransformCopyPolicy.resolvedCopiedText(
            ExternalSelectionCopySnapshot(
                previousChangeCount: 10,
                currentChangeCount: 11,
                copiedText: " \n "
            )
        )

        XCTAssertNil(resolved)
    }

    func testResolvedStandaloneMarkdownPreviewVisibilityDefaultsOff() {
        XCTAssertFalse(
            AppDelegate.resolvedStandaloneMarkdownPreviewVisibility(
                initialPreviewVisible: nil,
                supportsMarkdownPreview: true
            )
        )
        XCTAssertFalse(
            AppDelegate.resolvedStandaloneMarkdownPreviewVisibility(
                initialPreviewVisible: nil,
                supportsMarkdownPreview: false
            )
        )
    }

    func testResolvedStandaloneMarkdownPreviewVisibilityPreservesExplicitPreference() {
        XCTAssertTrue(
            AppDelegate.resolvedStandaloneMarkdownPreviewVisibility(
                initialPreviewVisible: true,
                supportsMarkdownPreview: true
            )
        )
        XCTAssertFalse(
            AppDelegate.resolvedStandaloneMarkdownPreviewVisibility(
                initialPreviewVisible: false,
                supportsMarkdownPreview: true
            )
        )
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
            WindowShellPolicy.panelToggleAction(isVisible: false, isFrontmost: false),
            .showOrRaise
        )
        XCTAssertEqual(
            WindowShellPolicy.panelToggleAction(isVisible: true, isFrontmost: false),
            .showOrRaise
        )
        XCTAssertEqual(
            WindowShellPolicy.panelToggleAction(isVisible: true, isFrontmost: true),
            .close
        )
    }

    func testPanelHotKeyRoutingTogglesPanelWhenSettingsHidden() {
        XCTAssertEqual(
            WindowShellPolicy.panelHotKeyRouting(
                settingsVisible: false,
                settingsShortcutCaptureActive: false
            ),
            .togglePanel
        )
    }

    func testPanelHotKeyRoutingRaisesSettingsWhenSettingsVisible() {
        XCTAssertEqual(
            WindowShellPolicy.panelHotKeyRouting(
                settingsVisible: true,
                settingsShortcutCaptureActive: false
            ),
            .bringSettingsToFront
        )
    }

    func testPanelHotKeyRoutingSuspendsRegistrationWhileCapturingSettingsShortcut() {
        XCTAssertEqual(
            WindowShellPolicy.panelHotKeyRouting(
                settingsVisible: true,
                settingsShortcutCaptureActive: true
            ),
            .suspendRegistration
        )
    }

    func testPreferredPasteTargetPIDPrefersSnapshotOverPreviousAndPlacement() {
        let decision = PasteTargetDecision(
            snapshotPID: 300,
            previousPID: 200,
            placementPID: 100,
            currentPID: 999,
            snapshotTerminated: false,
            previousTerminated: false,
            placementTerminated: false
        )

        XCTAssertEqual(PasteTargetingService.preferredTargetPID(for: decision), 300)
    }

    func testPreferredPasteTargetPIDFallsBackToPreviousWhenSnapshotIsUnavailable() {
        let decision = PasteTargetDecision(
            snapshotPID: 300,
            previousPID: 200,
            placementPID: 100,
            currentPID: 999,
            snapshotTerminated: true,
            previousTerminated: false,
            placementTerminated: false
        )

        XCTAssertEqual(PasteTargetingService.preferredTargetPID(for: decision), 200)
    }

    func testPreferredPasteTargetPIDFallsBackToPlacementWhenSnapshotAndPreviousAreUnavailable() {
        let decision = PasteTargetDecision(
            snapshotPID: 300,
            previousPID: 200,
            placementPID: 100,
            currentPID: 999,
            snapshotTerminated: true,
            previousTerminated: true,
            placementTerminated: false
        )

        XCTAssertEqual(PasteTargetingService.preferredTargetPID(for: decision), 100)
    }

    func testGlobalTransformRoutingUsesExternalSelectionWhenEditorIsOnlyVisibleInBackground() {
        let snapshot = GlobalTransformRoutingSnapshot(
            appIsActive: true,
            frontmostWindowKind: .settings,
            activeEditorSessionID: EditorSessionID(rawValue: "editor-session"),
            frontmostExternalPID: 777
        )

        XCTAssertEqual(
            GlobalTransformRoutingPolicy.resolve(snapshot),
            .externalSelection(777)
        )
    }

    func testGlobalTransformRoutingTargetsFrontmostNoteEditorSession() {
        let sessionID = EditorSessionID(rawValue: "note-editor-session")
        let snapshot = GlobalTransformRoutingSnapshot(
            appIsActive: true,
            frontmostWindowKind: .noteEditor,
            activeEditorSessionID: sessionID,
            frontmostExternalPID: 777
        )

        XCTAssertEqual(
            GlobalTransformRoutingPolicy.resolve(snapshot),
            .editor(sessionID)
        )
    }

    func testGlobalTransformRoutingTargetsFrontmostStandaloneSession() {
        let sessionID = EditorSessionID(rawValue: "standalone-session")
        let snapshot = GlobalTransformRoutingSnapshot(
            appIsActive: true,
            frontmostWindowKind: .standaloneNote,
            activeEditorSessionID: sessionID,
            frontmostExternalPID: 777
        )

        XCTAssertEqual(
            GlobalTransformRoutingPolicy.resolve(snapshot),
            .editor(sessionID)
        )
    }

    func testGlobalTransformRoutingTargetsPanelOnlyWhenPanelIsFrontmost() {
        let snapshot = GlobalTransformRoutingSnapshot(
            appIsActive: true,
            frontmostWindowKind: .panel,
            activeEditorSessionID: EditorSessionID(rawValue: "editor-session"),
            frontmostExternalPID: 777
        )

        XCTAssertEqual(
            GlobalTransformRoutingPolicy.resolve(snapshot),
            .panel
        )
    }

    func testEditorCommandDispatcherDeliversCommandOnlyToRequestedSession() {
        let dispatcher = EditorCommandDispatcher()
        let noteSession = EditorSessionID(rawValue: "note")
        let standaloneSession = EditorSessionID(rawValue: "standalone")
        var received: [(String, EditorCommand, String?)] = []

        _ = dispatcher.register(sessionID: noteSession) { command, payload in
            received.append(("note", command, payload))
        }
        _ = dispatcher.register(sessionID: standaloneSession) { command, payload in
            received.append(("standalone", command, payload))
        }

        XCTAssertTrue(dispatcher.dispatch(.joinLines, to: noteSession, payloadText: "payload"))
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, "note")
        XCTAssertEqual(received.first?.1, .joinLines)
        XCTAssertEqual(received.first?.2, "payload")
    }

    func testEditorCommandDispatcherUnregisterRequiresMatchingToken() {
        let dispatcher = EditorCommandDispatcher()
        let session = EditorSessionID(rawValue: "note")
        var received: [String] = []

        let originalToken = dispatcher.register(sessionID: session) { _, _ in
            received.append("original")
        }
        let replacementToken = dispatcher.register(sessionID: session) { _, _ in
            received.append("replacement")
        }

        dispatcher.unregister(sessionID: session, token: originalToken)
        XCTAssertTrue(dispatcher.dispatch(.normalizeForCommand, to: session))
        XCTAssertEqual(received, ["replacement"])

        dispatcher.unregister(sessionID: session, token: replacementToken)
        XCTAssertFalse(dispatcher.dispatch(.normalizeForCommand, to: session))
    }

    func testValidationEditorSurfacePolicyPrefersKeyWindowOwner() {
        let snapshot = ValidationEditorSurfaceSnapshot(
            keyOrMainWindowKind: .standaloneNote,
            noteEditorVisible: true,
            standaloneNoteVisible: true
        )

        XCTAssertEqual(
            ValidationEditorSurfacePolicy.resolve(snapshot),
            .standaloneNote
        )
    }

    func testValidationEditorSurfacePolicyFallsBackToVisibleNoteEditorBeforeStandalone() {
        let snapshot = ValidationEditorSurfaceSnapshot(
            keyOrMainWindowKind: .none,
            noteEditorVisible: true,
            standaloneNoteVisible: true
        )

        XCTAssertEqual(
            ValidationEditorSurfacePolicy.resolve(snapshot),
            .noteEditor
        )
    }

    func testValidationCoordinatorRoutesSaveCommandToResolvedEditorSurface() {
        var log: [String] = []
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: { log.append("open-panel") },
                togglePanelFromStatusItem: { log.append("toggle-panel") },
                captureSnapshot: { _ in log.append("snapshot") },
                captureWindowImage: { _, _ in log.append("image") },
                openFile: { _ in log.append("open-file") },
                openNewNote: { log.append("open-note") },
                openSettings: { log.append("open-settings") },
                openHelp: { log.append("open-help") },
                runGlobalCopyJoined: { log.append("copy-joined") },
                runGlobalCopyJoinedWithSpaces: { log.append("copy-joined-spaces") },
                runGlobalCopyNormalized: { log.append("copy-normalized") },
                inspectCodexIntegration: { log.append("inspect") },
                resetValidationState: { log.append("reset") },
                syncClipboardCapture: { log.append("sync") },
                seedHistoryText: { _ in log.append("seed") },
                reassertForegroundIfNeeded: { log.append("reassert") }
            ),
            panelCallbacks: .init(
                postPanelAction: { action, text in
                    log.append("panel:\(action):\(text ?? "")")
                },
                readTextFile: { _ in "" }
            ),
            editorCallbacks: .init(
                currentSurface: { .standaloneNote },
                readTextFile: { _ in "" },
                postEditorCommand: { _, _ in log.append("command") },
                saveNoteEditor: { log.append("save-note"); return true },
                saveStandaloneNote: { log.append("save-standalone"); return true },
                saveNoteEditorAs: { log.append("save-note-as"); return true },
                saveStandaloneNoteAs: { log.append("save-standalone-as"); return true },
                saveCurrentEditorToFile: { _ in log.append("save-file"); return true },
                closeNoteEditor: { log.append("close-note") },
                closeStandaloneNote: { log.append("close-standalone") },
                respondToAttachedSheet: { _ in log.append("sheet") }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { _ in log.append("preview-width") },
                setPreviewScroll: { _ in log.append("preview-scroll") },
                syncPreviewScroll: { log.append("preview-sync") },
                selectPreviewText: { _, _ in log.append("preview-select") },
                copyPreviewSelection: { log.append("preview-copy") },
                measurePreviewHorizontalOverflow: { log.append("preview-measure") },
                clickPreviewFirstLink: { log.append("preview-click") },
                respondToPreviewLinkPrompt: { _ in log.append("preview-prompt") }
            ),
            settingsCallbacks: .init(
                increaseZoom: { log.append("zoom-increase") },
                decreaseZoom: { log.append("zoom-decrease") },
                resetZoom: { log.append("zoom-reset") },
                setSettingsLanguage: { _ in log.append("language") },
                setThemePreset: { _ in log.append("theme") },
                setPanelShortcut: { _ in log.append("panel-shortcut") },
                setToggleMarkdownPreviewShortcut: { _ in log.append("preview-shortcut") },
                setGlobalCopyJoinedEnabled: { _ in log.append("joined-toggle") },
                setGlobalCopyJoinedWithSpacesEnabled: { _ in log.append("joined-spaces-toggle") },
                setGlobalCopyNormalizedEnabled: { _ in log.append("normalized-toggle") }
            )
        )

        XCTAssertTrue(
            coordinator.handleEditorAction(
                rawAction: ValidationCoordinator.EditorAction.saveCurrentEditor.rawValue,
                userInfo: [:]
            )
        )
        XCTAssertEqual(log, ["save-standalone"])
    }

    func testValidationCoordinatorRoutesTextMutationToEditorCommand() {
        var commands: [(EditorCommand, String?)] = []
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: {},
                togglePanelFromStatusItem: {},
                captureSnapshot: { _ in },
                captureWindowImage: { _, _ in },
                openFile: { _ in },
                openNewNote: {},
                openSettings: {},
                openHelp: {},
                runGlobalCopyJoined: {},
                runGlobalCopyJoinedWithSpaces: {},
                runGlobalCopyNormalized: {},
                inspectCodexIntegration: {},
                resetValidationState: {},
                syncClipboardCapture: {},
                seedHistoryText: { _ in },
                reassertForegroundIfNeeded: {}
            ),
            panelCallbacks: .init(
                postPanelAction: { _, _ in },
                readTextFile: { _ in "" }
            ),
            editorCallbacks: .init(
                currentSurface: { .noteEditor },
                readTextFile: { _ in "loaded-text" },
                postEditorCommand: { command, text in commands.append((command, text)) },
                saveNoteEditor: { true },
                saveStandaloneNote: { true },
                saveNoteEditorAs: { true },
                saveStandaloneNoteAs: { true },
                saveCurrentEditorToFile: { _ in true },
                closeNoteEditor: {},
                closeStandaloneNote: {},
                respondToAttachedSheet: { _ in }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { _ in },
                setPreviewScroll: { _ in },
                syncPreviewScroll: {},
                selectPreviewText: { _, _ in },
                copyPreviewSelection: {},
                measurePreviewHorizontalOverflow: {},
                clickPreviewFirstLink: {},
                respondToPreviewLinkPrompt: { _ in }
            ),
            settingsCallbacks: .init(
                increaseZoom: {},
                decreaseZoom: {},
                resetZoom: {},
                setSettingsLanguage: { _ in },
                setThemePreset: { _ in },
                setPanelShortcut: { _ in },
                setToggleMarkdownPreviewShortcut: { _ in },
                setGlobalCopyJoinedEnabled: { _ in },
                setGlobalCopyJoinedWithSpacesEnabled: { _ in },
                setGlobalCopyNormalizedEnabled: { _ in }
            )
        )

        XCTAssertTrue(
            coordinator.handleEditorAction(
                rawAction: ValidationCoordinator.EditorAction.setCurrentEditorText.rawValue,
                userInfo: ["path": "/tmp/test.txt"]
            )
        )
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.0, .setText)
        XCTAssertEqual(commands.first?.1, "loaded-text")
    }

    func testValidationCoordinatorRoutesPreviewActionsToCallbacks() {
        var log: [String] = []
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: {},
                togglePanelFromStatusItem: {},
                captureSnapshot: { _ in },
                captureWindowImage: { _, _ in },
                openFile: { _ in },
                openNewNote: {},
                openSettings: {},
                openHelp: {},
                runGlobalCopyJoined: {},
                runGlobalCopyJoinedWithSpaces: {},
                runGlobalCopyNormalized: {},
                inspectCodexIntegration: {},
                resetValidationState: {},
                syncClipboardCapture: {},
                seedHistoryText: { _ in },
                reassertForegroundIfNeeded: {}
            ),
            panelCallbacks: .init(
                postPanelAction: { _, _ in },
                readTextFile: { _ in "" }
            ),
            editorCallbacks: .init(
                currentSurface: { .none },
                readTextFile: { _ in "" },
                postEditorCommand: { _, _ in },
                saveNoteEditor: { true },
                saveStandaloneNote: { true },
                saveNoteEditorAs: { true },
                saveStandaloneNoteAs: { true },
                saveCurrentEditorToFile: { _ in true },
                closeNoteEditor: {},
                closeStandaloneNote: {},
                respondToAttachedSheet: { _ in }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { width in log.append("width:\(width)") },
                setPreviewScroll: { progress in log.append("scroll:\(progress)") },
                syncPreviewScroll: { log.append("sync") },
                selectPreviewText: { needle, preferCodeBlock in
                    log.append("select:\(needle):\(preferCodeBlock)")
                },
                copyPreviewSelection: { log.append("copy") },
                measurePreviewHorizontalOverflow: { log.append("measure") },
                clickPreviewFirstLink: { log.append("click") },
                respondToPreviewLinkPrompt: { rawChoice in log.append("prompt:\(rawChoice)") }
            ),
            settingsCallbacks: .init(
                increaseZoom: {},
                decreaseZoom: {},
                resetZoom: {},
                setSettingsLanguage: { _ in },
                setThemePreset: { _ in },
                setPanelShortcut: { _ in },
                setToggleMarkdownPreviewShortcut: { _ in },
                setGlobalCopyJoinedEnabled: { _ in },
                setGlobalCopyJoinedWithSpacesEnabled: { _ in },
                setGlobalCopyNormalizedEnabled: { _ in }
            )
        )

        XCTAssertTrue(
            coordinator.handlePreviewAction(
                rawAction: ValidationCoordinator.PreviewAction.selectCurrentPreviewCodeBlock.rawValue,
                userInfo: ["path": "needle"]
            )
        )
        XCTAssertTrue(
            coordinator.handlePreviewAction(
                rawAction: ValidationCoordinator.PreviewAction.setCurrentPreviewScroll.rawValue,
                userInfo: ["path": "0.5"]
            )
        )
        XCTAssertTrue(
            coordinator.handlePreviewAction(
                rawAction: ValidationCoordinator.PreviewAction.respondToPreviewLinkPrompt.rawValue,
                userInfo: ["path": "open"]
            )
        )

        XCTAssertEqual(log, ["select:needle:true", "scroll:0.5", "prompt:open"])
    }

    func testValidationCoordinatorRoutesSettingsActionsToCallbacks() {
        var log: [String] = []
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: {},
                togglePanelFromStatusItem: {},
                captureSnapshot: { _ in },
                captureWindowImage: { _, _ in },
                openFile: { _ in },
                openNewNote: {},
                openSettings: {},
                openHelp: {},
                runGlobalCopyJoined: {},
                runGlobalCopyJoinedWithSpaces: {},
                runGlobalCopyNormalized: {},
                inspectCodexIntegration: {},
                resetValidationState: {},
                syncClipboardCapture: {},
                seedHistoryText: { _ in },
                reassertForegroundIfNeeded: {}
            ),
            panelCallbacks: .init(
                postPanelAction: { _, _ in },
                readTextFile: { _ in "" }
            ),
            editorCallbacks: .init(
                currentSurface: { .none },
                readTextFile: { _ in "" },
                postEditorCommand: { _, _ in },
                saveNoteEditor: { true },
                saveStandaloneNote: { true },
                saveNoteEditorAs: { true },
                saveStandaloneNoteAs: { true },
                saveCurrentEditorToFile: { _ in true },
                closeNoteEditor: {},
                closeStandaloneNote: {},
                respondToAttachedSheet: { _ in }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { _ in },
                setPreviewScroll: { _ in },
                syncPreviewScroll: {},
                selectPreviewText: { _, _ in },
                copyPreviewSelection: {},
                measurePreviewHorizontalOverflow: {},
                clickPreviewFirstLink: {},
                respondToPreviewLinkPrompt: { _ in }
            ),
            settingsCallbacks: .init(
                increaseZoom: { log.append("zoom+") },
                decreaseZoom: { log.append("zoom-") },
                resetZoom: { log.append("zoom0") },
                setSettingsLanguage: { language in log.append("lang:\(language.rawValue)") },
                setThemePreset: { theme in log.append("theme:\(theme.rawValue)") },
                setPanelShortcut: { rawValue in log.append("panel:\(rawValue)") },
                setToggleMarkdownPreviewShortcut: { rawValue in log.append("preview:\(rawValue)") },
                setGlobalCopyJoinedEnabled: { enabled in log.append("joined:\(enabled)") },
                setGlobalCopyJoinedWithSpacesEnabled: { enabled in log.append("joined-spaces:\(enabled)") },
                setGlobalCopyNormalizedEnabled: { enabled in log.append("normalized:\(enabled)") }
            )
        )

        XCTAssertTrue(
            coordinator.handleSettingsAction(
                rawAction: ValidationCoordinator.SettingsAction.setSettingsLanguage.rawValue,
                userInfo: ["path": SettingsLanguage.english.rawValue]
            )
        )
        XCTAssertTrue(
            coordinator.handleSettingsAction(
                rawAction: ValidationCoordinator.SettingsAction.setThemePreset.rawValue,
                userInfo: ["path": InterfaceThemePreset.graphite.rawValue]
            )
        )
        XCTAssertTrue(
            coordinator.handleSettingsAction(
                rawAction: ValidationCoordinator.SettingsAction.setGlobalCopyJoinedEnabled.rawValue,
                userInfo: ["path": "true"]
            )
        )
        XCTAssertTrue(
            coordinator.handleSettingsAction(
                rawAction: ValidationCoordinator.SettingsAction.setGlobalCopyJoinedWithSpacesEnabled.rawValue,
                userInfo: ["path": "false"]
            )
        )

        XCTAssertEqual(log, ["lang:en", "theme:graphite", "joined:true", "joined-spaces:false"])
    }

    func testValidationCoordinatorRoutesPanelActionsToCallbacks() {
        var log: [String] = []
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: {},
                togglePanelFromStatusItem: {},
                captureSnapshot: { _ in },
                captureWindowImage: { _, _ in },
                openFile: { _ in },
                openNewNote: {},
                openSettings: {},
                openHelp: {},
                runGlobalCopyJoined: {},
                runGlobalCopyJoinedWithSpaces: {},
                runGlobalCopyNormalized: {},
                inspectCodexIntegration: {},
                resetValidationState: {},
                syncClipboardCapture: {},
                seedHistoryText: { _ in },
                reassertForegroundIfNeeded: {}
            ),
            panelCallbacks: .init(
                postPanelAction: { action, text in
                    log.append("\(action):\(text ?? "")")
                },
                readTextFile: { _ in "loaded-panel-text" }
            ),
            editorCallbacks: .init(
                currentSurface: { .none },
                readTextFile: { _ in "" },
                postEditorCommand: { _, _ in },
                saveNoteEditor: { true },
                saveStandaloneNote: { true },
                saveNoteEditorAs: { true },
                saveStandaloneNoteAs: { true },
                saveCurrentEditorToFile: { _ in true },
                closeNoteEditor: {},
                closeStandaloneNote: {},
                respondToAttachedSheet: { _ in }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { _ in },
                setPreviewScroll: { _ in },
                syncPreviewScroll: {},
                selectPreviewText: { _, _ in },
                copyPreviewSelection: {},
                measurePreviewHorizontalOverflow: {},
                clickPreviewFirstLink: {},
                respondToPreviewLinkPrompt: { _ in }
            ),
            settingsCallbacks: .init(
                increaseZoom: {},
                decreaseZoom: {},
                resetZoom: {},
                setSettingsLanguage: { _ in },
                setThemePreset: { _ in },
                setPanelShortcut: { _ in },
                setToggleMarkdownPreviewShortcut: { _ in },
                setGlobalCopyJoinedEnabled: { _ in },
                setGlobalCopyJoinedWithSpacesEnabled: { _ in },
                setGlobalCopyNormalizedEnabled: { _ in }
            )
        )

        XCTAssertTrue(
            coordinator.handlePanelAction(
                rawAction: ValidationCoordinator.PanelAction.setPanelEditorText.rawValue,
                userInfo: ["path": "/tmp/panel.txt"]
            )
        )
        XCTAssertTrue(
            coordinator.handlePanelAction(
                rawAction: ValidationCoordinator.PanelAction.commitPanelEditor.rawValue,
                userInfo: [:]
            )
        )

        XCTAssertEqual(log, ["setEditorText:loaded-panel-text", "commitEditor:"])
    }

    func testValidationCoordinatorRoutesApplicationOpenFileActionAndReassertsForeground() {
        var log: [String] = []
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: { log.append("open-panel") },
                togglePanelFromStatusItem: { log.append("toggle-panel") },
                captureSnapshot: { _ in log.append("snapshot") },
                captureWindowImage: { _, _ in log.append("image") },
                openFile: { url in log.append("open-file:\(url.path)") },
                openNewNote: { log.append("open-note") },
                openSettings: { log.append("open-settings") },
                openHelp: { log.append("open-help") },
                runGlobalCopyJoined: { log.append("copy-joined") },
                runGlobalCopyJoinedWithSpaces: { log.append("copy-joined-spaces") },
                runGlobalCopyNormalized: { log.append("copy-normalized") },
                inspectCodexIntegration: { log.append("inspect") },
                resetValidationState: { log.append("reset") },
                syncClipboardCapture: { log.append("sync") },
                seedHistoryText: { text in log.append("seed:\(text)") },
                reassertForegroundIfNeeded: { log.append("reassert") }
            ),
            panelCallbacks: .init(
                postPanelAction: { _, _ in },
                readTextFile: { _ in "" }
            ),
            editorCallbacks: .init(
                currentSurface: { .none },
                readTextFile: { _ in "" },
                postEditorCommand: { _, _ in },
                saveNoteEditor: { true },
                saveStandaloneNote: { true },
                saveNoteEditorAs: { true },
                saveStandaloneNoteAs: { true },
                saveCurrentEditorToFile: { _ in true },
                closeNoteEditor: {},
                closeStandaloneNote: {},
                respondToAttachedSheet: { _ in }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { _ in },
                setPreviewScroll: { _ in },
                syncPreviewScroll: {},
                selectPreviewText: { _, _ in },
                copyPreviewSelection: {},
                measurePreviewHorizontalOverflow: {},
                clickPreviewFirstLink: {},
                respondToPreviewLinkPrompt: { _ in }
            ),
            settingsCallbacks: .init(
                increaseZoom: {},
                decreaseZoom: {},
                resetZoom: {},
                setSettingsLanguage: { _ in },
                setThemePreset: { _ in },
                setPanelShortcut: { _ in },
                setToggleMarkdownPreviewShortcut: { _ in },
                setGlobalCopyJoinedEnabled: { _ in },
                setGlobalCopyJoinedWithSpacesEnabled: { _ in },
                setGlobalCopyNormalizedEnabled: { _ in }
            )
        )

        XCTAssertTrue(
            coordinator.handleApplicationAction(
                rawAction: ValidationCoordinator.ApplicationAction.openFile.rawValue,
                userInfo: ["path": "/tmp/validation.md"]
            )
        )

        XCTAssertEqual(log, ["open-file:/tmp/validation.md", "reassert"])
    }

    func testValidationCoordinatorRoutesApplicationSeedHistoryAction() {
        var seededText: String?
        let coordinator = ValidationCoordinator(
            applicationCallbacks: .init(
                openPanel: {},
                togglePanelFromStatusItem: {},
                captureSnapshot: { _ in },
                captureWindowImage: { _, _ in },
                openFile: { _ in },
                openNewNote: {},
                openSettings: {},
                openHelp: {},
                runGlobalCopyJoined: {},
                runGlobalCopyJoinedWithSpaces: {},
                runGlobalCopyNormalized: {},
                inspectCodexIntegration: {},
                resetValidationState: {},
                syncClipboardCapture: {},
                seedHistoryText: { text in seededText = text },
                reassertForegroundIfNeeded: {}
            ),
            panelCallbacks: .init(
                postPanelAction: { _, _ in },
                readTextFile: { _ in "" }
            ),
            editorCallbacks: .init(
                currentSurface: { .none },
                readTextFile: { _ in "" },
                postEditorCommand: { _, _ in },
                saveNoteEditor: { true },
                saveStandaloneNote: { true },
                saveNoteEditorAs: { true },
                saveStandaloneNoteAs: { true },
                saveCurrentEditorToFile: { _ in true },
                closeNoteEditor: {},
                closeStandaloneNote: {},
                respondToAttachedSheet: { _ in }
            ),
            previewCallbacks: .init(
                setPreviewWidth: { _ in },
                setPreviewScroll: { _ in },
                syncPreviewScroll: {},
                selectPreviewText: { _, _ in },
                copyPreviewSelection: {},
                measurePreviewHorizontalOverflow: {},
                clickPreviewFirstLink: {},
                respondToPreviewLinkPrompt: { _ in }
            ),
            settingsCallbacks: .init(
                increaseZoom: {},
                decreaseZoom: {},
                resetZoom: {},
                setSettingsLanguage: { _ in },
                setThemePreset: { _ in },
                setPanelShortcut: { _ in },
                setToggleMarkdownPreviewShortcut: { _ in },
                setGlobalCopyJoinedEnabled: { _ in },
                setGlobalCopyJoinedWithSpacesEnabled: { _ in },
                setGlobalCopyNormalizedEnabled: { _ in }
            )
        )

        XCTAssertTrue(
            coordinator.handleApplicationAction(
                rawAction: ValidationCoordinator.ApplicationAction.seedHistoryText.rawValue,
                userInfo: ["path": "seed-text"]
            )
        )

        XCTAssertEqual(seededText, "seed-text")
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

    func testSupportsStandaloneEditorLocalHistoryForFileBackedAndCodexEditors() {
        XCTAssertTrue(
            AppDelegate.supportsStandaloneEditorLocalHistory(
                externalMode: .fileBacked(.markdown),
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertTrue(
            AppDelegate.supportsStandaloneEditorLocalHistory(
                externalMode: .codex,
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertFalse(
            AppDelegate.supportsStandaloneEditorLocalHistory(
                externalMode: .codex,
                hasFileURL: true,
                isOrphanedCodexDraft: true
            )
        )
        XCTAssertFalse(
            AppDelegate.supportsStandaloneEditorLocalHistory(
                externalMode: nil,
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertFalse(
            AppDelegate.supportsStandaloneEditorLocalHistory(
                externalMode: .fileBacked(.text),
                hasFileURL: false,
                isOrphanedCodexDraft: false
            )
        )
    }

    func testShouldBootstrapCurrentEditorOpenedFileTrackingOnlyForEligibleEditors() {
        XCTAssertTrue(
            AppDelegate.shouldBootstrapCurrentEditorOpenedFileTracking(
                isEnabled: true,
                trackOpenedFiles: true,
                externalMode: .fileBacked(.text),
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldBootstrapCurrentEditorOpenedFileTracking(
                isEnabled: true,
                trackOpenedFiles: true,
                externalMode: .codex,
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldBootstrapCurrentEditorOpenedFileTracking(
                isEnabled: false,
                trackOpenedFiles: true,
                externalMode: .fileBacked(.markdown),
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldBootstrapCurrentEditorOpenedFileTracking(
                isEnabled: true,
                trackOpenedFiles: false,
                externalMode: .fileBacked(.markdown),
                hasFileURL: true,
                isOrphanedCodexDraft: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldBootstrapCurrentEditorOpenedFileTracking(
                isEnabled: true,
                trackOpenedFiles: true,
                externalMode: .codex,
                hasFileURL: true,
                isOrphanedCodexDraft: true
            )
        )
    }

    func testStandaloneCommitModeSupportsLocalHistoryForReturnToCodexAndFileBackedModes() {
        XCTAssertTrue(StandaloneNoteEditorView.CommitMode.returnToCodex.supportsLocalHistory)
        XCTAssertTrue(StandaloneNoteEditorView.CommitMode.fileBackedMarkdown.supportsLocalHistory)
        XCTAssertTrue(StandaloneNoteEditorView.CommitMode.fileBackedText.supportsLocalHistory)
        XCTAssertFalse(StandaloneNoteEditorView.CommitMode.pasteToTarget.supportsLocalHistory)
        XCTAssertFalse(StandaloneNoteEditorView.CommitMode.orphanedCodex.supportsLocalHistory)
    }

    func testStandaloneCommitModeUsesTrackedFileLocalHistoryMessagingForReturnToCodexAndFileBackedModes() {
        XCTAssertTrue(StandaloneNoteEditorView.CommitMode.returnToCodex.usesTrackedFileLocalHistoryMessaging)
        XCTAssertTrue(StandaloneNoteEditorView.CommitMode.fileBackedMarkdown.usesTrackedFileLocalHistoryMessaging)
        XCTAssertTrue(StandaloneNoteEditorView.CommitMode.fileBackedText.usesTrackedFileLocalHistoryMessaging)
        XCTAssertFalse(StandaloneNoteEditorView.CommitMode.pasteToTarget.usesTrackedFileLocalHistoryMessaging)
        XCTAssertFalse(StandaloneNoteEditorView.CommitMode.orphanedCodex.usesTrackedFileLocalHistoryMessaging)
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
