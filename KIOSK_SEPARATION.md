# xibo-kiosk Separation Plan

## Overview
The xibo-kiosk package is being separated into its own repository to allow independent versioning and maintenance. This package provides kiosk session scripts that work with multiple Xibo player implementations.

## New Repository: xibo-kiosk

### Repository Contents
The new `xibo-kiosk` repository should contain:

#### 1. Kiosk Scripts (`kiosk/` directory)
- `gnome-kiosk-script.xibo.sh` - Main session holder
- `gnome-kiosk-script.xibo-init.sh` - First-boot registration wizard
- `xibo-player.service` - Systemd user service
- `xibo-keyd-run.sh` - Keyboard shortcut helper
- `xibo-show-ip.sh` - Display IP address utility
- `xibo-show-cms.sh` - Display CMS connection utility
- `keyd-xibo.conf` - Keyboard shortcut configuration
- `dunstrc` - Notification daemon configuration

#### 2. RPM Packaging (`rpm/xibo-kiosk.spec`)
```spec
Name:           xibo-kiosk
Version:        1.0.0
Release:        1%{?dist}
Summary:        Kiosk session scripts for Xibo digital signage players

License:        AGPLv3+
URL:            https://github.com/xibo-players/xibo-kiosk
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch

Requires:       gnome-kiosk-script-session
Requires:       dunst
Requires:       unclutter
Requires:       zenity
Requires:       opendoas
Requires:       keyd
Requires:       mesa-va-drivers
Requires:       libva
Recommends:     libva-intel-driver

%description
Kiosk session scripts for running Xibo digital signage players as full-screen 
displays under GNOME Kiosk. Includes a first-boot registration wizard,
session holder with health monitoring, dunst notification config, and
a systemd user unit for the player process.

Supports multiple Xibo player implementations:
- arexibo (Rust-based)
- xiboplayer-electron
- xiboplayer-chromium

%prep
%autosetup -n %{name}-%{version}

%install
install -Dm755 kiosk/gnome-kiosk-script.xibo.sh %{buildroot}%{_datadir}/xibo-kiosk/gnome-kiosk-script.xibo.sh
install -Dm755 kiosk/gnome-kiosk-script.xibo-init.sh %{buildroot}%{_datadir}/xibo-kiosk/gnome-kiosk-script.xibo-init.sh
install -Dm644 kiosk/dunstrc %{buildroot}%{_datadir}/xibo-kiosk/dunstrc
install -Dm644 kiosk/xibo-player.service %{buildroot}%{_userunitdir}/xibo-player.service
install -Dm755 kiosk/xibo-keyd-run.sh %{buildroot}%{_datadir}/xibo-kiosk/xibo-keyd-run.sh
install -Dm755 kiosk/xibo-show-ip.sh %{buildroot}%{_datadir}/xibo-kiosk/xibo-show-ip.sh
install -Dm755 kiosk/xibo-show-cms.sh %{buildroot}%{_datadir}/xibo-kiosk/xibo-show-cms.sh
install -Dm644 kiosk/keyd-xibo.conf %{buildroot}%{_sysconfdir}/keyd/xibo.conf

%files
%dir %{_datadir}/xibo-kiosk
%{_datadir}/xibo-kiosk/gnome-kiosk-script.xibo.sh
%{_datadir}/xibo-kiosk/gnome-kiosk-script.xibo-init.sh
%{_datadir}/xibo-kiosk/dunstrc
%{_datadir}/xibo-kiosk/xibo-keyd-run.sh
%{_datadir}/xibo-kiosk/xibo-show-ip.sh
%{_datadir}/xibo-kiosk/xibo-show-cms.sh
%{_userunitdir}/xibo-player.service
%{_sysconfdir}/keyd/xibo.conf

%changelog
* Mon Feb 17 2026 Xibo Team - 1.0.0-1
- Initial standalone xibo-kiosk package
- Separated from arexibo repository for independent versioning
```

#### 3. DEB Packaging (`.github/workflows/deb.yml`)
Build workflow for creating Debian packages for Ubuntu 24.04.

#### 4. Kickstart File (`kickstart/xibo-kiosk.ks`)
Automated installation kickstart for creating kiosk systems.

#### 5. Documentation
- README.md - Installation and usage instructions
- INSTALL.md - Detailed setup guide
- Player compatibility matrix

#### 6. GitHub Workflows
- `.github/workflows/rpm.yml` - Build RPM packages
- `.github/workflows/deb.yml` - Build DEB packages
- `.github/workflows/release.yml` - Create releases

## Changes Required in arexibo Repository

### 1. Remove Kiosk Packaging
- Remove `%package kiosk` section from `rpm/arexibo.spec`
- Remove kiosk file installation commands
- Remove kiosk-specific dependencies

### 2. Remove Kiosk Build from Workflows
- Remove kiosk packaging from `.github/workflows/deb.yml`
- Update `.github/workflows/image.yml` to use external xibo-kiosk package

### 3. Update Documentation
- Update README.md to reference separate xibo-kiosk package
- Add installation instructions that include xibo-kiosk

### 4. Remove Directories
- Remove `kiosk/` directory
- Move `kickstart/xibo-kiosk.ks` to new repository

## Installation After Separation

Users will install both packages:

### Fedora/RHEL
```bash
# Add both repositories
sudo dnf copr enable xibo-players/arexibo
sudo dnf copr enable xibo-players/xibo-kiosk

# Install both packages
sudo dnf install arexibo xibo-kiosk
```

### Ubuntu/Debian
```bash
# Add arexibo repository
curl -fsSL https://xibo-players.github.io/arexibo/deb/DEB-GPG-KEY-arexibo | \
  sudo gpg --dearmor -o /usr/share/keyrings/arexibo.gpg
echo "deb [signed-by=/usr/share/keyrings/arexibo.gpg] https://xibo-players.github.io/arexibo/deb/ubuntu/24.04 ./" | \
  sudo tee /etc/apt/sources.list.d/arexibo.list

# Add xibo-kiosk repository  
curl -fsSL https://xibo-players.github.io/xibo-kiosk/deb/DEB-GPG-KEY-xibo-kiosk | \
  sudo gpg --dearmor -o /usr/share/keyrings/xibo-kiosk.gpg
echo "deb [signed-by=/usr/share/keyrings/xibo-kiosk.gpg] https://xibo-players.github.io/xibo-kiosk/deb/ubuntu/24.04 ./" | \
  sudo tee /etc/apt/sources.list.d/xibo-kiosk.list

# Install both packages
sudo apt update
sudo apt install arexibo xibo-kiosk
```

## Migration Path

1. Create new `xibo-kiosk` repository
2. Copy kiosk files and setup build workflows
3. Publish initial xibo-kiosk v1.0.0 packages
4. Update arexibo repository to remove kiosk packaging
5. Update documentation with migration notes
6. Update image builds to use external xibo-kiosk package

## Benefits

1. **Independent Versioning**: Kiosk scripts can be updated without releasing new player versions
2. **Multi-Player Support**: Same kiosk package works with arexibo, electron, and chromium players
3. **Cleaner Separation**: Each repository has a focused purpose
4. **Easier Maintenance**: Smaller, more manageable codebases
5. **Flexible Updates**: Users can update kiosk scripts independently
