#!/bin/zsh
set -euo pipefail
setopt typesetsilent

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${CLIPBOARD_HISTORY_APP_BUNDLE:-/Applications/ClipboardHistory.app}"
APP_BIN="${CLIPBOARD_HISTORY_APP_BIN:-$APP_BUNDLE/Contents/MacOS/ClipboardHistory}"
COMMAND_HELPER="$ROOT_DIR/ClipboardHistoryTests/app_validation_command.swift"
WINDOW_PROBE="$ROOT_DIR/ClipboardHistoryTests/window_probe.swift"
TMP_DIR_RAW="${VALIDATION_PANEL_ACTIONS_TMP_DIR:-$ROOT_DIR/.codex-tmp/panel-item-actions}"
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
  pkill -f "$COMMAND_HELPER" >/dev/null 2>&1 || true
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

relaunch_and_reset() {
  launch_clean_app
  reset_validation_state
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
  for dispatch_attempt in {1..8}; do
    post_command snapshot "$snapshot_file"
    for _ in {1..60}; do
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

seed_history() {
  local texts=("$@")
  local expected_count=0
  for text in "${texts[@]}"; do
    expected_count=$((expected_count + 1))
    local expected_file="$TMP_DIR/seed-expected-${expected_count}.txt"
    printf "%s" "$text" > "$expected_file"
    post_command dispatch seedHistoryText "$text"
    local captured=0
    for _ in {1..80}; do
      local snapshot_name="seed-${expected_count}"
      capture_snapshot "$snapshot_name" || return 1
      local snapshot_file
      snapshot_file="$(snapshot_path_for "$snapshot_name")"
      if python3 - "$snapshot_file" "$expected_file" "$expected_count" <<'PY'
import json, sys
from pathlib import Path
snapshot_path, expected_path, minimum_count = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = json.load(open(snapshot_path))
expected = Path(expected_path).read_text()
if data.get("latestHistoryItemText") == expected and int(data.get("historyCount", 0)) >= minimum_count:
    raise SystemExit(0)
raise SystemExit(1)
PY
      then
        captured=1
        break
      fi
      sleep 0.15
    done
    if [[ "$captured" -ne 1 ]]; then
      echo "Failed to capture seeded text: $text" >&2
      return 1
    fi
    sleep 0.25
  done
}

seed_default_history() {
  seed_history "validation-alpha" "validation-bravo" "validation-charlie"
}

seed_multiline_history() {
  seed_history $'line-one\n line-two \nline-three  '
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

run_selection_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "panel-open-default" "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest'] and data['historyCount'] >= 3"
  capture_clipboardhistory_windows "panel-open-default"

  echo "==> #45 commit focused row body"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "panel-focused-second" "data['panelVisible'] and data['panelFrontmost'] and data['focusedPanelItemText'] == 'validation-bravo' and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch commitPanelSelection
  wait_for_snapshot_condition "panel-selected-second" "data['panelVisible'] and data['panelFrontmost'] and data['highlightedPanelItemText'] == 'validation-bravo' and data['focusedPanelItemText'] == 'validation-bravo'"
  capture_clipboardhistory_windows "panel-selected-second"
}

run_pin_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "pin-open" "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest']"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "pin-focused-bravo" "data['panelVisible'] and data['panelFrontmost'] and data['focusedPanelItemText'] == 'validation-bravo' and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch togglePinFocusedPanelItem
  wait_for_snapshot_condition "pin-focused-result" "data['panelVisible'] and data['panelFrontmost'] and data['pinnedCount'] == 1 and data['highlightedPanelItemText'] == 'validation-charlie'"
  capture_clipboardhistory_windows "pin-focused-result"

  echo "==> #53/#54 keyboard pin toggle"
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "keyboard-pin-open" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] >= 3"
  post_command dispatch movePanelSelectionDown
  post_command dispatch commitPanelSelection
  wait_for_snapshot_condition "keyboard-pin-selected" "data['panelVisible'] and data['panelFrontmost'] and data['highlightedPanelItemText'] == 'validation-bravo'"
  post_command dispatch togglePinSelectedPanelItem
  wait_for_snapshot_condition "keyboard-pin-done" "data['panelVisible'] and data['panelFrontmost'] and data['pinnedCount'] == 1"
  post_command dispatch togglePanelPinnedArea
  wait_for_snapshot_condition "keyboard-pin-sidebar-open" "data['panelVisible'] and data['panelFrontmost'] and data['panelPinnedAreaVisible'] and data['panelSelectionScope'] == 'pinned'"
  post_command dispatch commitPanelSelection
  post_command dispatch togglePinSelectedPanelItem
  wait_for_snapshot_condition "keyboard-unpin-done" "data['panelVisible'] and data['panelFrontmost'] and data['pinnedCount'] == 0"
  capture_clipboardhistory_windows "keyboard-unpin-done"
}

