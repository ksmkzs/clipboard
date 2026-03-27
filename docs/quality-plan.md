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
- editor normalize for command: Command-Shift-J

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

## 4. Execution Order

1. Clean repository structure and confirm the project builds from source control.
2. Freeze MVP scope.
3. Refactor for testability.
4. Add unit tests for pure logic and persistence rules.
5. Add integration tests for pasteboard capture and startup/relaunch behavior.
6. Add manual compatibility checklist and release checklist.
