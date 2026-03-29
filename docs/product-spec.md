# Product Specification

[日本語版](./product-spec.ja.md)

This document defines the proposed MVP specification for ClipboardHistory as a public macOS open-source application.

## 1. Product Summary

ClipboardHistory is a macOS menu bar app that stores recent clipboard history and lets the user quickly recall previous text or image items from a floating panel.

The first public release should optimize for a reliable clipboard-history experience, while allowing a small number of explicitly marked experimental features behind a clear settings surface.

## 2. Product Goals

The MVP should satisfy these goals:

- reliably capture recent clipboard changes on macOS
- preserve both text and image history
- preserve pinned items so important entries remain easy to access
- let the user reopen recent items from a compact floating panel
- let the user copy an item back to the clipboard
- let the user paste the selected item into the previously active app
- let the user configure essential app behavior from a settings UI
- remain stable across normal daily use, relaunch, and moderate clipboard volume

## 3. Non-Goals For MVP

The MVP does not need to solve everything.

The following are out of scope unless explicitly promoted later:

- account creation or sign-in
- account-based preference sync
- cloud sync
- cross-device sync
- device-to-device clipboard linking
- clipboard categories beyond text and image
- advanced search
- history export / import UI

## 4. Target Users

Primary users:

- macOS users who want a lightweight equivalent to Windows clipboard history
- individual developers, writers, and general desktop users who often need to reuse recent copied text or images

The MVP is optimized for a single-user local desktop workflow, not for shared machines or managed enterprise deployment.

The MVP should not require account setup, remote services, or multi-device pairing during installation or first launch.

## 5. Supported Environment

The exact compatibility matrix is still being finalized, but the MVP should target:

- macOS 14 or later
- Apple Silicon and Intel
- local single-user usage
- menu bar app execution from Xcode or a packaged app bundle

## 6. Core User Stories

1. As a user, I want recently copied text to be stored automatically so I can reuse it later.
2. As a user, I want recently copied images to be stored automatically so I can reuse them later.
3. As a user, I want to open a floating history panel with a global shortcut.
4. As a user, I want to move through the history list with the keyboard.
5. As a user, I want to copy the selected history item back to the clipboard.
6. As a user, I want to paste the selected history item into the app I was using before opening the panel.
7. As a user, I want to pin important clipboard items so they remain easy to find later.
8. As a user, I want basic app preferences, such as startup behavior and shortcut configuration, to be editable in a settings UI.
9. As a user, I want an experimental translation helper whose target language can be changed in settings.
10. As a user, I want a focused text-only editor mode for long text items so I can clean up clipboard content before reuse.
11. As a user, I want to create a new empty manual note and edit it even when the main clipboard panel is closed.

## 7. MVP Functional Requirements

### 7.1 Application Lifecycle

- The app launches as a menu bar app.
- The app does not open a regular main window at startup.
- The app starts clipboard monitoring after launch.
- The app persists history across app relaunch.
- The app can be configured to launch at user login.

### 7.2 Clipboard Capture

- The app monitors the system clipboard continuously while running.
- The app captures non-empty text clipboard content.
- The app captures image clipboard content.
- The app ignores unsupported clipboard payloads in the MVP.
- The app must not create duplicate history entries for internal paste-back operations initiated by the app itself.

### 7.3 History Storage

- History items are stored locally on the user’s machine.
- Text history and image history are both persistent across relaunch.
- The app keeps at most a fixed maximum number of history items.
- When the history limit is exceeded, the oldest items are removed first.
- When an image item is removed, its backing image file is also removed.
- Pinned items are persistent across relaunch.
- Pinned items are not removed by ordinary history trimming.

### 7.4 Pinning

- The user can pin and unpin an item from the UI.
- Pinned items remain discoverable even when normal history grows.
- The UI must make pinned state visually obvious.
- Pinned items should have a stable presentation area that does not depend on recent unpinned activity.
- Pinned items use a persistent manual order that is independent of normal history recency.
- Each history row shows a star affordance at the top-right corner.
- An unpinned item uses a hollow star presentation.
- Activating the star toggles the item between pinned and unpinned.
- When an item is pinned for the first time, it is appended to the end of the pinned order by default.
- The app must support reordering pinned items manually.

### 7.5 Panel Interaction

