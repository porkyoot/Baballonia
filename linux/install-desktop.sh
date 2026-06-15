#!/usr/bin/env bash
# linux/install-desktop.sh — Install Baballonia app menu entry for Linux
#
# Creates a .desktop file so Baballonia appears in the GNOME/KDE/etc app menu
# and launches with the Linux camera fix (LibV4L2Capture, auto-detect tracker).
#
# Usage:
#   bash linux/install-desktop.sh [/path/to/Baballonia.x64.vX.Y.Z]
#
# If no path is given, common install locations are searched automatically.
# Run without sudo — installs per-user (.local/share/applications).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GRN}[baballonia-desktop]${NC} $*"; }
warn()  { echo -e "${YLW}[baballonia-desktop]${NC} $*"; }
error() { echo -e "${RED}[baballonia-desktop]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Find or accept the Baballonia install directory
# ---------------------------------------------------------------------------
find_install_dir() {
    local candidates=(
        "$HOME/Systems/VR/Baballonia"*
        "$HOME/.local/share/Baballonia"*
        "$HOME/Applications/Baballonia"*
        /opt/Baballonia*
    )
    for c in "${candidates[@]}"; do
        if [[ -x "$c/Baballonia.Desktop" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

if [[ -n "${1:-}" ]]; then
    INSTALL_DIR="$1"
else
    INSTALL_DIR=$(find_install_dir 2>/dev/null) \
        || error "Baballonia.Desktop not found. Pass install path as argument:
  bash linux/install-desktop.sh /path/to/Baballonia.x64.vX.Y.Z"
fi

[[ -x "$INSTALL_DIR/Baballonia.Desktop" ]] \
    || error "'$INSTALL_DIR' does not contain Baballonia.Desktop"

INSTALL_DIR="$(realpath "$INSTALL_DIR")"
info "Install directory: $INSTALL_DIR"

# ---------------------------------------------------------------------------
# 2. Install the launch wrapper into the Baballonia directory
# ---------------------------------------------------------------------------
LAUNCHER="$INSTALL_DIR/linux-launch.sh"
if [[ -f "$SCRIPT_DIR/launch-babblonia.sh" ]]; then
    cp "$SCRIPT_DIR/launch-babblonia.sh" "$LAUNCHER"
else
    # Inline fallback if running without the full repo
    cat > "$LAUNCHER" <<'LAUNCH_BODY'
#!/usr/bin/env bash
set -euo pipefail
BABALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HOME/babblonia.log"
SETTINGS="$HOME/.config/ProjectBabble/ApplicationData/LocalSettings.json"

if command -v v4l2-ctl >/dev/null 2>&1; then
    TRACKER_DEV=""
    for dev in /dev/video*; do
        model=$(udevadm info --query=property "$dev" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2 | tr '[:upper:]' '[:lower:]')
        [[ "$model" == *openiri* ]] && { TRACKER_DEV="$dev"; break; }
    done
    if [[ -n "$TRACKER_DEV" ]]; then
        echo "Tracker: $TRACKER_DEV"
        DEV_NR="${TRACKER_DEV##*/video}"
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
        fi
    fi
fi

echo "=== Babblonia launch $(date) ===" > "$LOG"
cd "$BABALL_DIR"
exec ./Baballonia.Desktop 2>&1 | tee -a "$LOG"
LAUNCH_BODY
fi
chmod +x "$LAUNCHER"
info "Launcher installed: $LAUNCHER"

# ---------------------------------------------------------------------------
# 3. Install icon (copy 512px PNG to user icon theme)
# ---------------------------------------------------------------------------
ICON_SRC="$INSTALL_DIR/Assets/Icon_512x512.png"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
ICON_NAME="baballonia"

if [[ -f "$ICON_SRC" ]]; then
    mkdir -p "$ICON_DIR"
    cp "$ICON_SRC" "$ICON_DIR/$ICON_NAME.png"
    info "Icon installed: $ICON_DIR/$ICON_NAME.png"
else
    warn "Icon not found at $ICON_SRC — desktop entry will use a generic icon"
    ICON_NAME="applications-multimedia"
fi

# ---------------------------------------------------------------------------
# 4. Create the .desktop file
# ---------------------------------------------------------------------------
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/baballonia.desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Baballonia
GenericName=Face Tracker
Comment=Project Babble mouth tracking for VR — Linux edition
Exec=$LAUNCHER
Icon=$ICON_NAME
Terminal=false
Type=Application
Categories=Utility;Game;
Keywords=VR;face;tracking;babble;openIris;
StartupNotify=true
StartupWMClass=Baballonia.Desktop
EOF

chmod +x "$DESKTOP_FILE"
info "Desktop entry installed: $DESKTOP_FILE"

# ---------------------------------------------------------------------------
# 5. Refresh the app menu database
# ---------------------------------------------------------------------------
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    info "App menu database updated"
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    info "Icon cache updated"
fi

info ""
info "Done! Baballonia should now appear in your app menu."
info "Log file will be written to: \$HOME/babblonia.log"
