#!/bin/bash
# Show CMS server and display name, offer reconfiguration.
# Triggered by Ctrl+R (via keyd).
XIBO_KIOSK_DIR="${XIBO_KIOSK_DIR:-/usr/share/xibo-kiosk}"
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"
CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
DISPLAY_NAME=$(grep -oP '"display_name"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "unknown")
if zenity --question --title="Xibo" \
    --text="CMS Server: $CMS\nDisplay: $DISPLAY_NAME\n\nReconfigure CMS connection?\n\nThis will stop the player and start the setup wizard." \
    --width=300 2>/dev/null; then
    systemctl --user stop xibo-player.service 2>/dev/null || true
    rm -f "${XIBO_DATA_DIR}/cms.json"
    pkill -u "$(whoami)" -f gnome-kiosk-script 2>/dev/null || true
    exec "${XIBO_KIOSK_DIR}/gnome-kiosk-script.zenity.init.sh"
fi
