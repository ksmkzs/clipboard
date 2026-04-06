#!/bin/zsh
set -euo pipefail
setopt typesetsilent

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${CLIPBOARD_HISTORY_APP_BUNDLE:-/Applications/ClipboardHistory.app}"
APP_BIN="${CLIPBOARD_HISTORY_APP_BIN:-$APP_BUNDLE/Contents/MacOS/ClipboardHistory}"
COMMAND_HELPER="$ROOT_DIR/ClipboardHistoryTests/app_validation_command.swift"
WINDOW_PROBE="$ROOT_DIR/ClipboardHistoryTests/window_probe.swift"
TMP_DIR_RAW="${VALIDATION_EDITOR_TMP_DIR:-$ROOT_DIR/.codex-tmp/editor-file-settings}"
if [[ "$TMP_DIR_RAW" = /* ]]; then
  TMP_DIR="$TMP_DIR_RAW"
else
  TMP_DIR="$ROOT_DIR/$TMP_DIR_RAW"
fi
KEEP_ARTIFACTS="${KEEP_UI_SMOKE_ARTIFACTS:-0}"
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
  mkdir -p "$TMP_DIR"
}

post_command() {
  swift "$COMMAND_HELPER" "$@"
}

reset_validation_state() {
  post_command dispatch resetValidationState
  wait_for_snapshot_condition "validation-reset" "(not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and (not data['settingsVisible']) and (not data['helpVisible']) and data['historyCount'] == 0 and data['pinnedCount'] == 0 and data['settingsLanguage'] == 'en' and data['interfaceThemePreset'] == 'graphite' and (data['interfaceZoomScale'] > 0.999) and (data['interfaceZoomScale'] < 1.001)" 60
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

main() {
  ensure_paths

  echo "==> standalone note close/save flow"
  local standalone_text_file="$TMP_DIR/standalone-note.txt"
  local standalone_text=$'first draft line\nsecond line'
  printf "%s" "$standalone_text" > "$standalone_text_file"

  launch_clean_app
  reset_validation_state
  post_command open-new-note
  wait_for_snapshot_condition "standalone-open" "data['standaloneNoteVisible'] and data['standaloneNoteDraftText'] == ''"
  post_command dispatch setCurrentEditorText "$standalone_text_file"
  wait_for_snapshot_condition "standalone-dirty" "data['standaloneNoteVisible'] and data['standaloneNoteDirty'] and data['standaloneNoteDraftText'] == 'first draft line\\nsecond line'"
  capture_clipboardhistory_windows "standalone-dirty"
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "standalone-close-sheet" "data['standaloneNoteAttachedSheetVisible']" 40
  capture_clipboardhistory_windows "standalone-close-sheet"
  post_command dispatch respondToAttachedSheet fourth
  wait_for_snapshot_condition "standalone-close-cancel" "data['standaloneNoteVisible'] and (not data['standaloneNoteAttachedSheetVisible'])"
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "standalone-close-sheet-save" "data['standaloneNoteAttachedSheetVisible']" 40
  post_command dispatch respondToAttachedSheet first
  wait_for_snapshot_condition "standalone-saved-to-clipboard" "(not data['standaloneNoteVisible']) and data['clipboardText'] == 'first draft line\\nsecond line' and data['latestHistoryItemText'] == 'first draft line\\nsecond line'" 40

  echo "==> standalone note save-to-file conversion"
  local standalone_file_path="$TMP_DIR/standalone-converted.txt"
  local standalone_file_text="converted manual note"
  printf "%s" "$standalone_file_text" > "$standalone_text_file"
  launch_clean_app
  reset_validation_state
  post_command open-new-note
  wait_for_snapshot_condition "standalone-open-for-file" "data['standaloneNoteVisible']"
  post_command dispatch setCurrentEditorText "$standalone_text_file"
  wait_for_snapshot_condition "standalone-dirty-for-file" "data['standaloneNoteDirty'] and data['standaloneNoteDraftText'] == 'converted manual note'"
  post_command dispatch saveCurrentEditorToFile "$standalone_file_path"
  wait_for_snapshot_condition "standalone-converted-to-file-editor" "data['fileEditorVisible'] and data['noteEditorRepresentedPath'] == '$standalone_file_path' and data['noteEditorDraftText'] == 'converted manual note'" 40
  assert_file_contains "$standalone_file_path" "$standalone_file_text"
  capture_clipboardhistory_windows "standalone-converted-to-file-editor"

  echo "==> existing file save / save-as-choice / close-discard"
  local file_path="$TMP_DIR/existing-file.md"
  local modified_text="modified file contents"
  local modified_text_file="$TMP_DIR/modified-file.txt"
  printf "%s" "$modified_text" > "$modified_text_file"
  printf "%s" "# sample" > "$file_path"

  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "file-open-clean" "data['fileEditorVisible'] and data['noteEditorDraftText'] == '# sample' and (not data['noteEditorAttachedSheetVisible'])"
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "file-close-clean" "(not data['noteEditorVisible'])" 40

  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "file-open-for-save" "data['fileEditorVisible'] and data['noteEditorRepresentedPath'] == '$file_path'"
  post_command dispatch setCurrentEditorText "$modified_text_file"
  wait_for_snapshot_condition "file-dirty" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'modified file contents'"
  post_command dispatch saveCurrentEditor
  wait_for_snapshot_condition "file-saved" "data['noteEditorSaveDestination'] == 'file' and (not data['noteEditorDirty']) and data['noteEditorDraftText'] == 'modified file contents'" 40
  assert_file_contains "$file_path" "$modified_text"
  capture_clipboardhistory_windows "file-saved"

  post_command dispatch saveCurrentEditorAs
  wait_for_snapshot_condition "file-save-as-sheet" "data['noteEditorAttachedSheetVisible']" 40
  capture_clipboardhistory_windows "file-save-as-sheet"
  post_command dispatch respondToAttachedSheet first
  wait_for_snapshot_condition "file-save-as-clipboard" "(not data['noteEditorAttachedSheetVisible']) and data['clipboardText'] == 'modified file contents' and data['noteEditorSaveDestination'] == 'clipboard'" 40

  printf "%s" "changed then discarded" > "$modified_text_file"
  post_command dispatch setCurrentEditorText "$modified_text_file"
  wait_for_snapshot_condition "file-dirty-before-discard" "data['noteEditorDirty'] and data['noteEditorDraftText'] == 'changed then discarded'"
  post_command dispatch closeCurrentEditor
  wait_for_snapshot_condition "file-close-sheet" "data['noteEditorAttachedSheetVisible']" 40
  post_command dispatch respondToAttachedSheet third
  wait_for_snapshot_condition "file-discard-closed" "(not data['noteEditorVisible'])" 40
  assert_file_contains "$file_path" "$modified_text"

  echo "==> external file change prompt"
  local external_text="external replacement"
  launch_clean_app
  reset_validation_state
  post_command open-file "$file_path"
  wait_for_snapshot_condition "file-open-for-external-change" "data['fileEditorVisible'] and data['noteEditorDraftText'] == 'modified file contents'"
  printf "%s" "$external_text" > "$file_path"
  wait_for_snapshot_condition "external-change-sheet" "data['noteEditorAttachedSheetVisible']" 50
  capture_clipboardhistory_windows "external-change-sheet"
  post_command dispatch respondToAttachedSheet first
  wait_for_snapshot_condition "external-change-synced" "(not data['noteEditorAttachedSheetVisible']) and data['noteEditorDraftText'] == 'external replacement' and data['noteEditorSaveDestination'] == 'file'" 40

  echo "==> settings zoom/theme/language"
  launch_clean_app
  reset_validation_state
  post_command open-settings
  wait_for_snapshot_condition "settings-open" "data['settingsVisible'] and data['settingsLanguage'] == 'en' and data['interfaceThemePreset'] == 'graphite'"
  post_command dispatch increaseZoom
  wait_for_snapshot_condition "settings-zoom-in" "data['interfaceZoomScale'] > 1.0" 40
  capture_clipboardhistory_windows "settings-zoom-in"
  post_command dispatch decreaseZoom
  wait_for_snapshot_condition "settings-zoom-out" "(data['interfaceZoomScale'] > 0.999) and (data['interfaceZoomScale'] < 1.001)" 40
  post_command dispatch setThemePreset terminal
  wait_for_snapshot_condition "settings-theme-terminal" "data['interfaceThemePreset'] == 'terminal'" 40
  capture_clipboardhistory_windows "settings-theme-terminal"
  post_command dispatch setSettingsLanguage ja
  wait_for_snapshot_condition "settings-language-ja" "data['settingsLanguage'] == 'ja'" 40
  capture_clipboardhistory_windows "settings-language-ja"
  post_command dispatch inspectCodexIntegration
  wait_for_snapshot_condition "settings-codex-inspect" "data['settingsVisible'] and data['codexIntegrationInspectable'] in [True, False]" 10

  echo "PASS editor_file_settings_smoke"
  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "Artifacts kept in $TMP_DIR"
  fi
}

main "$@"
