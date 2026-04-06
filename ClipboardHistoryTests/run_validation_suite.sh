#!/bin/zsh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${CLIPBOARD_HISTORY_APP_BUNDLE:-/Applications/ClipboardHistory.app}"
APP_BIN="${CLIPBOARD_HISTORY_APP_BIN:-$APP_BUNDLE/Contents/MacOS/ClipboardHistory}"
WINDOW_PROBE="$ROOT_DIR/ClipboardHistoryTests/window_probe.swift"
VALIDATION_COMMAND="$ROOT_DIR/ClipboardHistoryTests/app_validation_command.swift"
PANEL_VISUAL_SMOKE="$ROOT_DIR/ClipboardHistoryTests/panel_visual_top5_smoke.sh"
PANEL_ITEM_ACTIONS_SMOKE="$ROOT_DIR/ClipboardHistoryTests/panel_item_actions_smoke.sh"
EDITOR_FILE_SETTINGS_SMOKE="$ROOT_DIR/ClipboardHistoryTests/editor_file_settings_smoke.sh"
CLIPBOARD_CAPTURE_HOTKEYS_SMOKE="$ROOT_DIR/ClipboardHistoryTests/clipboard_capture_hotkeys_smoke.sh"
EDITOR_PREVIEW_HOTKEYS_SMOKE="$ROOT_DIR/ClipboardHistoryTests/editor_preview_hotkeys_smoke.sh"
STRESS_MARKDOWN="$ROOT_DIR/docs/markdown-preview-stress-test.md"
RUN_ID="${VALIDATION_RUN_ID:-$$}"
SUITE_DIR="$ROOT_DIR/.codex-tmp/validation-suite-$RUN_ID"
TMP_DIR="$SUITE_DIR/artifacts"
DERIVED_DATA_PATH="${VALIDATION_DERIVED_DATA_PATH:-$SUITE_DIR/TestDerivedData}"
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
    rm -rf "$SUITE_DIR"
  fi
}
trap cleanup EXIT

ensure_paths() {
  [[ -x "$APP_BIN" ]] || {
    echo "ClipboardHistory binary not found: $APP_BIN" >&2
    exit 2
  }
  [[ -f "$WINDOW_PROBE" ]] || {
    echo "Window probe helper not found: $WINDOW_PROBE" >&2
    exit 2
  }
  [[ -f "$VALIDATION_COMMAND" ]] || {
    echo "Validation command helper not found: $VALIDATION_COMMAND" >&2
    exit 2
  }
  [[ -f "$PANEL_VISUAL_SMOKE" ]] || {
    echo "Panel visual smoke not found: $PANEL_VISUAL_SMOKE" >&2
    exit 2
  }
  [[ -f "$PANEL_ITEM_ACTIONS_SMOKE" ]] || {
    echo "Panel item actions smoke not found: $PANEL_ITEM_ACTIONS_SMOKE" >&2
    exit 2
  }
  [[ -f "$EDITOR_FILE_SETTINGS_SMOKE" ]] || {
    echo "Editor/file/settings smoke not found: $EDITOR_FILE_SETTINGS_SMOKE" >&2
    exit 2
  }
  [[ -f "$CLIPBOARD_CAPTURE_HOTKEYS_SMOKE" ]] || {
    echo "Clipboard capture/hotkeys smoke not found: $CLIPBOARD_CAPTURE_HOTKEYS_SMOKE" >&2
    exit 2
  }
  [[ -f "$EDITOR_PREVIEW_HOTKEYS_SMOKE" ]] || {
    echo "Editor/preview/hotkeys smoke not found: $EDITOR_PREVIEW_HOTKEYS_SMOKE" >&2
    exit 2
  }
  [[ -f "$STRESS_MARKDOWN" ]] || {
    echo "Stress markdown not found: $STRESS_MARKDOWN" >&2
    exit 2
  }
  mkdir -p "$TMP_DIR"
}

window_count() {
  swift "$WINDOW_PROBE" --owner ClipboardHistory --count | tr -d '[:space:]'
}

wait_for_count_eq() {
  local expected="$1"
  local attempts="${2:-40}"
  for _ in $(seq 1 "$attempts"); do
    local current
    current="$(window_count)"
    if [[ "$current" == "$expected" ]]; then
      return 0
    fi
    sleep 0.15
  done
  echo "Timed out waiting for ClipboardHistory window count == $expected (actual $(window_count))" >&2
  return 1
}

