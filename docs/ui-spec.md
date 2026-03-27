# UI Specification

This document defines the intended user interface for the first public ClipboardHistory release before SwiftUI implementation changes are made.

## 1. UI Principles

The UI should follow these constraints:

- restrained, monochrome, and low-noise
- fast to scan and keyboard-friendly
- compact by default, with secondary surfaces hidden until needed
- standard macOS behavior where custom UI does not add real value

What this explicitly means:

- prefer grayscale and neutral surfaces over accent-heavy styling
- avoid decorative gradients, glass-heavy treatments, and colorful status states
- keep typography simple and system-native
- use structure, spacing, and icons for hierarchy instead of visual ornament

## 2. Primary Surfaces

The app has three primary surfaces:

1. menu bar status item
2. history panel
3. settings window

There is no regular document-style main window in the MVP.

## 3. Menu Bar Status Item

The menu bar item remains minimal.

Behavior:

- left click toggles the history panel
- right click opens the status menu

Status menu contents:

- show / hide history panel
- run translation now
- configure panel shortcut
- configure translation shortcut
- open settings
- quit

Notes:

- the menu bar item is utility-first, not a dashboard
- no counters, badges, or noisy indicators in the MVP

## 4. History Panel Overview

The history panel is the core product UI.

Panel goals:

- let the user reopen recent history quickly
- keep frequent actions available from the keyboard
- expose pinned items without permanently shrinking the main list

Panel size baseline:

- keep the current baseline around `420 x 560`
- allow resizing, but preserve usability at the default size

Panel structure:

1. header
2. main content region
3. hidden / collapsible pinned region on the right

Placement behavior:

- prefer opening the panel near the active text insertion caret when that position can be resolved safely
- avoid covering the insertion point when a nearby placement is available
- fall back to the center of the active screen when caret-aware placement is unavailable, unstable, or would place the panel off-screen
- placement should feel utility-first rather than animated or theatrical

## 5. Header

The header should stay small and quiet.

Required contents:

- app title: `Clipboard History`
- compact keyboard help text
- compact paste-target hint when available, such as `Paste to Cursor in VS Code`
- pinned-area open / close affordance on the right side

Header behavior:

- do not add a search field in the MVP
- do not place large controls or rich visual chrome here
- the open / close affordance for pinned items should be visibly interactive but not dominant
- the paste-target hint should stay secondary and quiet, not a large banner

Recommended header copy:

- first line: product title
- second line: compact keyboard legend such as `↑↓ Select  Cmd+C Copy  Enter Paste  P Pin  Tab Pins  Del Delete  Esc Close`

## 6. Main Content Region

The main content region shows ordinary history items only.

Rules:

- unpinned history appears in reverse chronological order
- each row is selectable
- the selected row remains visually obvious
- keyboard navigation should scroll the selected row into view
- each panel reopen should reset selection to the latest visible unpinned item instead of restoring the previous scroll position

Empty state:

- if there is no history, show a quiet empty-state message
- the empty state should explain that copied text and images will appear automatically
- the empty state should not include illustration-heavy design

## 7. Pinned Region

The pinned region is a secondary surface, not a permanent split view.

Rules:

- collapsed by default
- opened from the right side of the panel
- visually separated from ordinary history
- contains only pinned items
- pinned items are shown in persistent manual order, not recency order

Open / close behavior:

- open / close button lives near the top-right area of the panel
- `Tab` toggles the pinned region while the panel is focused
- opening the pinned region should not replace the ordinary history list
- closing the pinned region returns focus to the ordinary selection model

Width behavior:

- when open, the pinned region uses a narrow side width that still supports text scanning
- it should not consume more space than the ordinary history list
- pinned rows should use a slightly denser, more compact layout than ordinary history rows

Animation:

- if animation is used, it should be subtle and short
- avoid springy or decorative motion

## 8. Row Design

Rows should remain compact and readable.

Shared row rules:

- monochrome or near-monochrome surfaces
- rounded rectangular hit target is acceptable
- selected state must be clear
- pinned state must be visible without dominating the row
- star affordance sits at the top-right corner

### 8.1 Text Row

Required elements:

- text preview
- pin star

Text-row behavior:

- show up to roughly 3 lines in the main history list
- preserve line breaks visually when possible
- keep the copied text preview itself literal rather than wrapping it with decorative brackets
- if the copied text starts or ends with meaningful whitespace, show a compact hint below the preview
  - examples: `start ␠×2`, `end ␠×1`, `⇥ start`, `↵ end`
- truncate overflow rather than expanding the row excessively

### 8.2 Image Row

Required elements:

- image preview
- pin star

Image-row behavior:

