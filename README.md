# Arexibo

<p align="center">
  <img src="https://github.com/birkenfeld/arexibo/blob/master/assets/logo.png?raw=true" alt="Logo"/>
</p>

Arexibo is an unofficial alternate Digital Signage Player for [Xibo](https://xibo.org.uk),
implemented mostly in Rust but making use of Qt GUI components, for Linux platforms.

It is currently still incomplete.  Don't expect more complex features to work
unless tested.


## Installation

### RPM (Fedora 43)

Pre-built RPMs for x86_64 and aarch64 are available from the
[GitHub Releases](https://github.com/linuxnow/arexibo/releases) page,
or from the RPM repository:

```bash
# Add the repository
sudo tee /etc/yum.repos.d/arexibo.repo <<'EOF'
[arexibo]
name=Arexibo
baseurl=https://linuxnow.github.io/arexibo/rpm/fedora/43/$basearch/
enabled=1
gpgcheck=0
EOF

# Install
sudo dnf install arexibo
```

Or install directly from a downloaded RPM:

```bash
sudo dnf install ./arexibo-*.rpm
```

### Installer ISO (Recommended for physical hardware)

A bootable installer ISO is available from the
[GitHub Releases](https://github.com/linuxnow/arexibo/releases) page.
This performs an automated Fedora 43 installation with arexibo pre-configured.

```bash
# Flash ISO to USB
sudo dd if=arexibo-kiosk-installer_*_x86_64.iso of=/dev/sdX bs=8M status=progress

# Or use Balena Etcher
```

Alternatively, use any Fedora 43 netinstall ISO with the kickstart URL:

```bash
# At boot menu, press 'e' to edit and add to the linux line:
inst.ks=https://raw.githubusercontent.com/linuxnow/arexibo/master/kickstart/arexibo-kiosk.ks
# Then press Ctrl+X to boot
```

### Disk Images (Kiosk)

Ready-to-boot kiosk images are available from the
[GitHub Releases](https://github.com/linuxnow/arexibo/releases) page:

- **QCOW2** (x86_64): For VMs (GNOME Boxes, virt-manager, QEMU)
- **Raw.xz** (x86_64 / aarch64): For flashing to physical hardware

Default credentials: `xibo` / `xibo`

> **Change passwords after first login!**

```bash
# Test in QEMU
qemu-system-x86_64 -enable-kvm -m 2G -drive file=arexibo-kiosk_*_x86_64.qcow2

# Flash to hardware (use raw.xz)
xz -dc arexibo-kiosk_*_x86_64.raw.xz | sudo dd of=/dev/sdX bs=8M status=progress
```

Or use [Balena Etcher](https://etcher.balena.io/) which handles `.xz` files
automatically. After booting, a setup wizard will configure your Xibo CMS
connection.

### Building from Source

To build from source, you need:

* The [Rust toolchain](https://www.rust-lang.org/), version >= 1.75.  Refer to
  https://rustup.rs/ for the easiest way to install, if the Linux distribution
  provided package is too old.

* CMake and a C++ compiler.

* Qt 6 with the QtWebEngine component and its development headers.

* Development headers for `dbus` (>= 1.6), `zeromq` (>= 4.1)
  as well as `pkg-config`.

To build, run:

```
$ cargo build --release
```

The binary is placed in `target/release/arexibo` and can be run from there.

To install, run:

```
$ cargo install --path . --root /usr
```

The will install the binary to `/usr/bin/arexibo`.  It requires no other files
at runtime, except for the system libraries it is linked against.

Builds have been tested with the available dependency library versions on Fedora
41, RHEL 9 with EPEL and Ubuntu 24.04.  Note that in order to play some media
like mp4 videos, you will require a `ffmpeg` package that includes some codecs
that RHEL/Fedora don't include in their packages, e.g. from rpmfusion.org.

For RHEL derived distributions, install `cmake gcc-c++ cargo dbus-devel
zeromq-devel qt6-qtwebengine-devel`.  For Debian derived, install `cmake g++
cargo libdbus-1-dev libzmq3-dev qt6-webengine-dev`.

### Using Nix/NixOS

A Nix flake is provided for easy building and installation:

```bash
# Build the package
nix build

# Run directly
nix run

# Enter development shell with all dependencies
nix develop

# Install to profile
nix profile install
```

#### NixOS Module

A NixOS module is included for declarative configuration with systemd integration.

Add arexibo as a flake input and enable the module:

```nix
{
  inputs.arexibo.url = "github:linuxnow/arexibo";

  outputs = { nixpkgs, arexibo, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        arexibo.nixosModules.default
        {
          services.arexibo = {
            enable = true;
            host = "https://your-cms.example.com/";
            keyFile = "/run/secrets/arexibo-key";  # or key = "your-key";
            # displayName = "Lobby Display";
          };
        }
      ];
    };
  };
}
```

**Key options:**

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Enable the Arexibo service |
| `host` | string | CMS server URL (required) |
| `key` | string | Display key (mutually exclusive with `keyFile`) |
| `keyFile` | path | Path to file containing the key (for sops-nix/agenix) |
| `displayId` | string | Custom display ID (auto-generated if unset) |
| `displayName` | string | Initial display name |
| `dataDir` | path | Data directory (default: `/var/lib/arexibo`) |
| `xserver.enable` | bool | Run with a dedicated X server instance |

For secrets management, prefer `keyFile` over `key` so the key stays out of
the Nix store. This integrates with sops-nix or agenix:

```nix
services.arexibo.keyFile = config.sops.secrets.arexibo-key.path;
```


## Usage

Create a new directory where Arexibo can store configuration and media files.
Then, at first start, use the following command line to configure the player:

```
arexibo --host <https://my.cms/> --key <key> <dir>
```

Further configuration options are `--display-id` (which is normally
auto-generated from machine characteristics) and `--proxy` (if needed).

Arexibo will cache the configuration in the directory, so that in the future you
only need to start with

```
arexibo <dir>
```

Log messages are printed to stdout.  The GUI window will only show up once the
display is authorized.


## Standalone setup with X server

The following example systemd service file shows how to to start an X server
with Arexibo and no DPMS/screensaver:

```
[Unit]
Description=Start X with Arexibo player
After=network-online.target
Requires=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/xinit /usr/bin/arexibo /home/xibo/env -- :0 vt2 -s 0 -v -dpms
User=xibo
Restart=always
RestartSec=60
Environment=NO_AT_BRIDGE=1

[Install]
WantedBy=multi-user.target
```
