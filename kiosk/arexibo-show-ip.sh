#!/bin/bash
# Show IP address, CMS and player status via dunst notification.
# Triggered by Ctrl+I (via keyd).
AREXIBO_DATA_DIR="${AREXIBO_DATA_DIR:-${HOME}/.local/share/arexibo}"
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
STATUS=$(systemctl --user is-active arexibo-player.service 2>/dev/null || echo "unknown")
CMS=$(grep -oP '"address"\s*:\s*"\K[^"]+' "${AREXIBO_DATA_DIR}/cms.json" 2>/dev/null || echo "not configured")
notify-send -t 5000 "Arexibo Status" "IP: $IP\nCMS: $CMS\nPlayer: $STATUS"
