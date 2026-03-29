# Quality Plan

[日本語版](./quality-plan.ja.md)

This document defines the initial OSS hardening plan for ClipboardHistory.

## 1. Compatibility

The repository will not claim support until these are explicit and verified:

- supported macOS versions
- supported CPU architectures: Apple Silicon and Intel
- required permissions: Accessibility and any others implied by hotkeys or paste simulation
- expected packaging path: debug run, unsigned app, signed app, notarized build

Current compatibility status:

- release build settings target `arm64 x86_64`
- deployment target is `macOS 14.0`
- current runtime verification has been exercised on Intel only

Remaining compatibility tasks:

1. Normalize the Xcode deployment target and build settings.
2. Verify a clean build from the repository checkout.
3. Run the app on at least one Apple Silicon machine and record any permission prompts.
4. Verify startup, menu bar presence, panel toggle, clipboard capture, and paste back behavior.
5. Check sleep/wake, launch-at-login, and app relaunch behavior.

## 2. Functionality

The first public MVP should have a tightly defined scope.

Candidate MVP:

- text clipboard history
- image clipboard history
- item pinning
- manual ordering of pinned items
- single-item deletion
- history recall from a floating panel
- copy-back to clipboard
- paste into the previously active app
- configurable global shortcut for panel toggle
- startup at login
- settings UI for core preferences
- text-item editor mode with keyboard editing commands
- experimental translation with configurable target language

Features that need an explicit decision before public release:

- search
- the exact duplicate-detection algorithm for text and images
- whether a clear-history action should ship in the MVP

Initial functionality tasks:

1. Write a product spec for the MVP and non-goals.
2. Separate clipboard-history behavior from optional helper features.
3. Define the expected behavior for duplicates, empty text, image normalization, and history trimming.
4. Define pinned-item behavior and settings behavior.
5. Add regression tests for the agreed behavior.

Additional UI constraints already chosen:

- the default visual style should remain monochrome or near-monochrome
- pinned items use a star affordance on each row
- the pinned area is collapsed by default and opened explicitly rather than always occupying space
- pinned items use a persistent manual order independent of recency
- pinned items should use a slightly more compact presentation than ordinary history items
- panel reopening should reset to the latest visible history item rather than preserving the previous scroll position
- the panel should place itself from the frontmost window box rather than exact caret geometry
- the panel should communicate paste target in a restrained way rather than covering the insertion point unnecessarily
- copy, paste, pin, delete, undo, redo, and save should have small green feedback responses
- translation target language selection follows the supported Google Translate language set
- all keyboard shortcuts have defaults but remain user-editable
- default shortcuts are:
  - panel toggle: Command-Shift-V
  - translation: Command-Shift-T
  - panel pin toggle: P
  - panel pinned-area open / close: Tab
  - pinned reorder within panel: Option-Up / Option-Down
- panel delete selected item: Delete
- editor save: Command-Return
- editor indent / outdent: Tab / Shift-Tab
- editor line up / down: Option-Up / Option-Down
- editor join lines: Command-J
- editor normalize: Command-Shift-J

## 3. Robustness

The public app needs clear behavior for failures and edge cases.

Primary risks already visible in the imported code:

- persistence paths are inconsistent between the SwiftData store and image cache
- model container creation uses force unwraps
- duplicate detection uses weak fingerprints
- there are no automated tests for persistence or failure modes

Robustness test matrix:

- rapid repeated copies of different text payloads
- repeated copies of identical text and identical images
- repeated copies that match existing pinned items
- pinning, unpinning, and pin-order normalization
- large text payloads
- large images and image downscaling
- corrupted or missing image files
- corrupted SwiftData store
- save failures due to filesystem issues
- app relaunch after stored history exists
- internal paste operations not re-entering capture
- history limit trimming and associated image deletion
- pinned-area collapsed / expanded interaction state
- deleting pinned and unpinned items, including image cleanup and pin-order normalization
- panel reopen selection reset after close / reopen cycles
- caret-aware placement fallback when caret location cannot be resolved

