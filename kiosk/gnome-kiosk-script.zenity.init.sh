#!/bin/bash
# Arexibo CMS Registration Wizard
# =================================
# First-boot wizard that collects CMS credentials via Zenity dialogs,
# then hands off to the session holder.

AREXIBO_KIOSK_DIR="${AREXIBO_KIOSK_DIR:-/usr/share/arexibo/kiosk}"
AREXIBO_DATA_DIR="${AREXIBO_DATA_DIR:-${HOME}/.local/share/arexibo}"

# Start dunst for notifications
dunst -conf "${AREXIBO_KIOSK_DIR}/dunstrc" &

# Wait for Wayland compositor
sleep 2

# Import display environment into systemd user manager
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR

# Show welcome message
notify-send "Arexibo Setup" "Starting configuration wizard..." -t 3000

# Main registration loop
while true; do
    # Get CMS host from user
    CMS_HOST=$(zenity --entry \
        --title="Arexibo Setup" \
        --text="Enter CMS Server URL (e.g., https://xibo.example.com/):" \
        --entry-text="https://" \
        --width=400)

    if [ -z "$CMS_HOST" ]; then
        zenity --question \
            --title="Arexibo Setup" \
            --text="Setup cancelled. Do you want to try again?" \
            --width=300

        if [ $? -ne 0 ]; then
            notify-send "Arexibo" "Setup cancelled. Rebooting in 10 seconds..." -t 8000
            sleep 10
            doas reboot 2>/dev/null || reboot
        fi
        continue
    fi

    # Ensure URL ends with /
    [[ "${CMS_HOST}" != */ ]] && CMS_HOST="${CMS_HOST}/"

    # Get CMS key from user (plain text — this is a dedicated kiosk)
    CMS_KEY=$(zenity --entry \
        --title="Arexibo Setup" \
        --text="Enter CMS Key:" \
        --width=400)

    if [ -z "$CMS_KEY" ]; then
        zenity --warning \
            --title="Arexibo Setup" \
            --text="CMS Key is required." \
            --width=300
        continue
    fi

    # Generate display ID based on machine-id and timestamp
    MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "unknown")
    TIMESTAMP=$(date +%s)
    DISPLAY_ID=$(echo "${MACHINE_ID}${TIMESTAMP}${CMS_KEY}" | sha256sum | cut -c1-12)

    # Get optional display name
    HOSTNAME=$(hostname)
    DISPLAY_NAME=$(zenity --entry \
        --title="Arexibo Setup" \
        --text="Enter Display Name (optional):" \
        --entry-text="${HOSTNAME}" \
        --width=400)

    [ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="${HOSTNAME}"

    # Get IP for confirmation dialog
    IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

    # Show summary and confirm
    zenity --question \
        --title="Arexibo Setup - Confirm" \
        --text="Configuration Summary:\n\nCMS Host: ${CMS_HOST}\nDisplay ID: arx43-${DISPLAY_ID}\nDisplay Name: ${DISPLAY_NAME}\nIP Address: ${IP}\n\nProceed with registration?" \
        --width=400

    if [ $? -ne 0 ]; then
        continue
    fi

    # Create cms.json
    mkdir -p "${AREXIBO_DATA_DIR}"
    cat > "${AREXIBO_DATA_DIR}/cms.json" << EOF
{
    "address": "${CMS_HOST}",
    "key": "${CMS_KEY}",
    "display_id": "arx43-${DISPLAY_ID}",
    "display_name": "${DISPLAY_NAME}",
    "proxy": null
}
EOF

    if [ $? -eq 0 ]; then
        notify-send -r 1 -t 0 "Arexibo" "IP: $IP — Configuration saved. Starting player..." 2>/dev/null || true

        # Start the player service and wait for initial registration attempt
        systemctl --user start arexibo-player.service
        sleep 5

        if systemctl --user is-active --quiet arexibo-player.service; then
            notify-send -r 1 -t 0 "Arexibo" "IP: $IP — Connected to CMS" 2>/dev/null || true

            zenity --info \
                --title="Arexibo Setup Complete" \
                --text="Player is running!\n\nDisplay ID: arx43-${DISPLAY_ID}\nIP Address: ${IP}\n\nIf the display shows no content, authorize it in your Xibo CMS." \
                --width=400
        else
            # Exit code 2 = not authorized yet (transient), anything else = real error
            EXIT_CODE=$(systemctl --user show -p ExecMainStatus --value arexibo-player.service 2>/dev/null)

            if [ "$EXIT_CODE" = "2" ]; then
                notify-send -r 1 -t 0 -u normal "Arexibo" \
                    "IP: $IP — Waiting for CMS authorization\nDisplay ID: arx43-${DISPLAY_ID}" 2>/dev/null || true

                zenity --info \
                    --title="Arexibo Setup - Authorization Pending" \
                    --text="Display registered but not yet authorized.\n\nDisplay ID: arx43-${DISPLAY_ID}\nIP Address: ${IP}\n\nPlease authorize this display in your Xibo CMS.\nThe player will retry automatically." \
                    --width=400
            else
                ERROR=$(journalctl --user -u arexibo-player.service --no-pager -n 20 -q 2>/dev/null \
                    | grep -iE 'error|fail|denied|refused|timeout' \
                    | tail -1 \
                    | sed 's/.*arexibo\[.*\]: //' \
                    | head -c 200)

                notify-send -r 1 -t 0 -u critical "Arexibo" \
                    "IP: $IP — Error: ${ERROR:-player failed to start}" 2>/dev/null || true

                zenity --question \
                    --title="Arexibo Setup - Error" \
                    --text="Player failed to start.\n\nError: ${ERROR:-unknown}\nIP Address: ${IP}\n\nDo you want to reconfigure?" \
                    --width=400

                if [ $? -eq 0 ]; then
                    rm -f "${AREXIBO_DATA_DIR}/cms.json"
                    continue
                fi
            fi
        fi

        # Hand off to session holder (has monitoring loop)
        pkill -u "$(whoami)" dunst 2>/dev/null || true
        exec "${AREXIBO_KIOSK_DIR}/gnome-kiosk-script.arexibo.sh"
    else
        zenity --error \
            --title="Arexibo Setup" \
            --text="Failed to save configuration. Please try again." \
            --width=300
    fi
done