wait_for_count_ge() {
  local minimum="$1"
  local attempts="${2:-54}"
  for _ in $(seq 1 "$attempts"); do
    local current
    current="$(window_count)"
    if [[ "$current" -ge "$minimum" ]]; then
      return 0
    fi
    sleep 0.15
  done
  echo "Timed out waiting for ClipboardHistory window count >= $minimum (actual $(window_count))" >&2
  return 1
}

launch_clean_app() {
  pkill -x ClipboardHistory >/dev/null 2>&1 || true
  "$APP_BIN" --validation-hooks >/dev/null 2>&1 &
  for _ in {1..60}; do
    APP_PID="$(pgrep -n -f "$APP_BIN" || true)"
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
      local readiness_file="$TMP_DIR/launch-ready.json"
      for _ in {1..40}; do
        rm -f "$readiness_file"
        swift "$VALIDATION_COMMAND" snapshot "$readiness_file"
        for _ in {1..20}; do
          [[ -f "$readiness_file" ]] && return 0
          sleep 0.05
        done
        sleep 0.15
      done
      echo "Validation hooks not ready" >&2
      exit 3
      return 0
    fi
    sleep 0.1
  done
  echo "ClipboardHistory did not launch cleanly" >&2
  exit 3
}

post_validation_command() {
  swift "$VALIDATION_COMMAND" "$@"
}

capture_screen() {
  local name="$1"
  screencapture -x "$TMP_DIR/$name.png"
}

send_command_shift_v() {
  osascript -e 'tell application "System Events" to keystroke "v" using {command down, shift down}'
}

send_command_control_n() {
  osascript -e 'tell application "System Events" to keystroke "n" using {command down, control down}'
}

run_targeted_xctest() {
  echo "==> Running targeted XCTest"
  local attempt
  for attempt in 1 2; do
    if DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      xcodebuild \
        -project "$ROOT_DIR/ClipboardHistory.xcodeproj" \
        -scheme ClipboardHistory \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        test \
        -only-testing:ClipboardHistoryTests/AppDelegateTargetSelectionTests \
        -only-testing:ClipboardHistoryTests/ClipboardDataManagerBehaviorTests \
        -only-testing:ClipboardHistoryTests/ClipboardWorkflowRegressionTests \
        -only-testing:ClipboardHistoryTests/CodexIntegrationManagerTests \
        -only-testing:ClipboardHistoryTests/EditorNSTextViewKeyboardTests \
        -only-testing:ClipboardHistoryTests/PanelKeyboardRoutingTests; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "Targeted XCTest failed once; retrying once to absorb flake..." >&2
    fi
  done
  return 1
}

adopt_built_app_if_available() {
  local built_bundle="$DERIVED_DATA_PATH/Build/Products/Debug/ClipboardHistory.app"
  local built_bin="$built_bundle/Contents/MacOS/ClipboardHistory"
  if [[ -x "$built_bin" ]]; then
    APP_BUNDLE="$built_bundle"
    APP_BIN="$built_bin"
  fi
}

run_panel_toggle_smoke() {
  echo "==> Running panel toggle smoke"
  launch_clean_app
  wait_for_count_eq 0 30
  send_command_shift_v
  wait_for_count_ge 1 40
  capture_screen "panel-open"
  send_command_shift_v
  wait_for_count_eq 0 40
}

run_file_open_variants_smoke() {
  echo "==> Running file-open variant smoke"
  local txt_path="$TMP_DIR/variant-open.txt"
  local plain_path="$TMP_DIR/variant-open"
  print -r -- "plain text variant" > "$txt_path"
  print -r -- "plain text without extension" > "$plain_path"

  launch_clean_app
  post_validation_command open-file "$STRESS_MARKDOWN"
  wait_for_count_ge 1 54
  capture_screen "file-open-markdown"

  launch_clean_app
  post_validation_command open-file "$txt_path"
  wait_for_count_ge 1 54
  capture_screen "file-open-text"

  launch_clean_app
  post_validation_command open-file "$plain_path"
  wait_for_count_ge 1 54
  capture_screen "file-open-plain"
}

run_file_and_note_coexist_smoke() {
  echo "==> Running file + note coexistence smoke"
  launch_clean_app
  post_validation_command open-file "$STRESS_MARKDOWN"
  wait_for_count_ge 1 54
  capture_screen "file-editor-open"
  send_command_control_n
  wait_for_count_ge 2 54
  capture_screen "file-plus-note-open"
}

run_existing_smokes() {
  echo "==> Running existing enter/paste smoke"
  local attempt
  for attempt in 1 2; do
    if CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" zsh "$ROOT_DIR/ClipboardHistoryTests/enter_paste_smoke.sh" 2; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "enter/paste smoke failed once; retrying once to absorb focus timing..." >&2
    fi
  done
  return 1
}

