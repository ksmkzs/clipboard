# ClipboardHistory

ClipboardHistory is a macOS menu bar app that keeps recent clipboard history for text and images and lets you reopen, pin, edit, copy, and paste older items from a compact floating panel.

## Features

- text and image clipboard history
- pinned items with manual ordering
- text-item editing mode with keyboard editing commands
- copy-back and paste-back into the previously active app
- configurable shortcuts and launch-at-login setting
- experimental Google Translate shortcut with configurable target language

## Scope

ClipboardHistory is intentionally local-first.

- no account setup
- no cloud sync
- no cross-device clipboard sync
- no remote service dependency

## Compatibility

Current target:

- macOS 14+
- Apple Silicon and Intel build targets

Current verification status:

- repository build verified from terminal
- editor keyboard command harness verified
- runtime behavior repeatedly exercised on an Intel macOS environment
- Intel and Apple Silicon are targeted by build settings, but multi-machine runtime verification is still pending before public release

## Keyboard Highlights

Default shortcuts:

- panel toggle: `⌘⇧V`
- translation: `⌘⇧T`
- copy selected item: `⌘C`
- paste selected item: `Return`
- delete selected item: `Delete`
- toggle pinned pane: `Tab`

Editor mode adds:

- save: `⌘↩`
- cancel: `Esc`
- indent / outdent: `Tab` / `⇧Tab`
- move line up / down: `⌥↑` / `⌥↓`
- join lines: `⌘J`
- normalize for command: `⌘⇧J`

## Build

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Tests

The project now includes editor keyboard tests under [`ClipboardHistoryTests`](./ClipboardHistoryTests).

Current automated verification covers:

- editor keyboard command handling
- editor-specific undo / redo routing
- non-text persistence undo / redo logic
- `Enter` paste smoke test against a real TextEdit window:
  `ClipboardHistoryTests/enter_paste_smoke.sh 5`
- paste target switch smoke test across TextEdit and Script Editor:
  `ClipboardHistoryTests/enter_paste_target_switch_smoke.sh`

UI-level manual verification is still required for:

- launch at login after logout / login
- final panel behavior across multiple Macs and macOS versions
- packaging and signed distribution behavior

## Repository Layout

- `App/`: app lifecycle, settings state, and app delegate
- `Managers/`: clipboard capture, persistence, paste, and hotkeys
- `Models/`: SwiftData models
- `Views/`: panel UI, editor UI, and AppKit bridges
- `ClipboardHistoryTests/`: focused keyboard and editing tests
- `docs/`: product, UI, and quality notes

## License

[MIT](./LICENSE)
