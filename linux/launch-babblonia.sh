#!/usr/bin/env bash
# linux/launch-babblonia.sh — Launch Baballonia with ESP32-S3 OpenIris tracker on Linux.
#
# Prerequisites:
#   1. Kernel patch applied:  sudo bash linux/install.sh
#   2. Baballonia built on Linux (LibV4L2Capture is included and handles MJPEG natively)
#
# The LibV4L2Capture module reads MJPEG directly from the tracker via V4L2 mmap —
# no ffmpeg bridge or v4l2loopback required.
#
# Usage:  bash linux/launch-babblonia.sh [/path/to/Baballonia]

set -euo pipefail

# When installed as linux-launch.sh inside the Baballonia directory, default to
# the script's own directory so it works from the app menu without arguments.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BABALL_DIR="${1:-$_SELF_DIR}"
LOG="$HOME/babblonia.log"

if [[ ! -x "$BABALL_DIR/Baballonia.Desktop" ]]; then
    echo "ERROR: Baballonia.Desktop not found in $BABALL_DIR" >&2
    echo "Pass the install path as first argument or set BABALL_DIR." >&2
    exit 1
fi

# Auto-detect the tracker and pre-configure settings so Baballonia opens it
# on first launch without needing manual camera selection in the UI.
SETTINGS="$HOME/.config/ProjectBabble/ApplicationData/LocalSettings.json"

if command -v v4l2-ctl >/dev/null 2>&1; then
    # ID_MODEL from udev gives us the name Baballonia will display in the device list.
    # Find the first video device whose udev ID_MODEL contains "openiri" (case-insensitive).
    TRACKER_DEV=""
    for dev in /dev/video*; do
        model=$(udevadm info --query=property "$dev" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2 | tr '[:upper:]' '[:lower:]')
        if [[ "$model" == *openiri* ]]; then
            TRACKER_DEV="$dev"
            break
        fi
    done

    if [[ -n "$TRACKER_DEV" ]]; then
        echo "Tracker: $TRACKER_DEV"
        DEV_NR="${TRACKER_DEV##*/video}"

        # Build the friendly name Baballonia's DesktopDeviceEnumerator will use:
        #   "{ID_VENDOR} {ID_MODEL} (videoN)"  or  "{ID_MODEL} (videoN)"
        ID_MODEL=$(udevadm info --query=property "$TRACKER_DEV" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2 || true)
        ID_VENDOR=$(udevadm info --query=property "$TRACKER_DEV" 2>/dev/null | grep '^ID_VENDOR=' | cut -d= -f2 || true)

        if [[ -n "$ID_VENDOR" && -n "$ID_MODEL" ]]; then
            CAMERA_LABEL="${ID_VENDOR} ${ID_MODEL} (video${DEV_NR})"
        elif [[ -n "$ID_MODEL" ]]; then
            CAMERA_LABEL="${ID_MODEL} (video${DEV_NR})"
        else
            CAMERA_LABEL="video${DEV_NR}"
        fi

        if [[ -f "$SETTINGS" ]] && command -v jq >/dev/null 2>&1; then
            jq --arg label "$CAMERA_LABEL" \
               '.LastOpenedFaceCamera = $label | .ShouldAutostartFaceCamera = true' \
               "$SETTINGS" > /tmp/babblonia-settings-tmp.json \
               && mv /tmp/babblonia-settings-tmp.json "$SETTINGS"
            echo "Settings: LastOpenedFaceCamera -> $CAMERA_LABEL"
        fi
    else
        echo "Warning: openiristracker USB device not found — select camera in UI."
    fi
fi

echo "=== Babblonia launch $(date) ===" > "$LOG"
cd "$BABALL_DIR"
exec ./Baballonia.Desktop 2>&1 | tee -a "$LOG"