- The user can toggle the history panel with a global shortcut.
- The default global shortcut for toggling the history panel is Command-Shift-V.
- The panel should place itself using the frontmost window box rather than exact text-caret geometry.
- If a frontmost window box cannot be resolved safely, the panel falls back to a centered position on the active screen.
- The panel keeps the pinned-items area collapsed by default.
- The panel provides an explicit open / close control on the right side for the pinned-items area.
- The pinned-items area can also be opened and closed by keyboard command.
- The default keyboard command for opening and closing the pinned-items area is Tab while the panel is focused.
- The panel presents pinned items in a clearly separated area from ordinary history when opened.
- The panel supports creating a new empty manual note at the top of the list with a dedicated command.
- Ordinary history items are shown in reverse chronological order.
- Each panel reopen resets the ordinary-history selection to the latest visible unpinned item rather than restoring the previous scroll position.
- The user can move selection with the up and down arrow keys.
- The user can dismiss the panel with Escape.
- The user can copy the selected item with Command-C.
- The user can also copy a joined text variant of the selected text item without mutating stored history.
- The user can also copy a normalized text variant of the selected text item without mutating stored history.
- The user can paste the selected item with Return or Enter.
- The default keyboard command for pinning or unpinning the selected item is P while the panel is focused.
- The default keyboard command for moving a selected pinned item within the pinned order is Option-Up and Option-Down while the panel is focused.
- The user can delete the selected item from history with Delete while the panel is focused.

### 7.5.1 Text Editor Mode

- Text items can enter a dedicated editor mode from the row actions.
- Editor mode is text-only and does not apply to image items.
- Editor mode presents the item content inside a focused text box without row chrome mixed into the editable text.
- Text is always edited as plain text.
- Editor mode supports standard text selection, copy, paste, undo, and redo behavior.
- Editor mode supports command-oriented editing actions such as indent, outdent, line move, join lines, and normalization.
- Join lines removes line breaks and trims leading and trailing whitespace on every source line before concatenation.
- Normalize preserves line breaks while trimming leading and trailing whitespace on every line.
- Editor mode may show a side-by-side Markdown preview of the current plain-text draft when requested.
- Editor changes are committed with Command-Return.
- Escape cancels editor mode without saving the current draft.
- A new note command can open a standalone editor-only window when the main panel is not visible.

### 7.6 Clipboard Reuse

- Copying an item from the panel writes that item back to the system clipboard.
- Pasting an item from the panel restores focus to the previously active app when possible.
- After focus is restored, the app synthesizes a paste command.
- While the panel is open, the UI should communicate the intended paste target in a restrained way, such as a compact target label in the header.
- Detailed keyboard guidance should live in a dedicated help surface opened with `Cmd+?`, not in a dense always-visible header legend.
- Paste completion may use a short monochrome confirmation toast or HUD, but should avoid loud or colorful notification treatment.

### 7.7 Settings UI

- The app provides a settings UI for user-configurable behavior.
- The settings UI uses standard macOS settings-window conventions.
- At minimum, settings should include:
  - panel toggle shortcut
  - translation shortcut
  - startup at login
  - translation target language
  - history size limit
  - settings-window language
  - editor command shortcuts
- Each shortcut has a default value and can be changed by the user.
- The default app settings shortcut follows the macOS convention Command-Comma.
- Experimental features must be visibly labeled in settings.
- The main clipboard-history UI remains English-first in the MVP, while the settings window may switch between English and Japanese.

### 7.8 Experimental Translation Feature

- Translation is part of the public application, but marked experimental.
- The user can trigger translation with a dedicated shortcut.
- The default global translation shortcut is Command-Shift-T.
- The translation target language is configurable in settings.
- The translation target language is selected from the language set supported by Google Translate.
- Translation source priority is: currently highlighted text item in the panel, then selected text in the focused app, then clipboard text.
- When possible, translation uses currently selected text.
- If selected text is unavailable, translation may fall back to clipboard text.
- Translation opens Google Translate in the browser and does not create or overwrite clipboard history entries on its own.
- Experimental means the feature should not crash the app, but its exact behavior and support guarantees may evolve faster than the core clipboard-history features.

## 8. Data Rules

These rules should be explicit because they drive tests.

### 8.1 Text

- Text containing only whitespace or newlines is ignored.
- Text is stored in its original form when accepted.
- Duplicate handling must be deterministic and documented.

Proposed MVP rule:

- if a newly captured text item matches an existing history entry, the older duplicate is removed and the new capture becomes the retained entry unless the existing item is pinned

### 8.2 Images

- Image payloads are normalized to a persistent storage format before being saved.
- Large images may be downscaled before persistence.
- Missing or unreadable image files must not crash the app.

