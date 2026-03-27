#!/bin/zsh
set -euo pipefail

iterations="${1:-3}"
delay_after_copy="${DELAY_AFTER_COPY:-0.35}"
delay_after_open="${DELAY_AFTER_OPEN:-0.40}"
delay_after_enter="${DELAY_AFTER_ENTER:-0.70}"

if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
  echo "iterations must be a positive integer" >&2
  exit 2
fi

app_pid="$(pgrep -f 'ClipboardHistory.app/Contents/MacOS/ClipboardHistory' | tail -n 1 || true)"
if [[ -z "$app_pid" ]]; then
  echo "ClipboardHistory app is not running" >&2
  exit 3
fi

original_clipboard="$(pbpaste || true)"
cleanup() {
  printf "%s" "$original_clipboard" | pbcopy
}
trap cleanup EXIT

run_case() {
  local token="$1"
  local base_text="BASE"
  local result

  printf "%s" "$token" | pbcopy
  sleep "$delay_after_copy"

  osascript \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "TextEdit" to if not (exists document 1) then make new document' \
    -e "tell application \"TextEdit\" to set text of document 1 to \"$base_text\"" \
    -e 'delay 0.15' \
    -e 'tell application "System Events" to keystroke "v" using {command down, shift down}' \
    -e "delay $delay_after_open" \
    -e 'tell application "System Events" to key code 36' \
    -e "delay $delay_after_enter" \
    -e 'tell application "TextEdit" to get text of document 1' > /tmp/clipboard_enter_result.txt

  result="$(cat /tmp/clipboard_enter_result.txt)"
  if [[ "$result" != "${base_text}${token}" ]]; then
    echo "FAIL expected='${base_text}${token}' actual='${result}'" >&2
    return 1
  fi
}

for i in $(seq 1 "$iterations"); do
  token="AUTOTEST_ENTER_${i}_$RANDOM"
  echo "run $i: $token"
  run_case "$token"
done

echo "PASS enter_paste_smoke x${iterations}"
