#!/bin/zsh
set -euo pipefail
setopt typesetsilent

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_bin="${CLIPBOARD_HISTORY_APP_BIN:-$PWD/.codex-tmp/DerivedData/Build/Products/Debug/ClipboardHistory.app/Contents/MacOS/ClipboardHistory}"
command_helper="$root_dir/ClipboardHistoryTests/app_validation_command.swift"
tmp_dir_raw="${VALIDATION_TARGET_SWITCH_TMP_DIR:-$root_dir/.codex-tmp/enter-paste-target-switch}"
if [[ "$tmp_dir_raw" = /* ]]; then
  tmp_dir="$tmp_dir_raw"
else
  tmp_dir="$root_dir/$tmp_dir_raw"
fi
keep_artifacts="${KEEP_UI_SMOKE_ARTIFACTS:-0}"
started_pid=""
original_clipboard="$(pbpaste || true)"

cleanup() {
  if [[ -n "$started_pid" ]]; then
    kill "$started_pid" >/dev/null 2>&1 || true
    wait "$started_pid" >/dev/null 2>&1 || true
  fi
  pkill -x ClipboardHistory >/dev/null 2>&1 || true
  printf "%s" "$original_clipboard" | pbcopy
  if [[ "$keep_artifacts" != "1" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

ensure_paths() {
  [[ -x "$app_bin" ]] || { echo "ClipboardHistory app binary not found: $app_bin" >&2; exit 3; }
  [[ -f "$command_helper" ]] || { echo "Validation helper not found: $command_helper" >&2; exit 3; }
  mkdir -p "$tmp_dir"
}

post_command() {
  swift "$command_helper" "$@"
}

snapshot_path_for() {
  echo "$tmp_dir/$1.json"
}

capture_snapshot() {
  local name="$1"
  local snapshot_file
  snapshot_file="$(snapshot_path_for "$name")"
  rm -f "$snapshot_file"
  for _ in {1..4}; do
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
  "$app_bin" --validation-hooks >/dev/null 2>&1 &
  for _ in {1..80}; do
    started_pid="$(pgrep -n -f "$app_bin" || true)"
    if [[ -n "$started_pid" ]] && kill -0 "$started_pid" >/dev/null 2>&1; then
      local readiness_file="$tmp_dir/launch-ready.json"
      for _ in {1..40}; do
        rm -f "$readiness_file"
        post_command snapshot "$readiness_file"
        for _ in {1..20}; do
          [[ -f "$readiness_file" ]] && return 0
          sleep 0.05
        done
        sleep 0.15
      done
      echo "Validation hooks not ready" >&2
      exit 4
    fi
    sleep 0.1
  done
  echo "ClipboardHistory app did not stay running after launch" >&2
  exit 4
}

reset_validation_state() {
  post_command dispatch resetValidationState
  wait_for_snapshot_condition "validation-reset" "(not data['panelVisible']) and (not data['standaloneNoteVisible']) and (not data['noteEditorVisible']) and data['historyCount'] == 0" 60
}

seed_history_text() {
  local text="$1"
  post_command dispatch seedHistoryText "$text"
  wait_for_snapshot_condition "seed-history" "data['historyCount'] >= 1 and data['latestHistoryItemText'] == '$text' and data['clipboardText'] == '$text'" 60
}

prepare_textedit_document() {
  local base_text="$1"
  osascript \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "TextEdit" to close every document saving no' \
    -e "tell application \"TextEdit\" to make new document with properties {text:\"$base_text\"}" \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "System Events" to key code 124 using {command down}' \
    -e 'delay 0.2'
}

prepare_script_editor_document() {
  local base_text="$1"
  osascript \
    -e 'tell application "Script Editor" to activate' \
    -e 'tell application "Script Editor" to close every document saving no' \
    -e 'tell application "Script Editor" to make new document' \
    -e "tell application \"Script Editor\" to set text of document 1 to \"$base_text\"" \
    -e 'tell application "Script Editor" to activate' \
    -e 'tell application "System Events" to key code 124 using {command down}' \
    -e 'delay 0.2'
}

textedit_contents() {
  osascript -e 'tell application "TextEdit" to get text of document 1'
}

script_editor_contents() {
  osascript -e 'tell application "Script Editor" to get text of document 1'
}

run_case() {
  local target="$1"
  local base_text="$2"
  local token="$3"

  if [[ "$target" == "TextEdit" ]]; then
    prepare_textedit_document "$base_text"
  else
    prepare_script_editor_document "$base_text"
  fi

  seed_history_text "$token"
  post_command toggle-status-item
  wait_for_snapshot_condition "panel-open-for-target-switch" "data['panelVisible'] and data['panelFrontmost'] and data['selectedMatchesLatest'] and data['latestHistoryItemText'] == '$token'" 60
  post_command dispatch pasteSelectedPanelItem

  local result=""
  for _ in {1..40}; do
    if [[ "$target" == "TextEdit" ]]; then
      result="$(textedit_contents)"
    else
      result="$(script_editor_contents)"
    fi
    if [[ "$result" == "${base_text}${token}" ]]; then
      printf "%s" "$result"
      return 0
    fi
    sleep 0.15
  done

  echo "FAIL ${target:l} expected='${base_text}${token}' actual='${result}'" >&2
  return 1
}

ensure_paths
launch_clean_app
reset_validation_state

token1="APP_SWITCH_TOKEN_1_$RANDOM"
token2="APP_SWITCH_TOKEN_2_$RANDOM"

textedit_result="$(run_case "TextEdit" "TEXTEDIT" "$token1")"
launch_clean_app
reset_validation_state
scripteditor_result="$(run_case "Script Editor" "SCRIPT" "$token2")"
textedit_after="$(textedit_contents)"

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
