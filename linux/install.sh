#!/usr/bin/env bash
# linux/install.sh — Baballonia Linux kernel patch
#
# Fixes VIDIOC_STREAMON ENOMEM for Project Babble / OpenIris ESP32-S3 mouth trackers
# on Linux (Ubuntu/Debian and derivatives). The Linux uvcvideo driver rejects the
# tracker's UVC payload size (64 bytes = 1 USB packet); this patches the kernel
# module to allow it.
#
# Usage:
#   sudo bash linux/install.sh
#   — or one-liner —
#   curl -fsSL https://raw.githubusercontent.com/porkyoot/Baballonia/linux-fixes/linux/install.sh | sudo bash
#
# To uninstall:
#   sudo bash linux/install.sh --uninstall
#
set -euo pipefail

SBIN=/usr/local/sbin/fix-uvcvideo-babble
HOOK=/etc/kernel/postinst.d/fix-uvcvideo-babble
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GRN}[babble-uvc-fix]${NC} $*"; }
warn()  { echo -e "${YLW}[babble-uvc-fix]${NC} $*"; }
error() { echo -e "${RED}[babble-uvc-fix]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Please run as root: sudo bash linux/install.sh"

if [[ "${1:-}" == "--uninstall" ]]; then
    info "Uninstalling babble-uvc-fix ..."
    rm -f "$SBIN" "$HOOK"
    info "Restoring original uvcvideo modules from backups ..."
    for dir in /lib/modules/*/kernel/drivers/media/usb/uvc; do
        for orig in "$dir"/uvcvideo.ko*.orig; do
            [[ -f "$orig" ]] || continue
            dst="${orig%.orig}"
            mv -f "$orig" "$dst"
            kver=$(echo "$dir" | sed 's|/lib/modules/||;s|/kernel.*||')
            info "  Restored $dst"
            if [[ "$(uname -r)" == "$kver" ]]; then
                modprobe -r uvcvideo 2>/dev/null || true
                modprobe uvcvideo 2>/dev/null || true
            fi
        done
    done
    info "Uninstall complete."
    exit 0
fi

for cmd in python3 zstd; do
    command -v "$cmd" >/dev/null 2>&1 || error "Missing dependency: $cmd  (try: sudo apt install $cmd)"
done

info "Installing patcher to $SBIN ..."
if [[ -f "$SCRIPT_DIR/fix-uvcvideo-babble" ]]; then
    install -m 755 "$SCRIPT_DIR/fix-uvcvideo-babble" "$SBIN"
else
    PATCHER_URL="https://raw.githubusercontent.com/porkyoot/Baballonia/linux-fixes/linux/fix-uvcvideo-babble"
    warn "fix-uvcvideo-babble not found locally; downloading from $PATCHER_URL ..."
    curl -fsSL "$PATCHER_URL" -o "$SBIN"
    chmod 755 "$SBIN"
fi

info "Installing kernel post-install hook to $HOOK ..."
if [[ -f "$SCRIPT_DIR/kernel-postinst-hook" ]]; then
    install -m 755 "$SCRIPT_DIR/kernel-postinst-hook" "$HOOK"
else
    cat > "$HOOK" <<'HOOK_BODY'
#!/bin/sh
KVER="$1"
[ -n "$KVER" ] || exit 0
command -v fix-uvcvideo-babble >/dev/null 2>&1 && fix-uvcvideo-babble "$KVER"
HOOK_BODY
    chmod 755 "$HOOK"
fi

info "Patching uvcvideo for all installed kernels ..."
"$SBIN"

info ""
info "Installation complete!"
info "Your Project Babble / OpenIris mouth tracker should now stream."
info ""
info "Test with:  v4l2-ctl --list-devices"
info "            v4l2-ctl -d /dev/videoN --stream-mmap --stream-count=5"
info ""
info "To uninstall: sudo bash linux/install.sh --uninstall"