- fit preview within a compact maximum height
- keep aspect ratio
- if image loading fails, show a quiet text fallback

### 8.3 Pin Star

Rules:

- unpinned items use a hollow star
- pinned items use a filled or clearly active star state
- the star should be clickable independently of row selection
- clicking the star toggles pinned state without forcing paste or copy

## 9. Selection And Keyboard Model

The panel is keyboard-first.

Required keyboard behavior:

- `Up` / `Down`: move selection within the active region
- `Enter`: paste selected item
- `Cmd+C`: copy selected item back to clipboard
- `Esc`: close panel
- `P`: toggle pin state for selected item
- `Tab`: open / close pinned region
- `Delete`: remove selected item
- `Option+Up` / `Option+Down`: move the selected pinned item within the pinned order

Selection rules:

- ordinary history has a single active selection
- pinned region may need its own active selection if it becomes focusable
- the UI should avoid ambiguous dual selection states

Recommended MVP selection model:

- keep selection focus in one region at a time
- if the pinned region opens, focus remains in the current region until the user explicitly changes region

Open question:

- what exact keyboard action should move active focus between ordinary history and pinned items once the pinned region is open?

## 10. Pinned Reordering UI

Pinned items must support manual ordering, but the first implementation should keep the interaction simple.

Recommended staged approach:

1. data model and persistence first
2. visible pinned list second
3. reordering UI third

Recommended eventual UI:

- when pinned region is open, provide a simple reorder mode for pinned items
- prefer a lightweight interaction such as drag-and-drop plus keyboard movement with `Option+Up` / `Option+Down`
- do not introduce a complex kanban-like interaction

MVP note:

- the data layer already supports manual pin order
- the first UI iteration should ship keyboard reordering before any more elaborate drag affordance

## 11. Settings Window

The settings window should use standard macOS settings conventions.

The first version can be a single-page settings window.

Required sections:

### 11.1 General

- settings-window language
- launch at login
- history size limit

### 11.2 Shortcuts

- panel toggle shortcut
- translation shortcut

### 11.3 Translation

- target language selector
- short explanatory text that translation is experimental

Settings principles:

- use standard toggles, pickers, and steppers / numeric fields
- avoid custom settings navigation unless the surface becomes crowded later
- the settings window may switch between English and Japanese
- the rest of the app UI remains English-first in the MVP
- do not add account, sign-in, or cross-device-linking controls

## 12. Visual Tokens

The UI should be near-monochrome by default.

Recommended direction:

- background: macOS window background / control background family
- row background: subtle neutral contrast
- text: primary / secondary semantic colors
- border: faint gray
- active accent: minimal usage, ideally desaturated

Avoid:

- saturated accent fills across the whole row
- purple-heavy defaults
- shadows that make the panel feel glossy or inflated

## 13. Feedback And Deletion

The panel should acknowledge important actions without becoming noisy.

Rules:

- copy, paste, pin, unpin, reorder, and delete may show a brief monochrome toast or HUD
- feedback should be text-first, short-lived, and low contrast enough to avoid looking like a system warning
- delete applies to a single selected item in either ordinary history or the pinned region
- delete should not require a modal confirmation for the MVP

Recommended feedback copy:

- `Copied`
- `Pasted`
- `Pinned`
- `Unpinned`
- `Deleted`

## 14. Accessibility And Usability Notes

- selected state must remain legible in both light and dark appearances
- hit targets for the star and pinned toggle affordance must be large enough for mouse use
- keyboard help should not be the only way to discover pinning
- image-only items still need a textual fallback when loading fails

## 15. Current Implementation Notes

The current implementation already includes:

- a pinned region with manual ordering
- row pin and delete actions
- settings UI
- editor mode for text items
- feedback toasts
- frontmost-window-based panel placement

Remaining polish is mostly in compatibility verification, public packaging, and UI refinement rather than missing core surfaces.

## 16. Recommended UI Build Order

1. Refactor `ClipboardHistoryView` into explicit regions: header, main list, pinned region shell
2. Reset selection and scroll state on reopen so the latest history item is selected
3. Add pin star to rows
4. Add pinned-region open / close state and layout
5. Split the list into ordinary history and pinned items
6. Add keyboard actions for `P`, `Tab`, `Delete`, and pinned-item reorder
7. Add caret-aware placement and target hinting
8. Add lightweight feedback toast / HUD
9. Add settings window
10. Add drag-and-drop pinned reorder if the keyboard model feels insufficient

## 17. Open Questions

These still need user intent before the UI is fully frozen:

1. When the pinned region is open, how should keyboard focus move between ordinary history and pinned items?
2. Does drag-and-drop meaningfully improve pinned reordering beyond the required `Option+Up` / `Option+Down` keyboard behavior?
