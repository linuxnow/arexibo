#!/bin/bash
# Show IP address, CMS and player status via dunst notification.
# Triggered by Ctrl+I (via keyd).
XIBO_DATA_DIR="${XIBO_DATA_DIR:-${HOME}/.local/share/xibo}"
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
STATUS=$(systemctl --user is-active xibo-player.service 2>/dev/null || echo "unknown")
CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${XIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
notify-send -t 5000 "Xibo Status" "IP: $IP\nCMS: $CMS\nPlayer: $STATUS"