run_delete_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "delete-open" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] >= 3"
  post_command dispatch movePanelSelectionDown
  post_command dispatch commitPanelSelection
  wait_for_snapshot_condition "delete-selected-bravo" "data['panelVisible'] and data['panelFrontmost'] and data['highlightedPanelItemText'] == 'validation-bravo'"
  post_command dispatch deleteSelectedPanelItem
  wait_for_snapshot_condition "delete-selected-done" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] == 2 and data['latestHistoryItemText'] == 'validation-charlie'"

  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "delete-focused-open" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] >= 3"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "delete-focused-bravo" "data['panelVisible'] and data['panelFrontmost'] and data['focusedPanelItemText'] == 'validation-bravo' and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch deleteFocusedPanelItem
  wait_for_snapshot_condition "delete-focused-done" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] == 2 and data['highlightedPanelItemText'] == 'validation-charlie'"
  capture_clipboardhistory_windows "delete-focused-done"

  echo "==> #47 focused-row delete button path leaves selected item unchanged"
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "delete-button-open" "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest']"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "delete-button-focused-bravo" "data['focusedPanelItemText'] == 'validation-bravo' and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch deleteFocusedPanelItem
  wait_for_snapshot_condition "delete-button-done" "data['historyCount'] == 2 and data['highlightedPanelItemText'] == 'validation-charlie' and data['latestHistoryItemText'] == 'validation-charlie'"
  capture_clipboardhistory_windows "delete-button-done"
}

run_focus_edit_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "focus-edit-open" "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest']"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "focus-edit-bravo" "data['focusedPanelItemText'] == 'validation-bravo' and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch openFocusedPanelEditor
  wait_for_snapshot_condition "focus-edit-opened" "data['panelInlineEditorItemID'] == data['focusedPanelItemID'] and data['focusedPanelItemText'] == 'validation-bravo' and data['highlightedPanelItemText'] == 'validation-charlie'"
  capture_clipboardhistory_windows "focus-edit-opened"
}

run_horizontal_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "horizontal-closed-open" "data['panelVisible'] and data['panelFrontmost'] and data['panelSelectionScope'] == 'history'"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "horizontal-closed-bravo" "data['focusedPanelItemText'] == 'validation-bravo' and data['panelSelectionScope'] == 'history'"
  post_command dispatch movePanelSelectionRight
  wait_for_snapshot_condition "horizontal-closed-right" "data['focusedPanelItemText'] == 'validation-bravo' and data['panelSelectionScope'] == 'history'"
  post_command dispatch movePanelSelectionLeft
  wait_for_snapshot_condition "horizontal-closed-left" "data['focusedPanelItemText'] == 'validation-bravo' and data['panelSelectionScope'] == 'history'"
  capture_clipboardhistory_windows "horizontal-closed-left"

  echo "==> #52 left/right move between history and pinned scopes when pinned area is open"
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "horizontal-open" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] >= 3"
  post_command dispatch togglePinSelectedPanelItem
  wait_for_snapshot_condition "horizontal-pin-selected" "data['pinnedCount'] == 1 and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch togglePanelPinnedArea
  wait_for_snapshot_condition "horizontal-pins-visible" "data['panelPinnedAreaVisible'] and data['panelSelectionScope'] == 'pinned'"
  post_command dispatch movePanelSelectionLeft
  wait_for_snapshot_condition "horizontal-left-history" "data['panelPinnedAreaVisible'] and data['panelSelectionScope'] == 'history'"
  post_command dispatch movePanelSelectionRight
  wait_for_snapshot_condition "horizontal-right-pinned" "data['panelPinnedAreaVisible'] and data['panelSelectionScope'] == 'pinned'"
  capture_clipboardhistory_windows "horizontal-right-pinned"
}

run_copy_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "copy-open" "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest'] and data['latestHistoryItemText'] == 'validation-charlie'"
  post_command dispatch copySelectedPanelItem
  wait_for_snapshot_condition "copy-done" "data['panelVisible'] and data['panelFrontmost'] and data['clipboardText'] == 'validation-charlie' and data['selectedMatchesLatest']"

  echo "==> #68 panel stays selected while new copy becomes #1"
  printf "%s" "validation-delta" | pbcopy
  post_command dispatch syncClipboardCapture
  wait_for_snapshot_condition "panel-new-copy" "data['panelVisible'] and data['panelFrontmost'] and data['latestHistoryItemText'] == 'validation-delta' and data['highlightedPanelItemText'] == 'validation-charlie' and (not data['selectedMatchesLatest'])" 40
  capture_clipboardhistory_windows "panel-new-copy"
}