Proposed MVP rule:

- normalize stored images to PNG
- cap the maximum dimension at 2000 px during persistence
- if a newly captured image matches an existing history entry, the older duplicate is removed and the new capture becomes the retained entry unless the existing item is pinned

### 8.3 History Limit

Proposed MVP rule:

- default history limit is 150 items
- history trimming is automatic and oldest-first
- history trimming applies only to unpinned items

### 8.4 Pinning And Duplicates

Proposed MVP rule:

- duplicate removal is global across ordinary history, not just consecutive captures
- pinned items are included in duplicate comparison
- pinned items are not removed by ordinary duplicate cleanup unless the user explicitly unpins or deletes them
- if a newly captured item matches a pinned item, the pinned item remains authoritative and no duplicate unpinned item is added

### 8.5 Pin Ordering

Proposed MVP rule:

- pinned items are ordered by a persistent manual pin order, not by capture timestamp
- pinning an unpinned item appends it to the end of the pinned order
- unpinning an item removes it from the pinned order and closes the gap
- manual pinned-item reordering rewrites the persistent pin order deterministically
- the initial pinned reorder UI may support both drag-and-drop and Option-Up / Option-Down keyboard movement inside the panel

### 8.6 Deletion

Proposed MVP rule:

- the user can delete a single selected item from either ordinary history or the pinned region
- deleting a pinned item removes it from persistent pinned order as well
- deleting an image item also removes its backing image file when present
- the MVP does not require a clear-all-history action

## 9. Visual And Interaction Direction

The public MVP should feel restrained rather than decorative.

- The default look should be monochrome or near-monochrome.
- Use simple grayscale surfaces with minimal accent usage.
- Do not rely on rich gradients, glass-heavy styling, or colorful card treatments.
- The default history list should stay visually compact and low-noise.
- Pinned-item discoverability should come from structure and iconography, not from loud styling.
- Settings UI should follow standard macOS controls and layout rather than a custom visual system.
- Small interaction feedback such as copy, paste, pin, and delete confirmation may appear as brief monochrome toast-style responses.

## 10. Permissions

The MVP should explicitly document permission expectations.

- Clipboard capture itself should work without special user prompting beyond normal platform behavior.
- Accessibility permission is required for synthetic paste and selected-text access.
- If required permissions are missing, the app should remain usable for the features that do not depend on those permissions.

## 11. Error Handling Expectations

The public MVP should not crash for expected local failure cases.

Minimum expected behavior:

- startup persistence errors are surfaced and handled without an uncontrolled crash
- image read failures degrade gracefully in the UI
- write failures do not corrupt unrelated stored history
- unsupported clipboard formats are ignored safely

## 12. Observability Expectations

The MVP does not require heavy telemetry, but developer-visible diagnostics should exist.

- important persistence failures should be logged
- permission-related limitations should be understandable during development
- failure paths should be testable without manual clipboard interaction

## 13. Proposed Test Strategy

### 12.1 Unit Tests

- text acceptance and whitespace rejection
- duplicate detection rules
- history trimming behavior
- pinned-item retention rules
- image normalization policy
- shortcut parsing and rendering

### 12.2 Integration Tests

- persistence round-trip for text items
- persistence round-trip for image items
- relaunch with existing stored history
- image file deletion when items are trimmed
- duplicate capture against existing pinned and unpinned items
- startup setting persistence
- internal paste-back not re-entering capture

### 12.3 Manual Compatibility Checks

- first launch behavior
- menu bar icon presence
- global shortcut opens and closes panel
- keyboard navigation works
- pinned items remain visible and actionable
- copy-back works for text and images
- paste-back works into a previously active app
- startup at login behaves as configured
- translation target language changes take effect
- behavior after sleep and wake

## 14. Explicitly Deferred Decisions

These are the main decisions that need user intent before the spec is final:

1. Should duplicate detection for text be exact-content based, normalized-content based, or hash based?
2. Should duplicate detection for images be content-hash based after normalization?
3. Should the MVP include manual deletion / clear-history UI, or defer it?

## 15. Recommended Initial Decisions

My current recommendation for the first public release is:

- keep translation as an explicitly experimental feature
- collapse duplicates globally across ordinary history by removing older duplicates
- target macOS 14+
- include startup at login
- include pinning
- include a small settings UI early
- defer deletion UI until the core storage and pinning model are stable

This keeps the public promise narrow enough that we can actually test and guarantee it.
