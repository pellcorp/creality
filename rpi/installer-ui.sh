#!/bin/bash

set -o pipefail

BASEDIR="$HOME"
INSTALLER="$BASEDIR/pellcorp/rpi/installer.sh"
LOG_DIR="$BASEDIR/printer_data/logs"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
UI_LOG="$LOG_DIR/installer-ui-$TIMESTAMP.log"
STATUS_FILE="/tmp/pellcorp-installer-status.$$"
READY_FILE="/tmp/pellcorp-installer-ui-ready.$$"
MODE_FILE="/tmp/pellcorp-installer-mode.$$"
PRINTER_FILE="/tmp/pellcorp-installer-printer.$$"
PROBE_FILE="/tmp/pellcorp-installer-probe.$$"
MOUNT_FILE="/tmp/pellcorp-installer-mount.$$"

valid_mode=false
for arg in "$@"; do
  if [ "$arg" = "--install" ] || [ "$arg" = "--reinstall" ]; then
    valid_mode=true
    break
  fi
done

if [ "$valid_mode" != "true" ]; then
  echo "FATAL: UI Installer supports --install or --reinstall only"
  exit 1
fi

mkdir -p "$LOG_DIR"
: > "$UI_LOG"

cleanup() {
  tput cnorm 2>/dev/null || true
  rm -f "$STATUS_FILE" "$READY_FILE" "$MODE_FILE" "$PRINTER_FILE" "$PROBE_FILE" "$MOUNT_FILE"
}
trap cleanup EXIT

draw_header() {
  local status="$1"
  local exit_code="$2"
  local rows
  local cols
  local output_rows
  local mode
  local printer
  local probe
  local mount

  rows=$(tput lines 2>/dev/null || echo 24)
  cols=$(tput cols 2>/dev/null || echo 80)
  output_rows=$((rows - 12))
  [ "$output_rows" -lt 5 ] && output_rows=5

  mode=$(cat "$MODE_FILE" 2>/dev/null)
  printer=$(cat "$PRINTER_FILE" 2>/dev/null)
  probe=$(cat "$PROBE_FILE" 2>/dev/null)
  mount=$(cat "$MOUNT_FILE" 2>/dev/null)

  tput cup 0 0 2>/dev/null || true
  tput ed 2>/dev/null || true
  printf "Simple AF Installer\n"
  printf "\n"
  printf " Status: %s\n" "$status"
  printf "   Mode: %s\n" "${mode:-unknown}"
  printf "Printer: %s\n" "${printer:-unknown}"
  printf "  Probe: %s\n" "${probe:-unknown}"
  printf "  Mount: %s\n" "${mount:-unknown}"
  printf "    Log: %s\n" "$UI_LOG"

  printf "\n--- Installer output ------------------------------------------------------------\n"
  tail -n "$output_rows" "$UI_LOG" 2>/dev/null | cut -c 1-"$cols"
}

(
  "$INSTALLER" "$@" 2>&1 | while IFS= read -r line; do
    printf '%s\n' "$line" >> "$UI_LOG"

    if [ ! -f "$READY_FILE" ]; then
      printf '%s\n' "$line"
    fi

    case "$line" in
      "INFO: Printer is "*) printf '%s\n' "${line#INFO: Printer is }" > "$PRINTER_FILE" ;;
      "INFO: Probe is "*)   printf '%s\n' "${line#INFO: Probe is }" > "$PROBE_FILE" ;;
      "INFO: Mount is "*)   printf '%s\n' "${line#INFO: Mount is }" > "$MOUNT_FILE" ;;
      INFO:*)  printf '%s\n' "$line" > "$STATUS_FILE" ;;
      WARN:*)  printf '%s\n' "$line" > "$STATUS_FILE" ;;
      ERROR:*) printf '%s\n' "$line" > "$STATUS_FILE" ;;
      FATAL:*) printf '%s\n' "$line" > "$STATUS_FILE" ;;
    esac

    case "$line" in
      "INFO: Starting install ..."|"INFO: Starting reinstall ...")
        mode_value="${line#INFO: Starting }"
        mode_value="${mode_value% ...}"
        printf '%s\n' "$mode_value" > "$MODE_FILE"
        touch "$READY_FILE"
        ;;
      "INFO Starting install ..."|"INFO Starting reinstall ...")
        mode_value="${line#INFO Starting }"
        mode_value="${mode_value% ...}"
        printf '%s\n' "$mode_value" > "$MODE_FILE"
        touch "$READY_FILE"
        ;;
    esac
  done
  exit "${PIPESTATUS[0]}"
) &
installer_pid=$!

while kill -0 "$installer_pid" 2>/dev/null; do
  if [ -f "$READY_FILE" ]; then
    break
  fi
  sleep 0.2
done

if [ ! -f "$READY_FILE" ]; then
  wait "$installer_pid"
  exit "$?"
fi

tput civis 2>/dev/null || true
clear
draw_header "Starting installation ..." ""

while kill -0 "$installer_pid" 2>/dev/null; do
  status=$(cat "$STATUS_FILE" 2>/dev/null)
  [ -z "$status" ] && status="Running ..."

  draw_header "$status" ""
  sleep 1
done

wait "$installer_pid"
exit_code=$?

status=$(cat "$STATUS_FILE" 2>/dev/null)
[ -z "$status" ] && status="Finished"

draw_header "$status" "$exit_code"

if [ "$exit_code" -eq 0 ]; then
  echo
  echo "Installer completed successfully."
else
  echo
  echo "Installer failed. See log: $UI_LOG"
fi

exit "$exit_code"