run_inline_editor_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "editor-open-source" "data['panelVisible'] and data['panelFrontmost'] and data['historyCount'] >= 3"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "editor-focused-bravo" "data['panelVisible'] and data['panelFrontmost'] and data['focusedPanelItemText'] == 'validation-bravo'"
  post_command dispatch openFocusedPanelEditor
  wait_for_snapshot_condition "editor-inline-open" "data['panelVisible'] and data['panelFrontmost'] and data['panelInlineEditorItemID'] is not None"
  local editor_text="$TMP_DIR/panel-editor.txt"
  printf "%s" "validation-bravo-edited" > "$editor_text"
  post_command dispatch setPanelEditorText "$editor_text"
  wait_for_snapshot_condition "editor-inline-dirty" "data['panelVisible'] and data['panelFrontmost'] and data['panelInlineEditorDirty']"
  capture_clipboardhistory_windows "editor-inline-dirty"
  post_command dispatch cancelPanelEditor
  wait_for_snapshot_condition "editor-inline-canceled" "data['panelVisible'] and data['panelFrontmost'] and data['panelInlineEditorItemID'] is None and data['focusedPanelItemText'] == 'validation-bravo'"
  post_command dispatch openFocusedPanelEditor
  wait_for_snapshot_condition "editor-inline-reopen" "data['panelVisible'] and data['panelFrontmost'] and data['panelInlineEditorItemID'] is not None"
  post_command dispatch setPanelEditorText "$editor_text"
  wait_for_snapshot_condition "editor-inline-redirty" "data['panelVisible'] and data['panelFrontmost'] and data['panelInlineEditorDirty']"
  post_command dispatch commitPanelEditor
  wait_for_snapshot_condition "editor-inline-committed" "data['panelVisible'] and data['panelFrontmost'] and data['panelInlineEditorItemID'] is None and data['focusedPanelItemText'] == 'validation-bravo-edited'"
  capture_clipboardhistory_windows "editor-inline-committed"
}

run_switch_checks() {
  relaunch_and_reset
  seed_default_history
  post_command open-panel
  wait_for_snapshot_condition "editor-switch-open" "data['panelVisible'] and data['panelFrontmost'] and data['highlightedPanelItemText'] == 'validation-charlie'"
  post_command dispatch openSelectedPanelEditor
  wait_for_snapshot_condition "editor-switch-inline-open" "data['panelInlineEditorItemID'] == data['highlightedPanelItemID'] and data['highlightedPanelItemText'] == 'validation-charlie'"
  local switch_text="$TMP_DIR/panel-editor-switch.txt"
  printf "%s" "validation-charlie-switched" > "$switch_text"
  post_command dispatch setPanelEditorText "$switch_text"
  wait_for_snapshot_condition "editor-switch-dirty" "data['panelInlineEditorDirty'] and data['panelInlineEditorItemID'] is not None"
  post_command dispatch movePanelSelectionDown
  wait_for_snapshot_condition "editor-switch-focused-bravo" "data['focusedPanelItemText'] == 'validation-bravo'"
  post_command dispatch openFocusedPanelEditor
  wait_for_snapshot_condition "editor-switch-committed-previous" "data['panelInlineEditorItemID'] == data['focusedPanelItemID'] and data['latestHistoryItemText'] == 'validation-charlie-switched' and data['focusedPanelItemText'] == 'validation-bravo'"
  capture_clipboardhistory_windows "editor-switch-committed-previous"
}

run_transform_checks() {
  relaunch_and_reset
  seed_multiline_history
  post_command open-panel
  wait_for_snapshot_condition "normalize-open" "data['panelVisible'] and data['panelFrontmost'] and data['latestHistoryItemText'].splitlines() == ['line-one', ' line-two ', 'line-three  ']"
  post_command dispatch normalizeSelectedPanelItem
  wait_for_snapshot_condition "normalize-done" "data['panelVisible'] and data['panelFrontmost'] and data['latestHistoryItemText'] == 'line-one\\nline-two\\nline-three'"
  capture_clipboardhistory_windows "normalize-done"

  relaunch_and_reset
  seed_multiline_history
  post_command open-panel
  wait_for_snapshot_condition "join-open" "data['panelVisible'] and data['panelFrontmost'] and data['latestHistoryItemText'].splitlines() == ['line-one', ' line-two ', 'line-three  ']"
  post_command dispatch joinSelectedPanelItem
  wait_for_snapshot_condition "join-done" "data['panelVisible'] and data['panelFrontmost'] and data['latestHistoryItemText'] == 'line-oneline-twoline-three'"
  capture_clipboardhistory_windows "join-done"
}

main() {
  ensure_paths

  echo "==> panel selection and item action smoke"

  case "$SECTION" in
    selection)
      run_selection_checks
      ;;
    pinning)
      run_pin_checks
      ;;
    delete)
      run_delete_checks
      ;;
    focus-edit)
      run_focus_edit_checks
      ;;
    horizontal)
      run_horizontal_checks
      ;;
    copy)
      run_copy_checks
      ;;
    inline-editor)
      run_inline_editor_checks
      ;;
    switch)
      run_switch_checks
      ;;
    transforms)
      run_transform_checks
      ;;
    all)
      run_selection_checks
      run_pin_checks
      run_delete_checks
      run_focus_edit_checks
      run_horizontal_checks
      run_copy_checks
      run_inline_editor_checks
      run_switch_checks
      run_transform_checks
      ;;
    *)
      echo "Unknown VALIDATION_SECTION: $SECTION" >&2
      exit 2
      ;;
  esac

  echo "PASS panel_item_actions_smoke"
  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "Artifacts kept in $TMP_DIR"
  fi
}

main "$@"
