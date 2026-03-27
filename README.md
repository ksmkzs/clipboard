# ClipboardHistory

[日本語版 README](./README.ja.md)

ClipboardHistory is a keyboard-first macOS clipboard app for people who constantly reuse copied text, code, prompts, commands, and images.

Instead of treating your clipboard like a single slot, it gives you a compact floating panel with recent history, a pinned working set, and an editor mode for cleaning up pasted text before you send it back into the app you were using.

## Why It Exists

Most clipboard tools are good at storing snippets and bad at helping you actually reuse them.

ClipboardHistory is built around the moments that usually create friction:

- you copied something useful twenty minutes ago and need it again now
- you want a small pinned set of snippets that stays close at hand
- you need to clean up copied text without opening another editor
- you want to paste back into the previous app immediately, without breaking flow

## What Makes It Different

- `Pinned workspace`
  Keep a small manually ordered set of always-available items beside normal history.
- `Editor mode`
  Open text items in-place, edit them, undo or redo changes, indent or outdent blocks, move lines, join lines, or normalize text for command use.
- `Paste-back workflow`
  Choose an item and send it back into the previously active app from the panel.
- `Text and image history`
  Store both kinds of clipboard content in one compact menu bar utility.
- `Local-first by default`
  No accounts, no sync, no remote dependency, no cloud service layer.

## Core Workflow

1. Copy text or an image as usual.
2. Open the panel with `⌘⇧V`.
3. Browse history, pin useful items, or open a text item in editor mode.
4. Press `Return` to paste the selected item back into the app you were just using.

## Features

### History and Reuse

- recent clipboard history for text and images
- pinned items with manual ordering
- quick copy-back and paste-back
- undo and redo for delete, pin, reorder, join, and normalize actions

### Text Editing

- in-panel text editor mode for text items
- native macOS text editing behavior
- indent / outdent
- move line up / down
- join lines
- normalize text for command use
- configurable editor shortcuts

### App Behavior

- configurable global and in-app shortcuts
- launch at login
- experimental Google Translate shortcut with configurable target language

## Keyboard Highlights

### Default panel shortcuts

- open panel: `⌘⇧V`
- translation: `⌘⇧T`
- copy selected item: `⌘C`
- paste selected item: `Return`
- delete selected item: `Delete`
- toggle pinned pane: `Tab`

### Default editor shortcuts

- save: `⌘↩`
- cancel: `Esc`
- indent / outdent: `Tab` / `⇧Tab`
- move line up / down: `⌥↑` / `⌥↓`
- join lines: `⌘J`
- normalize for command use: `⌘⇧J`

## Download

- Download page: https://ksmkzs.github.io/clipboard/
- Latest release: https://github.com/ksmkzs/clipboard/releases/latest

Available release artifacts:

- `ClipboardHistory-mac-universal.zip`
- `ClipboardHistory-mac-apple-silicon.zip`
- `ClipboardHistory-mac-intel.zip`
- `SHA256SUMS.txt`

## Install

1. Download the build that matches your Mac.
2. Unzip `ClipboardHistory.app`.
3. Move it to `/Applications`.
4. Launch it once.
5. Grant Accessibility permission if macOS asks for it.
6. Open Settings to tune shortcuts and launch at login.

## Compatibility

- macOS 14 or later
- Apple Silicon and Intel release targets
- built for local desktop use, not sync-heavy cross-device workflows

## Permissions

ClipboardHistory may require:

- Accessibility permission for global hotkeys and paste-back behavior
- normal clipboard access as part of clipboard history monitoring

## Development

Build from the repository:

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Build signed release artifacts:

```sh
./scripts/package_release.sh
```

This writes the following files to `build/release/`:

- `ClipboardHistory-mac-universal.zip`
- `ClipboardHistory-mac-apple-silicon.zip`
- `ClipboardHistory-mac-intel.zip`
- `SHA256SUMS.txt`

## Verification

Automated verification currently covers:

- editor keyboard command handling
- editor-specific undo / redo routing
- non-text persistence undo / redo logic
- `Enter` paste smoke test against a real TextEdit window
- paste-target switching smoke test across TextEdit and Script Editor

Still worth checking manually on your own machine:

- launch at login after logout / login
- final panel behavior across multiple Macs and macOS versions
- packaged distribution behavior after unzip and first launch

## Repository Layout

- `App/`: app lifecycle, settings state, app delegate
- `Managers/`: clipboard capture, persistence, paste, hotkeys
- `Models/`: SwiftData models
- `Views/`: panel UI, editor UI, AppKit bridges
- `ClipboardHistoryTests/`: focused keyboard and editing tests
- `docs/`: product, UI, and quality notes

## Documentation

- [Japanese README](./README.ja.md)
- [Japanese distribution page](./docs/index.ja.html)
- [Japanese product specification](./docs/product-spec.ja.md)
- [Japanese UI specification](./docs/ui-spec.ja.md)
- [Japanese quality plan](./docs/quality-plan.ja.md)
- [Japanese data model design](./docs/data-model-design.ja.md)

## License

[MIT](./LICENSE)
