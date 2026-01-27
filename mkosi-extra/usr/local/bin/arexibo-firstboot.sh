#!/bin/bash
# Arexibo first-boot setup script
# Runs once on first boot to set password and install arexibo

set -e

MARKER="/var/lib/arexibo-firstboot-done"

# Check if already run
[ -f "$MARKER" ] && exit 0

echo "Arexibo first-boot setup starting..."

# Set xibo password (user created by sysusers)
echo "xibo:xibo" | chpasswd

# Fix ownership of home directory
chown -R xibo:xibo /home/xibo

# Set permissions on scripts
chmod 755 /home/xibo/.local/bin/*.sh 2>/dev/null || true
chmod 755 /home/xibo/.local/bin/gnome-kiosk-script 2>/dev/null || true

# Install arexibo from the configured DNF repository
echo "Installing arexibo..."
dnf install -y arexibo || true

# Mark as complete
touch "$MARKER"
echo "Arexibo first-boot setup complete"
