# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  inputs,
  pkgs,
  pkgs-unstable,
  nixd,
  username,
  homeDirectory,
  ...
}:
{
  disabledModules = [
    "services/misc/elephant.nix"
  ];
  imports = [
    # The machine layer (hardware scan, bootloader, hostname, ...) is added by
    # flake.nix from /etc/nixos.
    # ./tmux.nix
    ./sops.nix
    ./hardware-devices/printers.nix
    ./hardware-devices/scanners.nix
    ./hardware-devices/fingerprint.nix
    ./hardware-devices/face.nix
    inputs.walker.nixosModules.default
    # inputs.elephant.nixosModules.default
    inputs.nixd.nixosModules
  ];

  # programs.nixd = {
  #   enable = true;
  #   # packages = with pkgs-unstable; [ nixd ];
  #   # inputs.walker.packages.${pkgs.system}.default
  # };

  documentation.dev.enable = true;

  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
  environment.variables.SUDO_EDITOR = "nvim";
  environment.variables.EDITOR = "nvim";
  environment.variables.VISUAL = "nvim";

  programs.walker = {
    enable = true;
  };
  nixpkgs.config.allowUnfree = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.tmp.cleanOnBoot = true;

  programs.wshowkeys.enable = true;

  # Enable Avahi (Bonjour) for network discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;      # Allows resolving .local hostnames
    openFirewall = true;  # Opens UDP port 5353 for mDNS discovery
  };
  # networking.wireless is left unset: with the default wpa_supplicant backend
  # the NetworkManager module enables wpa_supplicant itself (dbusControlled).
  # networking.wireless.iwd.enable = true; # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.networkmanager.wifi.powersave = false;
  networking.networkmanager.wifi.scanRandMacAddress = false;
  # wifi backend defaults to wpa_supplicant: iwd renamed the interface
  # (wlp1s0 -> wlan0), breaking existing connection profiles, and failed
  # SAE handshakes against WPA3-transition hotspots.
  # VPN types the Quickshell Network Center offers (/vpn); WireGuard is
  # built into NetworkManager.
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
    networkmanager-strongswan
    networkmanager-l2tp
  ];
  services.strongswan.enable = true;
  # charon-nm (the strongSwan plugin's daemon, started over D-Bus) and nm-l2tp's
  # IPsec starter both read /etc/strongswan.conf and abort when it is
  # missing; services.strongswan points its own charon at a store file
  # instead, so nothing creates it.
  # Empty means strongSwan's defaults; charon-nm then uses random IKE ports,
  # so it runs beside services.strongswan (checked by nixos/tests/test-vpn-vm.sh).
  environment.etc."strongswan.conf".text = "";
  # L2TP/IPsec can only negotiate with IKEv1, and strongSwan 6 builds without
  # it unless --enable-ikev1 is given (its charon then logs "IKE version 1 not
  # supported"). The overlay reaches networkmanager-l2tp, the strongSwan
  # plugin and services.strongswan alike. strongSwan marks IKEv1 deprecated
  # and plans to remove it; when that happens, L2TP/IPsec needs another
  # IPsec daemon. Checked by nixos/tests/test-vpn.sh and test-vpn-vm.sh.
  nixpkgs.overlays = [
    (final: prev: {
      strongswan = prev.strongswan.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-ikev1" ];
      });
    })
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono ];
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-color-emoji
    ];
    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "JetBrainsMono Nerd Font" ];
        sansSerif = [ "JetBrainsMono Nerd Font" ];
        serif = [ "JetBrainsMono Nerd Font" ];
      };
    };
  };

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #  # font = "Lat2-Terminus16";
  #  lib.mkDefault.keyMap = "it";
  #  useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  # services.displayManager.sddm.wayland.enable = true;
  # services.displayManager.sddm.enable = true;
  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        # command = "hyprland > /dev/null 2>&1";
        # command = "start-hyprland";
        command = "uwsm start hyprland.desktop";
        user = username;
        shell = pkgs.zsh;
      };
      default_session = initial_session;
    };
  };

  xdg.portal = {
    enable = true;
    # Use xdg-desktop-portal-gtk to handle GSettings for GTK apps like Firefox.
    # It must be in extraPortals for Hyprland to use it for settings.
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    # Explicit portal routing: file dialogs (FileChooser) via gtk portal so all
    # apps (Chrome, Firefox, Qt apps) get the same dialog; hyprland keeps
    # ScreenCast/Screenshot.
    config = {
      common.default = [ "gtk" ];
      hyprland = {
        "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
      };
    };
  };
  # Provides the system dconf profile so GTK/libadwaita apps read the user
  # database written by home-manager's dconf.settings (home.nix).
  programs.dconf.enable = true;

  # services.wayland.windowManager.hyprland.systemd.enable = true;
  # wayland.windowManager.hyprland.systemd.enable = true;
  programs.hyprland = {
    enable = true;
    package = pkgs-unstable.hyprland;
    withUWSM = true;
    # xwayland.enable = true;
    systemd.setPath.enable = true;
  };
  programs.hyprlock = {
    enable = true;
  };
  security.pam.services.hyprlock.enable = true;

  # Polkit password prompts (pkexec, udisks, the Identity Manager's face
  # models) come from Quickshell itself (quickshell/services/PolkitService.qml):
  # it is the session's authentication agent, so prompts appear inside the
  # shell. A session has one agent, so no hyprpolkitagent alongside it.

  # GTK theming is set declaratively via dconf in home.nix. Do NOT set
  # GTK_THEME here: it takes precedence over the gtk-theme GSettings key and
  # would override adw-gtk3-dark for GTK3 apps.
  environment.variables = {
    XCURSOR_THEME = "Adwaita";
    XDG_CURRENT_DESKTOP = "Hyprland";
    GTK_APPLICATION_PREFER_DARK_THEME = "1";
    GTK_USE_PORTAL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    NIXOS_OZONE_WL = "1";
  };

  hardware = {

    # opengl.enable = true;
    graphics.enable = true;
    # /dev/i2c-* for ddcutil (external monitor brightness); grants seated users access
    i2c.enable = true;
  };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "it";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = false;
  services.upower.enable = true;
  # Power saver, balanced and performance modes: `powerprofilesctl set <mode>`.
  # Don't add TLP or auto-cpufreq alongside it, because they conflict.
  services.power-profiles-daemon.enable = true;
  services.fwupd.enable = true; # firmware updates, on any machine with LVFS support
  services.udisks2.enable = true;   # udisksctl backend for UsbService (quickshell USB-Manager)

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.root = {
    shell = pkgs.zsh;
  };

  users.users.${username} = {
    isNormalUser = true;
    home = homeDirectory;
    extraGroups = [
      "input"
      "wheel"
      "docker"
      "wireshark"
      "networkmanager"
      "i2c"
    ]; # Enable ‘sudo’ for the user.
    # shell = pkgs.zsh;
    # packages = with pkgs; [ tree ];
  };

  virtualisation.docker.enable = true;

  programs.zsh = {
    enable = true;
    promptInit = ''
                  	eval "$(starship init zsh)"
                   	eval "$(atuin init zsh)"
      		'';
  };
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
    usbmon.enable = true;
    dumpcap.enable = true;
  };
  # programs.zsh = {
  #   enable = true;
  #   enableCompletion = true;
  #   autosuggestions.enable = true;
  #   syntaxHighlighting.enable = true;
  #
  #   shellAliases = {
  #     ll = "ls -l";
  #     edit = "sudo -e";
  #     update = "sudo nixos-rebuild switch --flake /etc/nixos";
  #     ftm = "~/tmux-sessionizer.sh";
  #   };
  #
  #   ohMyZsh = { # "ohMyZsh" without Home Manager
  #     enable = true;
  #     plugins = [ "git" ];
  #     # theme = "robbyrussell";
  #     # theme = "powerlevel10k";
  #   };
  #   histSize = 10000;
  #   histFile = "$HOME/.zsh_history";
  #   setOptions = [ "HIST_IGNORE_ALL_DUPS" ];
  #   promptInit = ''
  #           # this act as your ~/.zshrc but for all users (/etc/zshrc)
  #           source "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme"
  #           # source /etc/powerlevel10k/p10k.zsh
  #
  #           # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
  #           # Initialization code that may require console input (password prompts, [y/n]
  #           # confirmations, etc.) must go above this block; everything else may go below.
  #           if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
  #             source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
  #           fi
  #
  #
  #     show_eza_tree() {
  #     	level_arg=''${1:-2}
  #     	eza --tree --level="$level_arg" --long --icons --git
  #     }
  #
  #     alias lz='show_eza_tree'
  #
  #           # uncomment if you want to customize your LS_COLORS
  #           # https://manpages.ubuntu.com/manpages/plucky/en/man5/dir_colors.5.html
  #           #LS_COLORS='...'
  #           #export LS_COLORS
  #   '';
  # };
  users.defaultUserShell = pkgs.zsh;
  # system.userActivationScripts.zshrc ="touch .zshrc"; # to avoid being prompted to generate the config for first time

  # environment.shells = pkgs.zsh; # https://wiki.nixos.org/wiki/Zsh#GDM_does_not_show_user_when_zsh_is_the_default_shell
  # environment.loginShellInit = ''
  # equivalent to .profile
  #   # https://search.nixos.org/options?show=environment.loginShellInit
  # '';

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries =
    (with pkgs; [ stdenv.cc ])

    ++

      (with pkgs-unstable; [
        # uv
      ]);

  environment.systemPackages =
    (with pkgs; [
      vim
      neovim
      tree-sitter
      tree
      sops
      # nixd

      bat
      zip
      unzip
    ])

    ++

      ## scanner utility (printer drivers live under services.printing.drivers).
      ## withNonFreePlugins provides the network scanning module; without it
      ## the GUI cannot discover network scanners.
      lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.epsonscan2)
        (pkgs.epsonscan2.override { withNonFreePlugins = true; })

    ++

    (with pkgs; [
      chromium
      chromedriver
      undetected-chromedriver
      google-chrome

      firefox-bin
      # git
      nix-prefetch-git
      lazygit
      btop
      htop
      # needed by flameshot + xdg-desktop-portal-hyprland (Screenshot portal)
      grim
      slurp
      wget
      # kitty
      xorg.xrandr
      # gtkd
      pkg-config
      # wofi
      nautilus
      gnome-themes-extra
      # required by gsettings gtk-theme "adw-gtk3-dark" (hyprland.conf) —
      # makes xdg portal file dialogs + GTK3 popups render dark
      adw-gtk3
      # gnome-control-center
      # nwg-look
      evince

      # nodejs
      # nodePackages.typescript

      # llvmPackages.clang
      # llvmPackages.clang-tools
      # llvmPackages.libclang

      llvmPackages_latest.lldb
      llvmPackages_latest.libllvm
      llvmPackages_latest.libcxx
      llvmPackages_latest.clang
      gcc
      glib
      glibc
      libgcc
      bear
      gdb
      rr
      perf
      hyperfine
      gnumake
      valgrind

      lua

      dbus

      zoxide
      bat

      docker
      docker-compose
      docker-compose-language-service

      # sway
      # waybar
      hyprpicker
      hyprpaper
      hyprlock
      wlr-randr
      pywal
      # swaynotificationcenter

      gvfs
      libnotify
      # inputs.ashell.defaultPackage.${pkgs.system}
      # inputs.elephant.packages.${pkgs.system}.default

      inputs.walker.packages.${pkgs.system}.default
      inputs.elephant.packages.${pkgs.system}.default
      lm_sensors
      upower
      bluez
      bluez-tools
      wireplumber
      networkmanager
      util-linux
      inputs.nixd.packages.${pkgs.system}.default

      # tmux
      # zellij

      # zsh
      # oh-my-zsh
      # zsh-autosuggestions
      # zsh-history
      # zsh-powerlevel10k

      fd
      jq
      starship
      xclip
      wl-clipboard
    ])

    ++

      (with pkgs-unstable; [

        ghostty
        ripgrep
        fzf
        universal-ctags

        # uv
        python3
        bun
        go
        # rustup
        rustc
        cargo
        zig
        # inputs.nixd.packages.${pkgs.system}.default
      ]);

  # nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = false;

  # system.stateVersion is per machine: it lives in /etc/nixos/machine.nix.
}
