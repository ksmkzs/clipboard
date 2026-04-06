#!/bin/zsh
set -euo pipefail
setopt typesetsilent

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${CLIPBOARD_HISTORY_APP_BUNDLE:-/Applications/ClipboardHistory.app}"
APP_BIN="${CLIPBOARD_HISTORY_APP_BIN:-$APP_BUNDLE/Contents/MacOS/ClipboardHistory}"
COMMAND_HELPER="$ROOT_DIR/ClipboardHistoryTests/app_validation_command.swift"
COPY_ROUTE_DRIVER="$ROOT_DIR/ClipboardHistoryTests/copy_route_driver.swift"
TMP_DIR_RAW="${VALIDATION_CLIPBOARD_TMP_DIR:-$ROOT_DIR/.codex-tmp/clipboard-capture-hotkeys}"
if [[ "$TMP_DIR_RAW" = /* ]]; then
  TMP_DIR="$TMP_DIR_RAW"
else
  TMP_DIR="$ROOT_DIR/$TMP_DIR_RAW"
fi
KEEP_ARTIFACTS="${KEEP_UI_SMOKE_ARTIFACTS:-0}"
SECTION="${VALIDATION_SECTION:-all}"
COPY_ROUTE_MODE="${VALIDATION_COPY_MODE:-all}"
APP_PID=""
ORIGINAL_CLIPBOARD="$(pbpaste || true)"

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
  pkill -x ClipboardHistory >/dev/null 2>&1 || true
  pkill -f "$COPY_ROUTE_DRIVER" >/dev/null 2>&1 || true
  printf "%s" "$ORIGINAL_CLIPBOARD" | pbcopy
  if [[ "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

ensure_paths() {
  [[ -x "$APP_BIN" ]] || { echo "Missing app binary: $APP_BIN" >&2; exit 2; }
  [[ -f "$COMMAND_HELPER" ]] || { echo "Missing helper: $COMMAND_HELPER" >&2; exit 2; }
  [[ -f "$COPY_ROUTE_DRIVER" ]] || { echo "Missing helper: $COPY_ROUTE_DRIVER" >&2; exit 2; }
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
  wait_for_snapshot_condition "validation-reset" "(not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and data['historyCount'] == 0 and data['statusItemPresent']"
}

activate_finder() {
  osascript -e 'tell application "Finder" to activate'
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

prepare_textedit_selection() {
  local text="$1"
  osascript \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "TextEdit" to if (count of documents) > 0 then close every document saving no' \
    -e "tell application \"TextEdit\" to make new document with properties {text:\"$text\"}" \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "System Events" to keystroke "a" using {command down}' \
    -e 'delay 0.25'
}

run_copy_route() {
  local route="$1"
  local text="$2"
  local expected_count="$3"
  if [[ "$route" == "keyboard" ]]; then
    prepare_textedit_selection "$text"
    send_key_code 8 "command down"
  else
    swift "$COPY_ROUTE_DRIVER" "$route" "$text" >/dev/null
  fi
  wait_for_snapshot_condition "copy-route-$route-$expected_count" "data['latestHistoryItemText'] == '$text' and data['clipboardText'] == '$text' and data['historyCount'] >= $expected_count" 60
}

run_startup_checks() {
  echo "==> startup state #1 #2"
  launch_clean_app
  reset_validation_state
  wait_for_snapshot_condition "startup-state" "data['statusItemPresent'] and data['historyCount'] == 0 and (not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and (not data['settingsVisible']) and (not data['helpVisible'])" 40
}

run_copy_route_checks() {
  echo "==> external copy routes #11 #12 #13"
  launch_clean_app
  reset_validation_state
  case "$COPY_ROUTE_MODE" in
    keyboard)
      run_copy_route keyboard "KEYBOARD_COPY_VALIDATION" 1
      ;;
    menu)
      run_copy_route menu "MENU_COPY_VALIDATION" 1
      ;;
    context)
      run_copy_route context "CONTEXT_COPY_VALIDATION" 1
      ;;
    all)
      run_copy_route keyboard "KEYBOARD_COPY_VALIDATION" 1
      run_copy_route menu "MENU_COPY_VALIDATION" 2
      run_copy_route context "CONTEXT_COPY_VALIDATION" 3
      ;;
    *)
      echo "Unknown VALIDATION_COPY_MODE: $COPY_ROUTE_MODE" >&2
      exit 2
      ;;
  esac
}

run_panel_hotkey_checks() {
  echo "==> panel hotkey rebinding #187"
  launch_clean_app
  reset_validation_state
  post_command dispatch setPanelShortcut "cmd+shift+9"
  wait_for_snapshot_condition "panel-shortcut-rebound" "data['panelShortcutDisplay'] == '⌘⇧9'" 20
  activate_finder
  send_key_code 25 "command down, shift down"
  wait_for_snapshot_condition "panel-shortcut-opened" "data['panelVisible'] and data['panelFrontmost']" 40
  send_key_code 25 "command down, shift down"
  wait_for_snapshot_condition "panel-shortcut-closed" "(not data['panelVisible'])" 40
}

run_global_special_copy_checks() {
  echo "==> global special copy toggle #189 #194 #197 #198"
  launch_clean_app
  reset_validation_state
  local multiline=$'line one\n line two \nline three  '
  printf "%s" "$multiline" | pbcopy
  post_command dispatch syncClipboardCapture
  wait_for_snapshot_condition "global-copy-seeded" "data['clipboardText'] == 'line one\\n line two \\nline three  '" 20

  post_command dispatch setGlobalCopyJoinedEnabled false
  wait_for_snapshot_condition "global-copy-joined-disabled" "(not data['globalCopyJoinedEnabled'])" 20
  activate_finder
  send_keystroke "c" "command down, option down"
  sleep 0.4
  wait_for_snapshot_condition "global-copy-joined-still-unchanged" "data['clipboardText'] == 'line one\\n line two \\nline three  ' and data['latestHistoryItemText'] == 'line one\\n line two \\nline three  '" 20

  post_command dispatch setGlobalCopyJoinedEnabled true
  wait_for_snapshot_condition "global-copy-joined-enabled" "data['globalCopyJoinedEnabled']" 20
  activate_finder
  send_keystroke "c" "command down, option down"
  wait_for_snapshot_condition "global-copy-joined-ran" "data['clipboardText'] == 'line oneline twoline three' and data['latestHistoryItemText'] == 'line oneline twoline three'" 40

  printf "%s" "$multiline" | pbcopy
  post_command dispatch syncClipboardCapture
  wait_for_snapshot_condition "global-copy-normalized-seeded" "data['clipboardText'] == 'line one\\n line two \\nline three  '" 20
  post_command dispatch setGlobalCopyNormalizedEnabled true
  wait_for_snapshot_condition "global-copy-normalized-enabled" "data['globalCopyNormalizedEnabled']" 20
  activate_finder
  send_keystroke "c" "command down, shift down"
  wait_for_snapshot_condition "global-copy-normalized-ran" "data['clipboardText'] == 'line one\\nline two\\nline three' and data['latestHistoryItemText'] == 'line one\\nline two\\nline three'" 40
}

run_quit_check() {
  echo "==> app quit #4"
  launch_clean_app
  reset_validation_state
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
}

main() {
  ensure_paths

  case "$SECTION" in
    startup)
      run_startup_checks
      ;;
    copy-routes)
      run_copy_route_checks
      ;;
    panel-hotkey)
      run_panel_hotkey_checks
      ;;
    global-special-copy)
      run_global_special_copy_checks
      ;;
    quit)
      run_quit_check
      ;;
    all)
      run_startup_checks
      run_copy_route_checks
      run_panel_hotkey_checks
      run_global_special_copy_checks
      run_quit_check
      ;;
    *)
      echo "Unknown VALIDATION_SECTION: $SECTION" >&2
      exit 2
      ;;
  esac

  echo "PASS clipboard_capture_hotkeys_smoke"
  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "Artifacts kept in $TMP_DIR"
  fi
}

main "$@"