Initial robustness tasks:

1. Introduce seams so clipboard access and persistence can be tested without the system pasteboard.
2. Replace crash-prone startup with recoverable error handling.
3. Unify the application support directory structure.
4. Strengthen duplicate detection and persistence invariants.
5. Add automated tests for the high-risk cases above.

## 4. Test Specification Inventory

The repository should treat the following as explicit test targets rather than informal behavior.

### 4.1 Core data and persistence rules

- history items are ordered by newest timestamp first
- pinned items are ordered only by `pinOrder`
- pinned items are excluded from ordinary history lists
- pinning appends to the end of current pinned order
- unpinning renormalizes remaining pinned order
- pin labels are trimmed, persisted, and removable by empty input
- deleting an item removes associated image files and pin labels
- restoring a deleted item preserves timestamp, pin state, and pin label
- text edits preserve original timestamp unless the operation explicitly requests recency bump
- history trimming affects only unpinned history items
- duplicate capture replaces unpinned duplicates but refuses to replace pinned duplicates

### 4.2 Text editing rules

- editor mode owns its own text-editing undo/redo behavior
- panel shortcuts that reuse editor keys, especially `Tab`, must not leak into editor mode while text editing is active
- indent / outdent operate on the selected lines
- move line up / down preserves selection and line order correctly
- join lines and normalize-for-command are undoable
- normalize-for-command preserves line structure; join lines is the explicit newline-flattening command
- clipboard-oriented commands do not corrupt editor state boundaries
- commit, cancel, and help shortcuts must route to the editor correctly without stealing ordinary text-editing behavior
- `⌘A`, `⌘C`, `⌘X`, `⌘V`, `⌘←→`, `⌥←→`, delete variants, and `Esc` behave compatibly enough with standard macOS text editing

### 4.3 Panel workflow rules

- Enter pastes the selected item into the currently active target app
- changing target apps between panel invocations changes the actual paste target
- panel-level undo/redo covers pin, delete, reorder, and non-editor text transforms
- join / normalize in ordinary panel mode edit the selected stored item in place rather than creating a new newest item

## 5. Complex Regression Workflows

The repository should keep five high-complexity workflows that pass only when multiple subsystems cooperate correctly.

1. Pinned delete / restore / transform workflow
   - label, pin, reorder, delete, restore, restore pin state, and edit text while preserving order and timestamp invariants
2. History trim and duplicate workflow
   - pinned duplicate rejection, unpinned duplicate replacement, and max-history trimming in one scenario
3. Image delete / restore workflow
   - image file persistence, pin label persistence, delete cleanup, restore rehydration, and image loading
4. Editor command round-trip workflow
   - indent, move line, join, then multi-step undo/redo with exact text expectations
5. Editor clipboard + normalize workflow
   - cut, paste, normalize, then exact undo/redo boundary verification

## 6. Diagnostic Breakdown Suites

When a complex regression test fails, smaller suites should isolate the fault domain.

- `ClipboardDataManagerBehaviorTests`
  - ordering, pinning, trimming, deletion, restore, labels, duplicate handling
- `EditorNSTextViewKeyboardTests`
  - standard text-editing key behavior and editor command routing
- `PanelKeyboardRoutingTests`
  - panel/editor routing boundaries and help-command visibility metadata
- `AppDelegateTargetSelectionTests`
  - paste target selection and frontmost-app routing
- smoke scripts
  - `enter_paste_smoke.sh`
  - `enter_paste_target_switch_smoke.sh`

## 7. Execution Order

1. Freeze the specification inventory above.
2. Keep the five complex workflow regressions green.
3. Keep the diagnostic breakdown suites narrow and fast.
4. Run target-selection and paste smoke tests after panel routing changes.
5. Run editor-keyboard tests after editor-command changes.
6. Expand compatibility and release checks only after the workflow tests stay green.
