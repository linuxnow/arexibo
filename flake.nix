{
  description = "Arexibo - An unofficial alternate Digital Signage Player for Xibo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Use the specific Rust version from rust-toolchain file
        rustVersion = "1.75.0";
        rust = pkgs.rust-bin.stable.${rustVersion}.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Qt and other native dependencies
        buildInputs = with pkgs; [
          # Qt dependencies
          qt6.full
          qt6.qtwebengine
          qt6.qtwayland  # Add Wayland support

          # System libraries
          dbus
          zeromq
          pkg-config

          # Build tools
          cmake
          gcc

          # Additional runtime dependencies
          ffmpeg
        ];

        nativeBuildInputs = with pkgs; [
          rust
          pkg-config
          cmake
          qt6.wrapQtAppsHook
        ];

      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "arexibo";
          version = "0.3.0";

          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;

          # Set environment variables for Qt development
          QT_QPA_PLATFORM_PLUGIN_PATH = "${pkgs.qt6.qtbase}/lib/qt-6/plugins";
          QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";

          # Set PKG_CONFIG_PATH for dependencies
          PKG_CONFIG_PATH = pkgs.lib.concatStringsSep ":" [
            "${pkgs.dbus.dev}/lib/pkgconfig"
            "${pkgs.zeromq}/lib/pkgconfig"
            "${pkgs.qt6.qtbase.dev}/lib/pkgconfig"
            "${pkgs.qt6.qtwebengine.dev}/lib/pkgconfig"
          ];

          # Set environment variables for Qt
          qtWrapperArgs = [
            "--prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs}"
          ];

          postInstall = ''
            wrapQtApp $out/bin/arexibo
          '';

          meta = with pkgs.lib; {
            description = "An unofficial alternate Digital Signage Player for Xibo";
            homepage = "https://github.com/linuxnow/arexibo";
            license = licenses.agpl3Plus;
            maintainers = [ ];
            platforms = platforms.linux;
            mainProgram = "arexibo";
          };
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
          buildInputs = nativeBuildInputs ++ buildInputs ++ (with pkgs; [
            # Additional development tools
            rust-analyzer
            cargo-watch
            cargo-edit
            clippy
            rustfmt

            # Debugging tools
            gdb
            valgrind
          ]);

          shellHook = ''
            echo "Arexibo development environment"
            echo "Rust version: ${rustVersion}"
            echo ""
            echo "Available commands:"
            echo "  cargo build --release  # Build the project"
            echo "  cargo run              # Run the project"
            echo "  cargo test             # Run tests"
            echo ""
            echo "Qt and other dependencies are available in the environment."

            # Set up environment for Qt development
            export QT_QPA_PLATFORM_PLUGIN_PATH="${pkgs.qt6.qtbase}/lib/qt-6/plugins"
            export QML2_IMPORT_PATH="${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
          '';
        };

        # Apps for easy running
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          name = "arexibo";
        };
      }) // {
        # NixOS module (not system-specific) - inline definition
        nixosModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.arexibo;

            # Use the arexibo package from nixpkgs or the flake
            arexibo = if (builtins.hasAttr "arexibo" pkgs)
                      then pkgs.arexibo
                      else throw "Arexibo package not available. Please ensure the flake overlay is imported or add arexibo to nixpkgs.";

            # Create the configuration script
            configScript = pkgs.writeShellScript "arexibo-config" ''
              set -e

              # Create the data directory if it doesn't exist
              mkdir -p ${cfg.dataDir}
              chown ${cfg.user}:${cfg.group} ${cfg.dataDir}
              chmod 755 ${cfg.dataDir}

              # Only run initial configuration if no config exists
              if [ ! -f "${cfg.dataDir}/.configured" ]; then
                echo "Running initial Arexibo configuration..."

                # Build the configuration command
                key_value=$(if [ -n "${cfg.keyFile}" ]; then cat "${cfg.keyFile}"; elif [ -n "${cfg.key}" ]; then echo "${cfg.key}"; else echo ""; fi)
                config_cmd="${arexibo}/bin/arexibo --host ${cfg.host} --key \"$key_value\""

                 ${optionalString (cfg.displayId != null) ''
                   config_cmd="$config_cmd --display-id ${cfg.displayId}"
                 ''}

                 ${optionalString (cfg.displayName != null) ''
                   config_cmd="$config_cmd --display-name ${cfg.displayName}"
                 ''}

                 ${optionalString (cfg.proxy != null) ''
                  config_cmd="$config_cmd --proxy ${cfg.proxy}"
                ''}

                config_cmd="$config_cmd ${cfg.dataDir}"

                # Run as the arexibo user
                su -s ${pkgs.bash}/bin/bash ${cfg.user} -c "$config_cmd" || {
                  echo "Initial configuration failed"
                  exit 1
                }

                # Mark as configured
                touch "${cfg.dataDir}/.configured"
                chown ${cfg.user}:${cfg.group} "${cfg.dataDir}/.configured"

                echo "Arexibo configuration completed"
              else
                echo "Arexibo already configured, skipping initial setup"
              fi
            '';
          in {

            ###### interface

            options.services.arexibo = {

              enable = mkEnableOption "Arexibo Digital Signage Player";

              host = mkOption {
                type = types.str;
                example = "https://my.cms.example.com/";
                description = ''
                  The URL of the Xibo CMS server that this player should connect to.
                  Must include the protocol (https:// or http://) and trailing slash.
                '';
              };

               key = mkOption {
                 type = types.nullOr types.str;
                 default = null;
                 example = "your-display-key-here";
                 description = ''
                   The display key for CMS authentication. Can be provided directly as a string.
                   Mutually exclusive with keyFile.
                 '';
               };

               keyFile = mkOption {
                 type = types.nullOr types.path;
                 default = null;
                 example = "/run/secrets/arexibo-key";
                 description = ''
                   Path to a file containing the display key for CMS authentication.
                   Mutually exclusive with key. Takes precedence over key if both are set.
                 '';
               };

               displayId = mkOption {
                 type = types.nullOr types.str;
                 default = null;
                 example = "custom-display-id";
                 description = ''
                   Custom display ID for this player. If not specified, one will be
                   auto-generated from machine characteristics.
                 '';
               };

               displayName = mkOption {
                 type = types.nullOr types.str;
                 default = null;
                 example = "My Digital Signage Display";
                 description = ''
                   Initial name for this display.
                 '';
               };

               proxy = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "http://proxy.example.com:8080";
                description = ''
                  HTTP proxy URL if needed for network access.
                '';
              };

              dataDir = mkOption {
                type = types.path;
                default = "/var/lib/arexibo";
                description = ''
                  Directory where Arexibo stores configuration and media files.
                  This directory will be created automatically with appropriate permissions.
                '';
              };

              user = mkOption {
                type = types.str;
                default = "arexibo";
                description = ''
                  User account under which Arexibo runs.
                '';
              };

              group = mkOption {
                type = types.str;
                default = "arexibo";
                description = ''
                  Group account under which Arexibo runs.
                '';
              };

              extraEnvironment = mkOption {
                type = types.attrsOf types.str;
                default = {
                  NO_AT_BRIDGE = "1";
                };
                example = {
                  NO_AT_BRIDGE = "1";
                  QT_QPA_PLATFORM = "xcb";
                };
                description = ''
                  Additional environment variables to set for the Arexibo service.
                '';
              };

              autoStart = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Whether to automatically start Arexibo on boot.
                '';
              };

              xserver = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Whether to run Arexibo with its own X server instance.
                    This is useful for dedicated signage displays.
                  '';
                };

                display = mkOption {
                  type = types.str;
                  default = ":0";
                  description = ''
                    X11 display number to use when running with dedicated X server.
                  '';
                };

                vt = mkOption {
                  type = types.str;
                  default = "vt2";
                  description = ''
                    Virtual terminal to use for the X server.
                  '';
                };

                extraArgs = mkOption {
                  type = types.listOf types.str;
                  default = [ "-s" "0" "-v" "-dpms" ];
                  description = ''
                    Additional arguments to pass to the X server.
                    Default disables screensaver and DPMS.
                  '';
                };
              };
            };


            ###### implementation

            config = mkIf cfg.enable {

              # Create user and group
              users.users.${cfg.user} = {
                isSystemUser = true;
                group = cfg.group;
                home = cfg.dataDir;
                createHome = true;
                description = "Arexibo Digital Signage Player user";
                # Add to video group for hardware acceleration if available
                extraGroups = [ "video" ];
              };

              users.groups.${cfg.group} = {};

              # Ensure required packages are available
              environment.systemPackages = [ arexibo ];

              # Configure systemd service
              systemd.services.arexibo = {
                description = "Arexibo Digital Signage Player";
                after = [ "network-online.target" ];
                requires = [ "network-online.target" ];
                wantedBy = mkIf cfg.autoStart [ "multi-user.target" ];

                # Run configuration before starting the main service
                preStart = configScript;

                serviceConfig = {
                  Type = "simple";
                  User = cfg.user;
                  Group = cfg.group;
                  Restart = "always";
                  RestartSec = "60";

                  # Security settings
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  ProtectHome = true;
                  ProtectSystem = "strict";
                  ReadWritePaths = [ cfg.dataDir ];

                  # Capabilities needed for display access
                  CapabilityBoundingSet = [ "CAP_SYS_TTY_CONFIG" ];
                  AmbientCapabilities = [ "CAP_SYS_TTY_CONFIG" ];
                } // (if cfg.xserver.enable then {
                  # Run with xinit when X server mode is enabled
                  ExecStart = ''
                    ${pkgs.xorg.xinit}/bin/xinit ${arexibo}/bin/arexibo ${cfg.dataDir} -- ${cfg.xserver.display} ${cfg.xserver.vt} ${concatStringsSep " " cfg.xserver.extraArgs}
                  '';
                } else {
                  # Run directly when using existing X server
                  ExecStart = "${arexibo}/bin/arexibo ${cfg.dataDir}";
                });

                environment = cfg.extraEnvironment // {
                  HOME = cfg.dataDir;
                };
              };

              # Configure X server dependencies if needed
              services.xserver = mkIf cfg.xserver.enable {
                enable = true;
                # Don't start display manager, we handle X server ourselves
                displayManager.startx.enable = true;
              };

               # Add configuration validation
               assertions = [
                 {
                   assertion = cfg.host != "";
                   message = "services.arexibo.host must be set to a valid CMS URL";
                 }
                 {
                   assertion = (cfg.key != null && cfg.key != "") || cfg.keyFile != null;
                   message = "Either services.arexibo.key or services.arexibo.keyFile must be set";
                 }
                 {
                   assertion = !(cfg.key != null && cfg.keyFile != null);
                   message = "services.arexibo.key and services.arexibo.keyFile are mutually exclusive";
                 }
                 {
                   assertion = hasPrefix "http" cfg.host;
                   message = "services.arexibo.host must start with http:// or https://";
                 }
               ];
            };

            meta = {
              maintainers = with lib.maintainers; [ ];
            };
          };

        nixosModules.arexibo = self.nixosModules.default;
      };
}
