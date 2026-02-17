#version=F43
# Xibo Kiosk Kickstart File
# =============================
# Automated Fedora 43 installation for Xibo digital signage
#
# Usage:
#   Boot from Fedora netinstall and add to kernel cmdline:
#   inst.ks=https://raw.githubusercontent.com/linuxnow/arexibo/master/kickstart/xibo-kiosk.ks
#
# Or create a custom ISO with this kickstart embedded.

# Installation settings
text
skipx
firstboot --disable
reboot --eject

# Localization
lang en_US.UTF-8
keyboard --xlayouts='us'
timezone Europe/Madrid --utc

# Network - DHCP by default
network --bootproto=dhcp --device=link --activate --onboot=yes
network --hostname=xibo-kiosk

# Root password (change this or use --lock)
rootpw --lock

# User configuration
user --name=xibo --groups=wheel --password=xibo --plaintext --gecos="Xibo Kiosk User"

# Disk configuration - use entire disk
clearpart --all --initlabel
autopart --type=plain --nohome

# Bootloader
bootloader --append="quiet rhgb"

# Package selection
%packages
@core
@hardware-support
@fonts

# Display manager and kiosk
gdm
gnome-kiosk
gnome-kiosk-script-session

# Arexibo dependencies
qt6-qtwebengine
dbus
zeromq

# Media playback
vlc
firefox
gstreamer1-plugins-base
gstreamer1-plugins-good
gstreamer1-plugins-bad-free
gstreamer1-plugins-ugly-free
gstreamer1-plugin-openh264
gstreamer1-plugin-libav

# Kiosk utilities (also pulled by xibo-kiosk, listed for clarity)
zenity
dunst
unclutter
opendoas

# Networking
avahi
nss-mdns
wireguard-tools
NetworkManager-wifi

# Remove unnecessary packages
-gnome-initial-setup
-gnome-tour
%end

# RPMFusion repositories
%post --erroronfail
# Add RPMFusion repos
dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm

# Swap ffmpeg-free for ffmpeg
dnf swap -y ffmpeg-free ffmpeg --allowerasing || true
%end

# Install arexibo from gh-pages yum repository
%post --erroronfail
cat > /etc/yum.repos.d/arexibo.repo << 'EOF'
[arexibo]
name=Arexibo Digital Signage Player
baseurl=https://linuxnow.github.io/arexibo/rpm/fedora/$releasever/$basearch/
enabled=1
gpgcheck=0
EOF

dnf install -y arexibo xibo-kiosk
%end

# Configure xibo user and directories
%post --erroronfail
# Enable lingering for xibo user
loginctl enable-linger xibo

# Create directories
mkdir -p /home/xibo/.local/bin
mkdir -p /home/xibo/.local/share/arexibo
mkdir -p /home/xibo/Videos

chown -R xibo:xibo /home/xibo
%end

# Configure GDM autologin
%post --erroronfail
cat > /etc/gdm/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=xibo

[security]

[xdmcp]

[chooser]

[debug]
EOF
%end

# Configure AccountsService
%post --erroronfail
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/xibo << 'EOF'
[User]
Session=gnome-kiosk-script-wayland
SystemAccount=false
EOF
%end

# Configure opendoas
%post --erroronfail
cat > /etc/doas.conf << 'EOF'
permit nopass xibo cmd reboot
permit nopass xibo cmd shutdown
EOF
chmod 600 /etc/doas.conf
%end

# Create kiosk dispatcher script
# This is the only script in the user's home — it dispatches to the
# RPM-installed session holder or wizard based on whether cms.json exists.
%post --erroronfail
cat > /home/xibo/.local/bin/gnome-kiosk-script << 'EOF'
#!/bin/bash
AREXIBO_KIOSK_DIR="${AREXIBO_KIOSK_DIR:-/usr/share/arexibo/kiosk}"
AREXIBO_DATA_DIR="${AREXIBO_DATA_DIR:-${HOME}/.local/share/arexibo}"
if [ -f "${AREXIBO_DATA_DIR}/cms.json" ]; then
    exec "${AREXIBO_KIOSK_DIR}/gnome-kiosk-script.arexibo.sh"
else
    exec "${AREXIBO_KIOSK_DIR}/gnome-kiosk-script.zenity.init.sh"
fi
EOF
chmod 755 /home/xibo/.local/bin/gnome-kiosk-script
chown xibo:xibo /home/xibo/.local/bin/gnome-kiosk-script

# Add local bin to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/xibo/.bashrc
chown xibo:xibo /home/xibo/.bashrc
%end

# Create reboot/shutdown wrappers
%post --erroronfail
cat > /home/xibo/.local/bin/reboot << 'EOF'
#!/bin/bash
doas reboot
EOF
chmod 755 /home/xibo/.local/bin/reboot

cat > /home/xibo/.local/bin/shutdown << 'EOF'
#!/bin/bash
doas shutdown -h now
EOF
chmod 755 /home/xibo/.local/bin/shutdown

chown xibo:xibo /home/xibo/.local/bin/reboot /home/xibo/.local/bin/shutdown
%end

# Enable services
%post --erroronfail
systemctl enable gdm
systemctl enable avahi-daemon
systemctl set-default graphical.target
%end

# Final cleanup
%post --erroronfail
# Ensure all xibo files have correct ownership
chown -R xibo:xibo /home/xibo

# Clean dnf cache
dnf clean all
%end