run_existing_target_switch_smoke() {
  echo "==> Running target-switch smoke"
  CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" zsh "$ROOT_DIR/ClipboardHistoryTests/enter_paste_target_switch_smoke.sh"
}

run_panel_visual_top5_smoke() {
  echo "==> Running panel visual top5 smoke"
  local attempt
  for attempt in 1 2; do
    if CLIPBOARD_HISTORY_APP_BUNDLE="$APP_BUNDLE" \
      CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" \
      VALIDATION_PANEL_TMP_DIR="$TMP_DIR/panel-visual-top5" \
      KEEP_UI_SMOKE_ARTIFACTS="$KEEP_ARTIFACTS" \
      zsh "$PANEL_VISUAL_SMOKE"; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "panel visual smoke failed once; retrying once after a clean relaunch..." >&2
    fi
  done
  return 1
}

run_panel_item_actions_smoke() {
  echo "==> Running panel item actions smoke"
  local attempt
  for attempt in 1 2; do
    if CLIPBOARD_HISTORY_APP_BUNDLE="$APP_BUNDLE" \
      CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" \
      VALIDATION_PANEL_ACTIONS_TMP_DIR="$TMP_DIR/panel-item-actions" \
      KEEP_UI_SMOKE_ARTIFACTS="$KEEP_ARTIFACTS" \
      zsh "$PANEL_ITEM_ACTIONS_SMOKE"; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "panel item actions smoke failed once; retrying once after a clean relaunch..." >&2
    fi
  done
  return 1
}

run_editor_file_settings_smoke() {
  echo "==> Running editor/file/settings smoke"
  local attempt
  for attempt in 1 2; do
    if CLIPBOARD_HISTORY_APP_BUNDLE="$APP_BUNDLE" \
      CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" \
      VALIDATION_EDITOR_TMP_DIR="$TMP_DIR/editor-file-settings" \
      KEEP_UI_SMOKE_ARTIFACTS="$KEEP_ARTIFACTS" \
      zsh "$EDITOR_FILE_SETTINGS_SMOKE"; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "editor/file/settings smoke failed once; retrying once after a clean relaunch..." >&2
    fi
  done
  return 1
}

run_clipboard_capture_hotkeys_smoke() {
  echo "==> Running clipboard capture/hotkeys smoke"
  local attempt
  for attempt in 1 2; do
    if CLIPBOARD_HISTORY_APP_BUNDLE="$APP_BUNDLE" \
      CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" \
      VALIDATION_CLIPBOARD_TMP_DIR="$TMP_DIR/clipboard-capture-hotkeys" \
      KEEP_UI_SMOKE_ARTIFACTS="$KEEP_ARTIFACTS" \
      zsh "$CLIPBOARD_CAPTURE_HOTKEYS_SMOKE"; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "clipboard capture/hotkeys smoke failed once; retrying once after a clean relaunch..." >&2
    fi
  done
  return 1
}

run_editor_preview_hotkeys_smoke() {
  echo "==> Running editor/preview/hotkeys smoke"
  local attempt
  for attempt in 1 2; do
    if CLIPBOARD_HISTORY_APP_BUNDLE="$APP_BUNDLE" \
      CLIPBOARD_HISTORY_APP_BIN="$APP_BIN" \
      VALIDATION_EDITOR_PREVIEW_TMP_DIR="$TMP_DIR/editor-preview-hotkeys" \
      KEEP_UI_SMOKE_ARTIFACTS="$KEEP_ARTIFACTS" \
      zsh "$EDITOR_PREVIEW_HOTKEYS_SMOKE"; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "editor/preview/hotkeys smoke failed once; retrying once after a clean relaunch..." >&2
    fi
  done
  return 1
}

main() {
  ensure_paths
  local failures=0

  if ! run_targeted_xctest; then
    failures=$((failures + 1))
  fi
  adopt_built_app_if_available
  if ! run_panel_toggle_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_file_open_variants_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_file_and_note_coexist_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_existing_smokes; then
    failures=$((failures + 1))
  fi
  if ! run_existing_target_switch_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_panel_visual_top5_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_panel_item_actions_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_editor_file_settings_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_clipboard_capture_hotkeys_smoke; then
    failures=$((failures + 1))
  fi
  if ! run_editor_preview_hotkeys_smoke; then
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "FAIL run_validation_suite ($failures failing step(s))" >&2
    return 1
  fi
  echo "PASS run_validation_suite"
  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "Artifacts kept in $SUITE_DIR"
  fi
}

main "$@"
