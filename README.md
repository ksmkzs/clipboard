# ClipboardHistory

[日本語版 README](./README.ja.md)

If you use macOS, you probably know these annoyances already.

- You copied something, but what was that previous one again... Windows can go back, why can't I?
- You want to send text to a chat agent, but VS Code feels too heavy...
- Why is Markdown preview always more awkward than it should be...
- Why are there so many Apple note / reminder apps and none of them feel right...
- Why am I still pressing `ctrl+k` over and over just to clear long text in Terminal...
- Copying text and sending it to Google Translate again and again...
- Am I really alive just to clean up whitespace in copied text...

ClipboardHistory solves those problems with a compact workflow.

---

## Main Features

- [x] Automatic clipboard history saving and recall
- [x] A lightweight scratch text window
- [x] Pin the text you always end up using
- [x] Automatic whitespace cleanup
- [x] Turn multi-line text into one sentence with one command
- [x] Simple Markdown preview
- [x] Open `.md`, `.txt`, and readable plain-text files directly
- [x] Optional local file history for saved files and watched folders
- [x] Copy already-normalized text in the first place
- [x] Codex CLI integration so drafting text for the CLI feels natural

---

## Windows

### Standard Window

This is the main clipboard history window.

What you can do:

- browse clipboard history
- copy again or paste into the frontmost app
- pin, delete, or rename history items
- normalize text with one command
- edit history items directly
- open Markdown preview

### New Text Window

This is a standalone window for writing new text.  
You can open it from anywhere with one command.  
It saves back into your clipboard workflow, so you can stop collecting files named `Untitled(12).txt`.

What you can do:

- create a new text draft
- open Markdown preview
- send the current text into the frontmost app with `⌘↩`

### Open and Edit Files

You can open `.md`, `.txt`, or any file that can be decoded as plain text.

- `.md` opens with Markdown preview support
- no autosave
- `⌘S` saves
  - if the file already has a path, it saves there
  - if no file path is assigned, it copies the current text to the clipboard
- closing a dirty file asks whether to
  - save to clipboard
  - save as file
  - cancel

If Codex integration is enabled:

- pressing `Ctrl+G` in Codex CLI opens the current draft in this window

### Local File History

Saved files can keep a local snapshot trail on this Mac.

- the editor shows a `Saved •N` pill when snapshots exist
- you can open the history pane, compare a snapshot against the current draft, and restore it into the draft
- you can delete a single snapshot or clear the file's local history
- tracking can come from either
  - files opened in ClipboardHistory
  - a watched directory plus extension filter
- deleted source files can either stay as orphaned history or be pruned after a grace period

---

## Global Shortcuts

- Open / close clipboard history: `⌘⇧V`
- Send the current selected / copied context to Google Translate: `⌘⇧T`
- Open the new text window: `⌃⌘N`
- Replace clipboard with one-line text: `⌘⌥C`
- Replace clipboard with normalized text: `⌘⇧C`

---

## Standard Window Shortcuts

- Close: `Esc`
- Undo / Redo: `⌘Z / ⌘⇧Z`
- Paste the selected item into the current window: `⌘↩`
- Edit the selected item: `E`
- Pin the selected item: `P`
- Delete the selected item: `⌫`
- Show / hide pinned items: `Tab`
- Normalize the selected item: `⌘⇧C`
- Join the selected item into one sentence: `⌘⌥C`

---

## Editor Shortcuts

- Cancel: `Esc`
- Confirm: `⌘↩`
- Undo / Redo: `⌘Z / ⌘⇧Z`
- Indent block: `Tab`
- Outdent block: `⇧Tab`
- Move line up / down: `⌥↑ / ⌥↓`
- Markdown preview: `⌘⌥P`
- Normalize selection whitespace: `⌘⇧C`
- Join selection into one line: `⌘⌥C`

---

## Text Transform Rules

### Normalize Whitespace

Trim leading and trailing whitespace on each line, while preserving line breaks.

Example:

```txt
"  a b   c  
    d"
```

→

```txt
"a b   c
d"
```

### Join Into One Line

Trim leading and trailing whitespace on each line, then remove the line breaks entirely.

Example:

```txt
"  a b   c  
 d"
```

→

```txt
"a b   cd"
```

---

## Codex CLI Integration

ClipboardHistory can act as the external editor target for Codex CLI `Ctrl+G`.

Expected flow:

1. Press `Ctrl+G` in Codex CLI
2. A Codex editor window opens in ClipboardHistory
3. The current Codex input is loaded into that window
4. Edit it
5. Press `⌘↩` to send it back to Codex

Notes:

- The Codex editor window does not autosave back to Codex
- Codex only receives the result when you press `⌘↩`
- Closing the window does not send anything back to Codex
- The orphaned state only appears when the Codex-side connection is lost unexpectedly

---

## Markdown Preview Scope

- supports practical basics such as task lists, code blocks, links, and block quotes
- HTML is not supported
- images are not supported
- links always ask for confirmation before opening in the default browser

---

## Settings

Settings currently include:

- global shortcuts
- standard window shortcuts
- editor shortcuts
- local file history policy
- global special copy on / off
- themes
- UI zoom
- display language
- launch at login
- Codex integration install / inspect / remove

---

## Themes

Several theme presets are included.  
You can preview them in Settings before switching.

Examples:

- Graphite
- Terminal
- Amber
- Frost
- Nord
- Cobalt
- Sakura
- Forest

---

## Accessibility Permission

The following features require Accessibility permission:

- paste-back into the frontmost app
- reading selected text from other apps
- translation
- global special copy

If permission is not granted, some features will not work.

---

## Build

```zsh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug build
```

---

## Validation

- full automated scheme check:

```zsh
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

- broader validation entry point:

```zsh
./ClipboardHistoryTests/run_validation_suite.sh
```

- useful manual-check documents:
  - [Local history debug file](./docs/local-history-debug.md)
  - [Markdown preview stress test](./docs/markdown-preview-stress-test.md)
  - [Validation matrix (Japanese)](./docs/validation-matrix.ja.md)

---

## Release Build

```zsh
./scripts/package_release.sh
```

Generated files:

- `build/release/ClipboardHistory.dmg`
- `build/release/ClipboardHistory-mac-universal.zip`
- `build/release/ClipboardHistory-mac-apple-silicon.zip`
- `build/release/ClipboardHistory-mac-intel.zip`
- `build/release/SHA256SUMS.txt`

---

## Status

ClipboardHistory is still evolving.  
Shortcuts, external editor integration, window behavior, themes, and helper workflows may continue to be refined.

---

## License

[MIT](./LICENSE)
