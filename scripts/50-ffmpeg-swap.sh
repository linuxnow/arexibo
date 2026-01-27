#!/bin/bash
# Install third-party repos and packages
# Runs inside the built image via systemd-nspawn (see build.yml)
set -euo pipefail

FEDORA_VER=$(rpm -E %fedora)

# --- Arexibo repo (gh-pages) ---
cat > /etc/yum.repos.d/arexibo.repo << EOF
[arexibo]
name=Arexibo
baseurl=https://linuxnow.github.io/arexibo/rpm/fedora/${FEDORA_VER}/\$basearch/
enabled=1
gpgcheck=0
EOF

dnf install -y arexibo arexibo-kiosk

# --- RPM Fusion ---
dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm

# Swap ffmpeg-free for full ffmpeg (provides H.264/AAC codecs)
dnf swap -y ffmpeg-free ffmpeg --allowerasing || true

# Clean up
dnf clean all
