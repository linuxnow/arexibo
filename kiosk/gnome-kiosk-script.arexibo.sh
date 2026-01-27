#!/bin/bash
# Arexibo GNOME Kiosk Session Holder
# ===================================
# Keeps the gnome-kiosk session alive while delegating player management
# to systemd (arexibo-player.service). Shows persistent status notifications.

AREXIBO_KIOSK_DIR="${AREXIBO_KIOSK_DIR:-/usr/share/arexibo/kiosk}"
AREXIBO_DATA_DIR="${AREXIBO_DATA_DIR:-${HOME}/.local/share/arexibo}"
NOTIFY_ID=1

# Start supporting services
dunst -conf "${AREXIBO_KIOSK_DIR}/dunstrc" &
unclutter --timeout 3 &

# Wait for compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Set audio volume (90%)
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.9 2>/dev/null || true

# Helper: get IP address
get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
}

# Helper: send/update the persistent status notification
# Usage: status_notify "message" [urgency]
# urgency: low, normal, critical (default: normal)
status_notify() {
    local msg="$1"
    local urgency="${2:-normal}"
    notify-send -r "$NOTIFY_ID" -u "$urgency" -t 0 "Arexibo" "$msg" 2>/dev/null || true
}

# Helper: extract error reason from arexibo journal logs
get_player_error() {
    journalctl --user -u arexibo-player.service --no-pager -n 20 -q 2>/dev/null \
        | grep -iE 'error|fail|denied|unauthorized|not authorised|refused|timeout' \
        | tail -1 \
        | sed 's/.*arexibo\[.*\]: //' \
        | head -c 200
}

# Show initial status
IP=$(get_ip)
status_notify "IP: $IP — Starting player..."

# Start arexibo via systemd (handles restarts, resource limits, logging)
if [ -f "${AREXIBO_DATA_DIR}/cms.json" ]; then
    systemctl --user start arexibo-player.service
fi

# Monitor player health
FAIL_COUNT=0
MAX_FAILS=3

while true; do
    sleep 10

    IP=$(get_ip)

    if systemctl --user is-active --quiet arexibo-player.service; then
        FAIL_COUNT=0
        # Dismiss notification when connected — player is showing content
        notify-send -r "$NOTIFY_ID" -t 1 "Arexibo" "" 2>/dev/null || true
    else
        # Check exit code: 2 = not authorized yet (transient), 1 = real error
        EXIT_CODE=$(systemctl --user show -p ExecMainStatus --value arexibo-player.service 2>/dev/null)

        if [ "$EXIT_CODE" = "2" ]; then
            # Display registered but not yet authorized in CMS — wait patiently
            status_notify "IP: $IP — Waiting for CMS authorization..." "normal"
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))

            # Extract error from journal
            ERROR=$(get_player_error)
            if [ -n "$ERROR" ]; then
                status_notify "IP: $IP — Error: $ERROR" "critical"
            else
                status_notify "IP: $IP — Player not running (attempt $FAIL_COUNT/$MAX_FAILS)" "critical"
            fi

            if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
                # Offer to reconfigure if wizard is available
                if [ -f "${AREXIBO_KIOSK_DIR}/gnome-kiosk-script.zenity.init.sh" ]; then
                    status_notify "IP: $IP — Player failed. Reconfigure?" "critical"
                    if zenity --question \
                        --title="Arexibo - Player Failed" \
                        --text="The player has failed $MAX_FAILS times.\n\nLast error: ${ERROR:-unknown}\n\nDo you want to reconfigure?" \
                        --width=400 2>/dev/null; then
                        # Remove config so dispatcher picks wizard on next boot
                        rm -f "${AREXIBO_DATA_DIR}/cms.json"
                        pkill -u "$(whoami)" dunst 2>/dev/null || true
                        exec "${AREXIBO_KIOSK_DIR}/gnome-kiosk-script.zenity.init.sh"
                    fi
                fi

                # Reset counter — either user declined reconfigure or no wizard available
                FAIL_COUNT=0
                # Try restarting the service
                systemctl --user restart arexibo-player.service 2>/dev/null || true
                status_notify "IP: $IP — Restarting player..." "normal"
            fi
        fi
    fi
done
