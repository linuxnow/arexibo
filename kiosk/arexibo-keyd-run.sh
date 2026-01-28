#!/bin/bash
# Run a command in the kiosk user's graphical session.
# Called by keyd (which runs as root) to bridge into the user session.

KIOSK_USER=$(who | awk 'NR==1{print $1}')
[ -z "$KIOSK_USER" ] && exit 1

KIOSK_UID=$(id -u "$KIOSK_USER")
XDG_RUNTIME_DIR="/run/user/${KIOSK_UID}"

exec runuser -u "$KIOSK_USER" -- env \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" \
    "$@"
