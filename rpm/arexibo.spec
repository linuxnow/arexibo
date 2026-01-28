%global debug_package %{nil}

Name:           arexibo
Version:        0.3.1
Release:        1%{?dist}
Summary:        Rust-based digital signage player for Xibo CMS

License:        AGPLv3+
URL:            https://github.com/linuxnow/arexibo
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  rust >= 1.75
BuildRequires:  cargo
BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  dbus-devel >= 1.6
BuildRequires:  zeromq-devel >= 4.1
BuildRequires:  qt6-qtwebengine-devel

Requires:       qt6-qtwebengine
Requires:       dbus
Requires:       zeromq

%description
Arexibo is a Rust-based digital signage player compatible with Xibo CMS.
It provides a lightweight alternative to the official Xibo player,
designed for kiosk and digital signage deployments on Linux.

%prep
%autosetup -n %{name}-%{version}

%build
export CARGO_NET_GIT_FETCH_WITH_CLI=true
cargo build --release

%package        kiosk
Summary:        Kiosk session scripts for Arexibo
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}
Requires:       gnome-kiosk-script-session
Requires:       dunst
Requires:       unclutter
Requires:       zenity
Requires:       opendoas
Requires:       keyd
Requires:       mesa-va-drivers
Requires:       libva
Recommends:     libva-intel-driver

%description    kiosk
Kiosk session scripts for running Arexibo as a full-screen digital signage
player under GNOME Kiosk. Includes a first-boot registration wizard,
session holder with health monitoring, dunst notification config, and
a systemd user unit for the player process.

%install
install -Dm755 target/release/arexibo %{buildroot}%{_bindir}/arexibo

# Kiosk scripts
install -Dm755 kiosk/gnome-kiosk-script.arexibo.sh %{buildroot}%{_datadir}/arexibo/kiosk/gnome-kiosk-script.arexibo.sh
install -Dm755 kiosk/gnome-kiosk-script.zenity.init.sh %{buildroot}%{_datadir}/arexibo/kiosk/gnome-kiosk-script.zenity.init.sh
install -Dm644 kiosk/dunstrc %{buildroot}%{_datadir}/arexibo/kiosk/dunstrc
install -Dm644 kiosk/arexibo-player.service %{buildroot}%{_userunitdir}/arexibo-player.service
install -Dm755 kiosk/arexibo-keyd-run.sh %{buildroot}%{_datadir}/arexibo/kiosk/arexibo-keyd-run.sh
install -Dm755 kiosk/arexibo-show-ip.sh %{buildroot}%{_datadir}/arexibo/kiosk/arexibo-show-ip.sh
install -Dm755 kiosk/arexibo-show-cms.sh %{buildroot}%{_datadir}/arexibo/kiosk/arexibo-show-cms.sh
install -Dm644 kiosk/keyd-arexibo.conf %{buildroot}%{_sysconfdir}/keyd/arexibo.conf

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/arexibo

%files          kiosk
%dir %{_datadir}/arexibo
%dir %{_datadir}/arexibo/kiosk
%{_datadir}/arexibo/kiosk/gnome-kiosk-script.arexibo.sh
%{_datadir}/arexibo/kiosk/gnome-kiosk-script.zenity.init.sh
%{_datadir}/arexibo/kiosk/dunstrc
%{_datadir}/arexibo/kiosk/arexibo-keyd-run.sh
%{_datadir}/arexibo/kiosk/arexibo-show-ip.sh
%{_datadir}/arexibo/kiosk/arexibo-show-cms.sh
%{_userunitdir}/arexibo-player.service
%{_sysconfdir}/keyd/arexibo.conf

%changelog
* Mon Jan 27 2026 Pau Aliagas <pau@linuxnow.com> - 0.3.1-2
- Add arexibo-kiosk subpackage with session scripts and systemd unit
- Fix exit code on error (exit 1 instead of 0)

* Sat Jan 18 2026 Pau Aliagas <pau@linuxnow.com> - 0.3.1-1
- Initial RPM package
