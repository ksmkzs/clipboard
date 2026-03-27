#!/bin/zsh
set -euo pipefail

delay_after_copy="${DELAY_AFTER_COPY:-0.35}"
delay_after_open="${DELAY_AFTER_OPEN:-0.35}"
delay_after_enter="${DELAY_AFTER_ENTER:-0.70}"

original_clipboard="$(pbpaste || true)"
cleanup() {
  printf "%s" "$original_clipboard" | pbcopy
}
trap cleanup EXIT

pgrep -f 'ClipboardHistory.app/Contents/MacOS/ClipboardHistory' >/dev/null || {
  echo "ClipboardHistory app is not running" >&2
  exit 3
}

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
