#!/bin/zsh
set -euo pipefail
setopt typesetsilent

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${CLIPBOARD_HISTORY_APP_BUNDLE:-/Applications/ClipboardHistory.app}"
APP_BIN="${CLIPBOARD_HISTORY_APP_BIN:-$APP_BUNDLE/Contents/MacOS/ClipboardHistory}"
COMMAND_HELPER="$ROOT_DIR/ClipboardHistoryTests/app_validation_command.swift"
STRESS_MARKDOWN="$ROOT_DIR/docs/markdown-preview-stress-test.md"
TMP_DIR_RAW="${VALIDATION_EDITOR_PREVIEW_TMP_DIR:-$ROOT_DIR/.codex-tmp/editor-preview-hotkeys}"
if [[ "$TMP_DIR_RAW" = /* ]]; then
  TMP_DIR="$TMP_DIR_RAW"
else
  TMP_DIR="$ROOT_DIR/$TMP_DIR_RAW"
fi
KEEP_ARTIFACTS="${KEEP_UI_SMOKE_ARTIFACTS:-0}"
SECTION="${VALIDATION_SECTION:-all}"
APP_PID=""
ORIGINAL_CLIPBOARD="$(pbpaste || true)"

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
  pkill -x ClipboardHistory >/dev/null 2>&1 || true
  printf "%s" "$ORIGINAL_CLIPBOARD" | pbcopy
  if [[ "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

ensure_paths() {
  [[ -x "$APP_BIN" ]] || { echo "Missing app binary: $APP_BIN" >&2; exit 2; }
  [[ -f "$COMMAND_HELPER" ]] || { echo "Missing helper: $COMMAND_HELPER" >&2; exit 2; }
  [[ -f "$STRESS_MARKDOWN" ]] || { echo "Missing stress markdown: $STRESS_MARKDOWN" >&2; exit 2; }
  mkdir -p "$TMP_DIR"
}

post_command() {
  swift "$COMMAND_HELPER" "$@"
}

snapshot_path_for() {
  echo "$TMP_DIR/$1.json"
}

capture_snapshot() {
  local name="$1"
  local snapshot_file
  snapshot_file="$(snapshot_path_for "$name")"
  rm -f "$snapshot_file"
  local dispatch_attempt
  for dispatch_attempt in {1..4}; do
    post_command snapshot "$snapshot_file"
    for _ in {1..40}; do
      [[ -f "$snapshot_file" ]] && return 0
      sleep 0.05
    done
  done
  echo "Timed out waiting for snapshot $snapshot_file" >&2
  return 1
}

wait_for_snapshot_condition() {
  local name="$1"
  local condition="$2"
  local attempts="${3:-40}"
  local snapshot_file
  snapshot_file="$(snapshot_path_for "$name")"
  for _ in $(seq 1 "$attempts"); do
    capture_snapshot "$name" || return 1
    if python3 - "$snapshot_file" "$condition" <<'PY'
import json, sys
class SafeDict(dict):
    def __missing__(self, key):
        return None
path, expr = sys.argv[1], sys.argv[2]
data = SafeDict(json.load(open(path)))
safe_funcs = {"abs": abs, "len": len, "min": min, "max": max}
if eval(expr, {"__builtins__": {}}, {"data": data, **safe_funcs}):
    raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 0.15
  done
  echo "Timed out waiting for condition: $condition" >&2
  [[ -f "$snapshot_file" ]] && cat "$snapshot_file" >&2
  return 1
}

launch_clean_app() {
  pkill -x ClipboardHistory >/dev/null 2>&1 || true
  "$APP_BIN" --validation-hooks >/dev/null 2>&1 &
  for _ in {1..80}; do
    APP_PID="$(pgrep -n -f "$APP_BIN" || true)"
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
      local readiness_file="$TMP_DIR/launch-ready.json"
      for _ in {1..40}; do
        rm -f "$readiness_file"
        post_command snapshot "$readiness_file"
        for _ in {1..20}; do
          if [[ -f "$readiness_file" ]]; then
            sleep 0.4
            return 0
          fi
          sleep 0.05
        done
        sleep 0.15
      done
      echo "Validation hooks not ready" >&2
      exit 3
    fi
    sleep 0.1
  done
  echo "ClipboardHistory did not launch cleanly" >&2
  exit 3
}

reset_validation_state() {
  post_command dispatch resetValidationState
  wait_for_snapshot_condition "validation-reset" "(not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and (not data['settingsVisible']) and (not data['helpVisible']) and data['historyCount'] == 0 and data['pinnedCount'] == 0 and data['settingsLanguage'] == 'en' and data['interfaceThemePreset'] == 'graphite' and (data['interfaceZoomScale'] > 0.999) and (data['interfaceZoomScale'] < 1.001)" 60
}

capture_clipboardhistory_windows() {
  local label="$1"
  capture_snapshot "${label}-capture-state" || return 1
  local snapshot_file
  snapshot_file="$(snapshot_path_for "${label}-capture-state")"
  python3 - "$snapshot_file" <<'PY' | while IFS= read -r window_kind; do
import json, sys
data = json.load(open(sys.argv[1]))
kinds = []
if data.get("panelVisible"):
    kinds.append("panel")
if data.get("standaloneNoteVisible"):
    kinds.append("standaloneNote")
if data.get("noteEditorVisible"):
    kinds.append("noteEditor")
if data.get("settingsVisible"):
    kinds.append("settings")
if data.get("helpVisible"):
    kinds.append("help")
for kind in kinds:
    print(kind)
PY
    [[ -n "$window_kind" ]] || continue
    post_command capture-window "$window_kind" "$TMP_DIR/${label}-${window_kind}.png"
  done
}

assert_file_contains() {
  local file_path="$1"
  local expected="$2"
  python3 - "$file_path" "$expected" <<'PY'
from pathlib import Path
import sys
path, expected = Path(sys.argv[1]), sys.argv[2]
actual = path.read_text()
if actual != expected:
    raise SystemExit(f"unexpected file content in {path}: {actual!r}")
PY
}

set_editor_text() {
  local text_path="$1"
  post_command dispatch setCurrentEditorText "$text_path"
}

send_keystroke() {
  local key="$1"
  local modifiers="$2"
  osascript <<APPLESCRIPT
tell application "System Events" to keystroke "$key" using {$modifiers}
APPLESCRIPT
}

send_key_code() {
  local key_code="$1"
  local modifiers="$2"
  osascript <<APPLESCRIPT
tell application "System Events" to key code $key_code using {$modifiers}
APPLESCRIPT
}

prepare_textedit_document() {
  local base_text="$1"
  osascript \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "TextEdit" to if (count of documents) > 0 then close every document saving no' \
    -e "tell application \"TextEdit\" to make new document with properties {text:\"$base_text\"}" \
    -e 'tell application "System Events" to key code 124 using {command down}' \
    -e 'delay 0.15'
}

textedit_contents() {
  osascript -e 'tell application "TextEdit" to get text of document 1'
}

run_preview_checks() {
  echo "==> preview interactions #104 #105 #106 #107 #108 #109 #110 #111 #132 #133 #134"
  launch_clean_app
  reset_validation_state
  post_command open-file "$STRESS_MARKDOWN"
  wait_for_snapshot_condition "preview-open" "data['fileEditorVisible'] and data['noteEditorPreviewVisible']" 40
  post_command dispatch setCurrentPreviewWidth 280
  wait_for_snapshot_condition "preview-width-updated" "data['noteEditorPreviewWidth'] is not None and abs(data['noteEditorPreviewWidth'] - 280) < 8" 40
  post_command dispatch setCurrentPreviewScroll 0.92
  wait_for_snapshot_condition "preview-scrolled" "data['previewScrollFraction'] is not None and data['previewScrollFraction'] > 0.85" 40
  post_command dispatch setCurrentEditorSelection 0
  post_command dispatch syncCurrentPreviewScroll
  wait_for_snapshot_condition "preview-scroll-stable-after-editor-change" "data['previewScrollFraction'] is not None and data['previewScrollFraction'] > 0.85" 40
  post_command dispatch selectCurrentPreviewText "alpha bravo"
  wait_for_snapshot_condition "preview-selection-text" "data['previewSelectedText'] == 'alpha bravo charlie delta echo foxtrot golf hotel india'" 40
  post_command dispatch copyCurrentPreviewSelection
  wait_for_snapshot_condition "preview-selection-copied" "data['clipboardText'] == 'alpha bravo charlie delta echo foxtrot golf hotel india'" 40
  post_command dispatch selectCurrentPreviewCodeBlock "copy this code block if selection works"
  wait_for_snapshot_condition "preview-code-selection" "'copy this code block if selection works' in (data['previewSelectedText'] or '')" 40
  post_command dispatch copyCurrentPreviewSelection
  wait_for_snapshot_condition "preview-code-copied" "data['clipboardText'] == 'copy this code block if selection works\\nline two\\nline three'" 40
  post_command dispatch clickCurrentPreviewFirstLink
  wait_for_snapshot_condition "preview-link-prompt" "data['previewLinkPromptVisible'] and data['previewLinkPromptURL'] == 'https://openai.com/'" 40
  post_command dispatch respondToPreviewLinkPrompt cancel
  wait_for_snapshot_condition "preview-link-cancelled" "(not data['previewLinkPromptVisible']) and data['previewLastOpenedURL'] is None" 40
  post_command dispatch clickCurrentPreviewFirstLink
  wait_for_snapshot_condition "preview-link-prompt-reopen" "data['previewLinkPromptVisible'] and data['previewLinkPromptURL'] == 'https://openai.com/'" 40
  post_command dispatch respondToPreviewLinkPrompt open
  wait_for_snapshot_condition "preview-link-opened" "(not data['previewLinkPromptVisible']) and data['previewLastOpenedURL'] == 'https://openai.com/'" 40
  post_command dispatch setCurrentPreviewScroll 1.0
  wait_for_snapshot_condition "preview-scroll-end" "data['previewScrollFraction'] is not None and data['previewScrollFraction'] > 0.98" 40
  post_command dispatch selectCurrentPreviewText "ここまで表示されていれば"
  wait_for_snapshot_condition "preview-end-marker-selected" "'ここまで表示されていれば' in (data['previewSelectedText'] or '')" 40
  capture_clipboardhistory_windows "preview-end-marker-selected"
}

run_standalone_note_checks() {
  echo "==> standalone note save/close flows #136 #139 #140 #142 #143"
  launch_clean_app
  reset_validation_state
  post_command open-new-note
  wait_for_snapshot_condition "standalone-empty-open" "data['standaloneNoteVisible'] and data['standaloneNoteDraftText'] == ''" 40
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "standalone-empty-closed" "(not data['standaloneNoteVisible']) and data['historyCount'] == 0 and (data['clipboardText'] is None or data['clipboardText'] == '')" 40

  local standalone_text_file="$TMP_DIR/standalone-body.txt"
  printf "%s" "standalone clipboard save" > "$standalone_text_file"
  post_command open-new-note
  wait_for_snapshot_condition "standalone-save-open" "data['standaloneNoteVisible']" 40
  set_editor_text "$standalone_text_file"
  wait_for_snapshot_condition "standalone-save-dirty" "data['standaloneNoteDirty'] and data['standaloneNoteDraftText'] == 'standalone clipboard save'" 40
  post_command dispatch saveCurrentEditor
  wait_for_snapshot_condition "standalone-saved-clipboard" "data['standaloneNoteSaveDestination'] == 'clipboard' and (not data['standaloneNoteDirty']) and data['clipboardText'] == 'standalone clipboard save' and data['latestHistoryItemText'] == 'standalone clipboard save'" 40

  post_command dispatch saveCurrentEditorAs
  wait_for_snapshot_condition "standalone-save-as-sheet" "data['standaloneNoteAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'manualNoteSaveDestination'" 40
  post_command dispatch respondToAttachedSheet third
  wait_for_snapshot_condition "standalone-save-as-cancelled" "(not data['standaloneNoteAttachedSheetVisible']) and data['standaloneNoteVisible']" 40

  local standalone_file_path="$TMP_DIR/standalone-close-save.txt"
  printf "%s" "standalone clipboard save updated" > "$standalone_text_file"
  set_editor_text "$standalone_text_file"
  wait_for_snapshot_condition "standalone-close-redirty" "data['standaloneNoteDirty'] and data['standaloneNoteDraftText'] == 'standalone clipboard save updated'" 40
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "standalone-close-sheet" "data['standaloneNoteAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'closeUnsavedManualNote'" 40
  post_command dispatch respondToAttachedSheet "file:$standalone_file_path"
  wait_for_snapshot_condition "standalone-close-saved-file" "(not data['standaloneNoteVisible'])" 40
  assert_file_contains "$standalone_file_path" "standalone clipboard save updated"

  printf "%s" "discard me" > "$standalone_text_file"
  launch_clean_app
  reset_validation_state
  post_command open-new-note
  wait_for_snapshot_condition "standalone-discard-open" "data['standaloneNoteVisible']" 40
  set_editor_text "$standalone_text_file"
  wait_for_snapshot_condition "standalone-discard-dirty" "data['standaloneNoteDirty'] and data['standaloneNoteDraftText'] == 'discard me'" 40
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "standalone-discard-sheet" "data['standaloneNoteAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'closeUnsavedManualNote'" 40
  post_command dispatch respondToAttachedSheet third
  wait_for_snapshot_condition "standalone-discard-closed" "(not data['standaloneNoteVisible']) and data['historyCount'] == 0 and data['latestHistoryItemText'] is None" 40
}

run_commit_checks() {
  echo "==> commit current editor to front app #101 #144"
  local standalone_text_file="$TMP_DIR/standalone-commit.txt"
  launch_clean_app
  reset_validation_state
  prepare_textedit_document "BASE"
  post_command open-new-note
  wait_for_snapshot_condition "standalone-paste-open" "data['standaloneNoteVisible']" 40
  printf "%s" "PASTE_FROM_EDITOR" > "$standalone_text_file"
  set_editor_text "$standalone_text_file"
  wait_for_snapshot_condition "standalone-paste-dirty" "data['standaloneNoteDraftText'] == 'PASTE_FROM_EDITOR'" 40
  post_command dispatch commitCurrentEditor
  sleep 0.8
  local textedit_result
  textedit_result="$(textedit_contents)"
  [[ "$textedit_result" == "BASEPASTE_FROM_EDITOR" ]] || {
    echo "Unexpected TextEdit contents after editor commit: $textedit_result" >&2
    exit 1
  }
}

run_file_checks() {
  echo "==> file-backed save/close/external-change flows #155 #156 #159 #160 #163 #164 #165"
  local file_path="$TMP_DIR/file-backed.md"
  local modified_text_file="$TMP_DIR/file-backed-modified.txt"
  printf "%s" "# original" > "$file_path"
  printf "%s" "updated body" > "$modified_text_file"

  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "file-open-for-save-as" "data['fileEditorVisible'] and data['noteEditorRepresentedPath'] == '$file_path'" 40
  set_editor_text "$modified_text_file"
  wait_for_snapshot_condition "file-open-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'updated body'" 40
  post_command dispatch saveCurrentEditorAs
  wait_for_snapshot_condition "file-save-as-sheet" "data['noteEditorAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'fileSaveDestination'" 40
  local save_as_path="$TMP_DIR/file-save-as.md"
  post_command dispatch respondToAttachedSheet "file:$save_as_path"
  wait_for_snapshot_condition "file-save-as-done" "data['noteEditorRepresentedPath'] == '$save_as_path' and data['noteEditorSaveDestination'] == 'file'" 40
  assert_file_contains "$save_as_path" "updated body"

  printf "%s" "clipboard close contents" > "$modified_text_file"
  set_editor_text "$modified_text_file"
  wait_for_snapshot_condition "file-close-clipboard-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'clipboard close contents'" 40
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "file-close-clipboard-sheet" "data['noteEditorAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'closeUnsavedEditor'" 40
  post_command dispatch respondToAttachedSheet first
  wait_for_snapshot_condition "file-close-clipboard-done" "(not data['noteEditorVisible']) and data['clipboardText'] == 'clipboard close contents' and data['latestHistoryItemText'] == 'clipboard close contents'" 40

  printf "%s" "# original" > "$file_path"
  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "file-close-file-open" "data['fileEditorVisible'] and data['noteEditorRepresentedPath'] == '$file_path'" 40
  printf "%s" "saved on close" > "$modified_text_file"
  set_editor_text "$modified_text_file"
  wait_for_snapshot_condition "file-close-file-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'saved on close'" 40
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "file-close-file-sheet" "data['noteEditorAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'closeUnsavedEditor'" 40
  local close_file_path="$TMP_DIR/file-close-save.md"
  post_command dispatch respondToAttachedSheet "file:$close_file_path"
  wait_for_snapshot_condition "file-close-file-done" "(not data['noteEditorVisible'])" 40
  assert_file_contains "$close_file_path" "saved on close"

  printf "%s" "# original" > "$file_path"
  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "external-open" "data['fileEditorVisible'] and data['noteEditorDraftText'] == '# original'" 40
  printf "%s" "local draft" > "$modified_text_file"
  set_editor_text "$modified_text_file"
  wait_for_snapshot_condition "external-local-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'local draft'" 40
  printf "%s" "disk replacement" > "$file_path"
  wait_for_snapshot_condition "external-sheet" "data['noteEditorAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'externalFileChange'" 60
  post_command dispatch respondToAttachedSheet second
  wait_for_snapshot_condition "external-save-clipboard" "(not data['noteEditorAttachedSheetVisible']) and data['clipboardText'] == 'local draft' and data['noteEditorDraftText'] == 'disk replacement'" 40

  printf "%s" "# original" > "$file_path"
  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "external-file-save-open" "data['fileEditorVisible'] and data['noteEditorDraftText'] == '# original'" 40
  printf "%s" "draft to file" > "$modified_text_file"
  set_editor_text "$modified_text_file"
  wait_for_snapshot_condition "external-file-save-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'draft to file'" 40
  printf "%s" "disk overwrite" > "$file_path"
  wait_for_snapshot_condition "external-file-save-sheet" "data['noteEditorAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'externalFileChange'" 60
  local external_save_path="$TMP_DIR/external-save.md"
  post_command dispatch respondToAttachedSheet "file:$external_save_path"
  wait_for_snapshot_condition "external-file-save-done" "(not data['noteEditorAttachedSheetVisible']) and data['noteEditorDraftText'] == 'disk overwrite'" 40
  assert_file_contains "$external_save_path" "draft to file"

  printf "%s" "# original" > "$file_path"
  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "external-cancel-open" "data['fileEditorVisible'] and data['noteEditorDraftText'] == '# original'" 40
  printf "%s" "draft kept" > "$modified_text_file"
  set_editor_text "$modified_text_file"
  wait_for_snapshot_condition "external-cancel-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'draft kept'" 40
  printf "%s" "disk elsewhere" > "$file_path"
  wait_for_snapshot_condition "external-cancel-sheet" "data['noteEditorAttachedSheetVisible'] and data['validationAttachedSheetContext'] == 'externalFileChange'" 60
  post_command dispatch respondToAttachedSheet fourth
  wait_for_snapshot_condition "external-cancel-done" "(not data['noteEditorAttachedSheetVisible']) and data['noteEditorDraftText'] == 'draft kept'" 40
}

run_shortcut_checks() {
  echo "==> shortcut rebinding #188 and global copy setting visibility #189"
  launch_clean_app
  reset_validation_state
  post_command open-new-note
  wait_for_snapshot_condition "shortcut-standalone-open" "data['standaloneNoteVisible'] and (not data['standaloneNotePreviewVisible'])" 40
  post_command dispatch setToggleMarkdownPreviewShortcut "cmd+shift+8"
  wait_for_snapshot_condition "shortcut-preview-display" "data['toggleMarkdownPreviewShortcutDisplay'] == '⌘⇧8'" 20
  send_key_code 28 "command down, shift down"
  wait_for_snapshot_condition "shortcut-preview-opened" "data['standaloneNotePreviewVisible']" 40
  post_command dispatch setGlobalCopyJoinedEnabled false
  post_command dispatch setGlobalCopyNormalizedEnabled false
  wait_for_snapshot_condition "shortcut-global-copy-flags-off" "(not data['globalCopyJoinedEnabled']) and (not data['globalCopyNormalizedEnabled'])" 20
  post_command dispatch setGlobalCopyJoinedEnabled true
  post_command dispatch setGlobalCopyNormalizedEnabled true
  wait_for_snapshot_condition "shortcut-global-copy-flags-on" "data['globalCopyJoinedEnabled'] and data['globalCopyNormalizedEnabled']" 20
  capture_clipboardhistory_windows "shortcut-global-copy-flags-on"
}

main() {
  ensure_paths

  case "$SECTION" in
    preview)
      run_preview_checks
      ;;
    standalone)
      run_standalone_note_checks
      ;;
    commit)
      run_commit_checks
      ;;
    file)
      run_file_checks
      ;;
    shortcuts)
      run_shortcut_checks
      ;;
    all)
      run_preview_checks
      run_standalone_note_checks
      run_commit_checks
      run_file_checks
      run_shortcut_checks
      ;;
    *)
      echo "Unknown VALIDATION_SECTION: $SECTION" >&2
      exit 2
      ;;
  esac

  echo "PASS editor_preview_hotkeys_smoke"
  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "Artifacts kept in $TMP_DIR"
  fi
}

main "$@"
