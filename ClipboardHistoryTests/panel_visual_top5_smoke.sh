#!/bin/zsh
set -euo pipefail
setopt typesetsilent

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${CLIPBOARD_HISTORY_APP_BUNDLE:-/Applications/ClipboardHistory.app}"
APP_BIN="${CLIPBOARD_HISTORY_APP_BIN:-$APP_BUNDLE/Contents/MacOS/ClipboardHistory}"
COMMAND_HELPER="$ROOT_DIR/ClipboardHistoryTests/app_validation_command.swift"
WINDOW_PROBE="$ROOT_DIR/ClipboardHistoryTests/window_probe.swift"
STRESS_MARKDOWN="$ROOT_DIR/docs/markdown-preview-stress-test.md"
TMP_DIR_RAW="${VALIDATION_PANEL_TMP_DIR:-$ROOT_DIR/.codex-tmp/panel-visual-top5}"
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
  pkill -f "$COMMAND_HELPER" >/dev/null 2>&1 || true
  printf "%s" "$ORIGINAL_CLIPBOARD" | pbcopy
  if [[ "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

ensure_paths() {
  [[ -x "$APP_BIN" ]] || {
    echo "ClipboardHistory binary not found: $APP_BIN" >&2
    exit 2
  }
  [[ -f "$COMMAND_HELPER" ]] || {
    echo "Validation command helper not found: $COMMAND_HELPER" >&2
    exit 2
  }
  [[ -f "$STRESS_MARKDOWN" ]] || {
    echo "Stress markdown not found: $STRESS_MARKDOWN" >&2
    exit 2
  }
  mkdir -p "$TMP_DIR"
}

wait_for_visible_window_count_ge() {
  local minimum="$1"
  local attempts="${2:-40}"
  wait_for_snapshot_condition \
    "visible-window-count-ge-${minimum}" \
    "((1 if data['panelVisible'] else 0) + (1 if data['standaloneNoteVisible'] else 0) + (1 if data['noteEditorVisible'] else 0) + (1 if data['settingsVisible'] else 0) + (1 if data['helpVisible'] else 0)) >= $minimum" \
    "$attempts"
}

wait_for_visible_window_count_eq() {
  local expected="$1"
  local attempts="${2:-40}"
  wait_for_snapshot_condition \
    "visible-window-count-eq-${expected}" \
    "((1 if data['panelVisible'] else 0) + (1 if data['standaloneNoteVisible'] else 0) + (1 if data['noteEditorVisible'] else 0) + (1 if data['settingsVisible'] else 0) + (1 if data['helpVisible'] else 0)) == $expected" \
    "$attempts"
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
      echo "ClipboardHistory launched but validation hooks never became ready" >&2
      exit 3
    fi
    sleep 0.1
  done
  echo "ClipboardHistory did not launch cleanly" >&2
  exit 3
}

send_command_shift_v() {
  osascript -e 'tell application "System Events" to keystroke "v" using {command down, shift down}'
}

send_plain_key() {
  local key="$1"
  osascript -e "tell application \"System Events\" to keystroke \"$key\""
}

activate_finder() {
  osascript -e 'tell application "Finder" to activate'
}

post_command() {
  swift "$COMMAND_HELPER" "$@"
}

reset_validation_state() {
  post_command dispatch resetValidationState
  wait_for_snapshot_condition "validation-reset" "(not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and (not data['settingsVisible']) and (not data['helpVisible']) and data['historyCount'] == 0 and data['pinnedCount'] == 0 and data['settingsLanguage'] == 'en' and data['interfaceThemePreset'] == 'graphite' and (data['interfaceZoomScale'] > 0.999) and (data['interfaceZoomScale'] < 1.001)" 60
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
  echo "Timed out waiting for snapshot file: $snapshot_file" >&2
  return 1
}

wait_for_snapshot_condition() {
  local name="$1"
  local condition="$2"
  local attempts="${3:-40}"
  local snapshot_file
  snapshot_file="$(snapshot_path_for "$name")"
  local i
  for ((i = 1; i <= attempts; i++)); do
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
  echo "Timed out waiting for snapshot condition: $condition" >&2
  [[ -f "$snapshot_file" ]] && cat "$snapshot_file" >&2
  return 1
}

seed_history() {
  local texts=("validation-alpha" "validation-bravo" "validation-charlie")
  local expected_count=0
  for text in "${texts[@]}"; do
    expected_count=$((expected_count + 1))
    local expected_file="$TMP_DIR/seed-expected-${expected_count}.txt"
    printf "%s" "$text" > "$expected_file"
    post_command dispatch seedHistoryText "$text"
    local captured=0
    for _ in {1..80}; do
      local snapshot_name="seeded-history-${expected_count}"
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

prepare_seeded_panel() {
  launch_clean_app
  reset_validation_state
  seed_history
  post_command toggle-status-item
  wait_for_snapshot_condition \
    "seeded-panel-open" \
    "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest'] and (not data['panelPinnedAreaVisible']) and data['panelSelectionScope'] == 'history' and data['latestHistoryItemText'] == 'validation-charlie'" \
    60
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

capture_fullscreen() {
  local label="$1"
  screencapture -x "$TMP_DIR/${label}.png"
}

main() {
  ensure_paths
  launch_clean_app
  reset_validation_state
  echo "==> Additional #1 #2 startup status-item and no-main-window state"
  wait_for_snapshot_condition "startup-idle" "data['statusItemPresent'] and (not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and (not data['settingsVisible']) and (not data['helpVisible'])" 40
  capture_fullscreen "startup-idle"
  wait_for_visible_window_count_eq 0 30
  seed_history

  echo "==> Top5 #28 #38 #39 and additional #40 #41 via status-item path"
  post_command toggle-status-item
  wait_for_visible_window_count_ge 1 40
  wait_for_snapshot_condition \
    "panel-open" \
    "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest'] and (not data['panelPinnedAreaVisible']) and data['panelSelectionScope'] == 'history' and data['latestHistoryItemText'] == 'validation-charlie' and data['selectedFillDiffersFromCardFill']" \
    40
  capture_clipboardhistory_windows "panel-open"

  echo "==> Top5 #29 close via status-item path"
  post_command toggle-status-item
  wait_for_snapshot_condition "panel-closed" "(not data['panelVisible'])" 40
  capture_fullscreen "panel-closed"

  echo "==> Top5 #33 panel frontmost over file editor"
  post_command open-file "$STRESS_MARKDOWN"
  wait_for_snapshot_condition "file-editor-open" "data['fileEditorVisible'] and data['noteEditorVisible']" 40
  capture_clipboardhistory_windows "file-editor-open"
  send_command_shift_v
  wait_for_visible_window_count_ge 2 40
  wait_for_snapshot_condition "panel-over-file-editor" "data['panelVisible'] and data['panelFrontmost'] and data['fileEditorVisible']" 40
  capture_clipboardhistory_windows "panel-over-file-editor"

  echo "==> Additional #34 panel frontmost over standalone note"
  post_command open-new-note
  wait_for_snapshot_condition "standalone-note-open" "data['standaloneNoteVisible'] and data['fileEditorVisible']" 40
  capture_clipboardhistory_windows "standalone-note-open"
  send_command_shift_v
  wait_for_snapshot_condition "panel-over-standalone-note" "data['panelVisible'] and data['panelFrontmost'] and data['standaloneNoteVisible'] and data['fileEditorVisible']" 40
  capture_clipboardhistory_windows "panel-over-standalone-note"
  post_command toggle-status-item
  wait_for_snapshot_condition "panel-closed-over-standalone-note" "(not data['panelVisible']) and data['standaloneNoteVisible']" 40
  capture_clipboardhistory_windows "panel-closed-over-standalone-note"

  echo "==> Additional #30 panel auto-dismisses when another app becomes frontmost"
  post_command toggle-status-item
  wait_for_snapshot_condition "panel-before-finder" "data['panelVisible'] and data['panelFrontmost']" 40
  activate_finder
  wait_for_snapshot_condition "panel-after-finder" "(not data['panelVisible']) and data['standaloneNoteVisible'] and data['fileEditorVisible']" 40
  capture_clipboardhistory_windows "panel-after-finder"

  echo "==> Additional #31 settings coexist with panel"
  post_command toggle-status-item
  wait_for_snapshot_condition "panel-before-settings" "data['panelVisible'] and data['panelFrontmost']" 40
  post_command open-settings
  wait_for_snapshot_condition "panel-with-settings" "data['panelVisible'] and data['settingsVisible']" 40
  capture_clipboardhistory_windows "panel-with-settings"

  echo "==> Additional #32 help coexist with panel"
  launch_clean_app
  reset_validation_state
  seed_history
  post_command toggle-status-item
  wait_for_snapshot_condition "panel-before-help" "data['panelVisible'] and data['panelFrontmost']" 40
  post_command open-help
  wait_for_snapshot_condition "panel-with-help" "data['panelVisible'] and data['helpVisible']" 40
  capture_clipboardhistory_windows "panel-with-help"

  echo "==> Additional #42 #43 panel arrow navigation moves highlighted item"
  prepare_seeded_panel
  post_command move-panel-down
  wait_for_snapshot_condition "panel-after-down" "(not data['focusedMatchesLatest']) and data['focusedPanelItemID'] != data['latestHistoryItemID']" 40
  capture_clipboardhistory_windows "panel-after-down"
  post_command move-panel-up
  wait_for_snapshot_condition "panel-after-up" "data['focusedMatchesLatest'] and data['focusedPanelItemID'] == data['latestHistoryItemID']" 40
  capture_clipboardhistory_windows "panel-after-up"

  echo "==> Additional #44 Enter commits focused panel selection"
  post_command move-panel-down
  wait_for_snapshot_condition "panel-before-enter-commit" "(not data['focusedMatchesLatest']) and data['selectedMatchesLatest']" 40
  post_command commit-panel-selection
  wait_for_snapshot_condition "panel-after-enter-commit" "(not data['selectedMatchesLatest']) and data['highlightedPanelItemID'] == data['focusedPanelItemID']" 40
  capture_clipboardhistory_windows "panel-after-enter-commit"

  echo "==> Additional #78 keyboard E opens panel inline editor"
  send_plain_key "e"
  wait_for_snapshot_condition "panel-inline-editor-open" "data['panelInlineEditorItemID'] == data['highlightedPanelItemID'] and data['panelInlineEditorItemID'] is not None" 40
  capture_clipboardhistory_windows "panel-inline-editor-open"

  echo "==> Additional #145 standalone note preview can open"
  launch_clean_app
  post_command open-new-note
  wait_for_snapshot_condition "standalone-note-for-preview" "data['standaloneNoteVisible'] and (not data['standaloneNotePreviewVisible'])" 40
  post_command toggle-current-editor-preview
  wait_for_snapshot_condition "standalone-note-preview-open" "data['standaloneNoteVisible'] and data['standaloneNotePreviewVisible']" 40
  capture_clipboardhistory_windows "standalone-note-preview-open"

  echo "==> Additional #150 markdown file shows preview and text file does not"
  launch_clean_app
  post_command open-file "$STRESS_MARKDOWN"
  wait_for_snapshot_condition "markdown-file-preview-visible" "data['fileEditorVisible'] and data['noteEditorPreviewVisible']" 40
  capture_clipboardhistory_windows "markdown-file-preview-visible"

  local txt_path="$TMP_DIR/preview-check.txt"
  print -r -- "plain text preview off" > "$txt_path"
  launch_clean_app
  post_command open-file "$txt_path"
  wait_for_snapshot_condition "text-file-preview-hidden" "data['fileEditorVisible'] and (not data['noteEditorPreviewVisible'])" 40
  capture_clipboardhistory_windows "text-file-preview-hidden"

  echo "==> Additional #178 #179 settings/help windows can open"
  launch_clean_app
  post_command open-settings
  wait_for_snapshot_condition "settings-open" "data['settingsVisible']" 40
  capture_clipboardhistory_windows "settings-open"
  launch_clean_app
  post_command open-help
  wait_for_snapshot_condition "help-open" "data['helpVisible']" 40
  capture_clipboardhistory_windows "help-open"

  echo "==> Additional #4 app quit tears down menu extra owner"
  local pid_before_quit="$APP_PID"
  kill "$pid_before_quit" >/dev/null 2>&1 || true
  wait "$pid_before_quit" >/dev/null 2>&1 || true
  APP_PID=""
  for _ in {1..40}; do
    if ! pgrep -f "$APP_BIN" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if pgrep -f "$APP_BIN" >/dev/null 2>&1; then
    echo "ClipboardHistory process still running after quit" >&2
    exit 1
  fi
  echo "PASS panel_visual_top5_smoke"
  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "Artifacts kept in $TMP_DIR"
  fi
}

main "$@"
