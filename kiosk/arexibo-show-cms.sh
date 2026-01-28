#!/bin/bash
# Show CMS server and display name, offer reconfiguration.
# Triggered by Ctrl+R (via keyd).
AREXIBO_KIOSK_DIR="${AREXIBO_KIOSK_DIR:-/usr/share/arexibo/kiosk}"
AREXIBO_DATA_DIR="${AREXIBO_DATA_DIR:-${HOME}/.local/share/arexibo}"
CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${AREXIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
DISPLAY_NAME=$(grep -oP '"display_name"\s*:\s*"\K[^"]+' "${AREXIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "unknown")
if zenity --question --title="Arexibo" \
    --text="CMS Server: $CMS\nDisplay: $DISPLAY_NAME\n\nReconfigure CMS connection?\n\nThis will stop the player and start the setup wizard." \
    --width=300 2>/dev/null; then
    systemctl --user stop arexibo-player.service 2>/dev/null || true
    rm -f "${AREXIBO_DATA_DIR}/cms.json"
    pkill -u "$(whoami)" -f gnome-kiosk-script 2>/dev/null || true
    exec "${AREXIBO_KIOSK_DIR}/gnome-kiosk-script.zenity.init.sh"
fi
