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

## Distribution

To build signed release artifacts for distribution:

```sh
./scripts/package_release.sh
```

This writes the following files to `build/release/`:

- `ClipboardHistory-mac-universal.zip`
- `ClipboardHistory-mac-apple-silicon.zip`
- `ClipboardHistory-mac-intel.zip`
- `SHA256SUMS.txt`

The repository also includes a distribution page at [`docs/index.html`](./docs/index.html).
If GitHub Pages is enabled from the `docs/` folder on `main`, that page can be used as the public download page and points to GitHub Releases `latest` assets.

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
4. Launch the app once.
5. If macOS prompts for permission, grant Accessibility access.
6. Open Settings to configure shortcuts and launch at login.

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

## Permissions

ClipboardHistory may require:

- Accessibility permission, for panel hotkeys and paste-back into the previously active app
- normal clipboard access as part of clipboard history monitoring

## Known Limitations

- Runtime verification is strongest on Intel macOS so far; Apple Silicon build compatibility is verified from universal and thin release artifacts.
- Launch at login is implemented and registered through macOS login items, but practical behavior depends on running the packaged app from `/Applications`.
- Some behavior depends on macOS Accessibility APIs and may vary by the currently focused app.

## Release Notes Template

```md
## ClipboardHistory v0.1.0

ClipboardHistory is a local-first macOS menu bar app for recalling recent text and image clipboard items from a compact floating panel.

### Highlights
- recent text and image clipboard history
- pinned items with manual ordering
- text editor mode for long text items
- copy-back and paste-back into the previously active app
- configurable shortcuts and launch at login
- experimental translation shortcut

### Downloads
- Universal: `ClipboardHistory-mac-universal.zip`
- Apple Silicon: `ClipboardHistory-mac-apple-silicon.zip`
- Intel: `ClipboardHistory-mac-intel.zip`
- Checksums: `SHA256SUMS.txt`

### Requirements
- macOS 14 or later

### Install
1. Download the build that matches your Mac.
2. Unzip `ClipboardHistory.app`.
3. Move it to `/Applications`.
4. Launch it once.
5. Grant Accessibility permission if macOS prompts for it.

### Notes
- Use the Universal build unless you specifically want an architecture-specific download.
- Move `ClipboardHistory.app` into `/Applications` before enabling `Launch at Login`.
- Accessibility permission may be required for panel hotkeys and paste-back behavior.
- Translation is experimental and opens Google Translate in your browser.
```

## Repository Layout

- `App/`: app lifecycle, settings state, and app delegate
- `Managers/`: clipboard capture, persistence, paste, and hotkeys
- `Models/`: SwiftData models
- `Views/`: panel UI, editor UI, and AppKit bridges
- `ClipboardHistoryTests/`: focused keyboard and editing tests
- `docs/`: product, UI, and quality notes

## License

[MIT](./LICENSE)
