#!/bin/zsh
set -euo pipefail

delay_after_copy="${DELAY_AFTER_COPY:-0.35}"
delay_after_open="${DELAY_AFTER_OPEN:-0.35}"
delay_after_enter="${DELAY_AFTER_ENTER:-0.70}"
app_bin="${CLIPBOARD_HISTORY_APP_BIN:-$PWD/.codex-tmp/DerivedData/Build/Products/Debug/ClipboardHistory.app/Contents/MacOS/ClipboardHistory}"
started_pid=""

original_clipboard="$(pbpaste || true)"
cleanup() {
  if [[ -n "$started_pid" ]]; then
    kill "$started_pid" >/dev/null 2>&1 || true
    wait "$started_pid" >/dev/null 2>&1 || true
  fi
  printf "%s" "$original_clipboard" | pbcopy
}
trap cleanup EXIT

start_app_for_smoke() {
  pkill -f 'ClipboardHistory.app/Contents/MacOS/ClipboardHistory' >/dev/null 2>&1 || true
  if [[ ! -x "$app_bin" ]]; then
    echo "ClipboardHistory app binary not found: $app_bin" >&2
    exit 3
  fi
  "$app_bin" >/dev/null 2>&1 &
  started_pid=$!
  for _ in {1..20}; do
    if kill -0 "$started_pid" >/dev/null 2>&1; then
      sleep 1.2
      return
    fi
    sleep 0.1
  done
  echo "ClipboardHistory app did not stay running after launch" >&2
  exit 4
}

start_app_for_smoke

run_case() {
  local app_name="$1"
  local base_text="$2"
  local token="$3"

  printf "%s" "$token" | pbcopy
  sleep "$delay_after_copy"

  osascript \
    -e "tell application \"$app_name\" to activate" \
    -e "tell application \"$app_name\" to if not (exists document 1) then make new document" \
    -e "tell application \"$app_name\" to set text of document 1 to \"$base_text\"" \
    -e 'delay 0.15' \
    -e 'tell application "System Events" to keystroke "v" using {command down, shift down}' \
    -e "delay $delay_after_open" \
    -e 'tell application "System Events" to key code 36' \
    -e "delay $delay_after_enter" \
    -e "tell application \"$app_name\" to get text of document 1"
}

token1="APP_SWITCH_TOKEN_1_$RANDOM"
token2="APP_SWITCH_TOKEN_2_$RANDOM"

textedit_result="$(run_case "TextEdit" "TEXTEDIT" "$token1")"
scripteditor_result="$(run_case "Script Editor" "SCRIPT" "$token2")"
textedit_after="$(osascript -e 'tell application "TextEdit" to get text of document 1')"

[[ "$textedit_result" == "TEXTEDIT${token1}" ]] || {
  echo "FAIL textedit expected='TEXTEDIT${token1}' actual='${textedit_result}'" >&2
  exit 1
}

[[ "$scripteditor_result" == "SCRIPT${token2}" ]] || {
  echo "FAIL scripteditor expected='SCRIPT${token2}' actual='${scripteditor_result}'" >&2
  exit 1
}

[[ "$textedit_after" == "TEXTEDIT${token1}" ]] || {
  echo "FAIL stale-target textedit changed unexpectedly: '${textedit_after}'" >&2
  exit 1
}

echo "PASS enter_paste_target_switch_smoke"
