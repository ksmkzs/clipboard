#!/bin/zsh
set -euo pipefail

iterations="${1:-3}"
delay_after_copy="${DELAY_AFTER_COPY:-0.35}"
delay_after_open="${DELAY_AFTER_OPEN:-0.40}"
delay_after_enter="${DELAY_AFTER_ENTER:-0.70}"
app_bin="${CLIPBOARD_HISTORY_APP_BIN:-$PWD/.codex-tmp/DerivedData/Build/Products/Debug/ClipboardHistory.app/Contents/MacOS/ClipboardHistory}"
started_pid=""

if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
  echo "iterations must be a positive integer" >&2
  exit 2
fi

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

original_clipboard="$(pbpaste || true)"
cleanup() {
  if [[ -n "$started_pid" ]]; then
    kill "$started_pid" >/dev/null 2>&1 || true
    wait "$started_pid" >/dev/null 2>&1 || true
  fi
  printf "%s" "$original_clipboard" | pbcopy
}
trap cleanup EXIT

start_app_for_smoke

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
