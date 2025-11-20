# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, inputs, pkgs, pkgs-unstable, home-manager, ... }:

{
  imports = [ # Include the results of the hardware scan.
    # ./hardware-configuration.nix

    # builtins.readFile "/etc/nixos/hardware-configuration.nix"
    /etc/nixos/hardware-configuration.nix
    # ./tmux.nix
    inputs.walker.nixosModules.default
  ];

  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
  environment.variables.SUDO_EDITOR = "nvim";
  environment.variables.EDITOR = "nvim";
  environment.variables.VISUAL = "nvim";

  programs.sway = { enable = true; };

  programs.walker = { enable = true; };
  nixpkgs.config.allowUnfree = true;
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-os"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable =
    true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Amsterdam";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono ];

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
        command = "hyprland > /dev/null 2>&1";
        user = "asergi";
      };
      default_session = initial_session;
    };
  };

  xdg.portal = {
    enable = true;
    # Use xdg-desktop-portal-gtk to handle GSettings for GTK apps like Firefox.
    # It must be in extraPortals for Hyprland to use it for settings.
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  programs.hyprland = {
    enable = true;
    # withUWSM = true;
    xwayland.enable = true;
  };
  programs.hyprlock = { enable = true; };
  security.pam.services.hyprlock.enable = true;

  # Optional: set GTK theme globally via environment variables
  environment.variables = {
    GTK_THEME = "Adwaita-dark";
    # GTK_THEME = "Materia-dark";
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
    nvidia.modesetting.enable = true;
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
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.asergi = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [ tree ];
  };
  programs.firefox.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      edit = "sudo -e";
      update = "sudo nixos-rebuild switch --flake /etc/nixos";
      ftm = "~/tmux-sessionizer.sh";
    };

    ohMyZsh = { # "ohMyZsh" without Home Manager
      enable = true;
      plugins = [ "git" ];
      # theme = "robbyrussell";
      # theme = "powerlevel10k";
    };
    histSize = 10000;
    histFile = "$HOME/.zsh_history";
    setOptions = [ "HIST_IGNORE_ALL_DUPS" ];
    promptInit = ''
            # this act as your ~/.zshrc but for all users (/etc/zshrc)
            source "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme"
            # source /etc/powerlevel10k/p10k.zsh

            # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
            # Initialization code that may require console input (password prompts, [y/n]
            # confirmations, etc.) must go above this block; everything else may go below.
            if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
              source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
            fi


      show_eza_tree() {
      	level_arg=''${1:-2}
      	eza --tree --level="$level_arg" --long --icons --git
      }

      alias lz='show_eza_tree'

            # uncomment if you want to customize your LS_COLORS
            # https://manpages.ubuntu.com/manpages/plucky/en/man5/dir_colors.5.html
            #LS_COLORS='...'
            #export LS_COLORS
    '';
  };
  users.defaultUserShell = pkgs.zsh;
  system.userActivationScripts.zshrc =
    "touch .zshrc"; # to avoid being prompted to generate the config for first time
  # environment.shells = pkgs.zsh; # https://wiki.nixos.org/wiki/Zsh#GDM_does_not_show_user_when_zsh_is_the_default_shell
  # environment.loginShellInit = ''
  #   # equivalent to .profile
  #   # https://search.nixos.org/options?show=environment.loginShellInit
  # '';

  # programs.tmux = {
  #   enable = true;
  #   # extraConfig = ''
  #   #     set-option -g default-shell "''${pkgs.zsh}";
  #   #   '';
  #   plugins = with pkgs; [
  #   	pkgs.tmuxPlugins.tilish
  #   ];
  # };

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = (with pkgs; [ ])

    ++

    (with pkgs-unstable; [ uv ]);

  environment.systemPackages = (with pkgs; [
    vim
    neovim
    tree-sitter

    bat
    unzip
    google-chrome
    git
    lazygit
    ghostty
    btop
    htop
    wget
    kitty
    xorg.xrandr
    gtkd
    pkg-config
    wofi
    nautilus
    gnome-themes-extra
    # gnome-control-center
    nwg-look

    nodejs
    gcc
    glibc
    llvmPackages_latest.lldb
    llvmPackages_latest.libllvm
    llvmPackages_latest.libcxx
    llvmPackages_latest.clang
    clang
    clang-tools
    libclang
    liggcc
    bear
    gdb

    dbus

    zoxide
    bat

    docker

    sway
    waybar
    hyprpicker
    hyprpaper
    hyprlock
    pywal
    swaynotificationcenter
    yay
    gvfs
    libnotify
    # inputs.ashell.defaultPackage.${pkgs.system}
    # inputs.elephant.packages.${pkgs.system}.default

    inputs.walker.packages.${pkgs.system}.default

    # tmux
    zellij

    zsh
    oh-my-zsh
    zsh-autosuggestions
    zsh-history
    zsh-powerlevel10k
  ])

    ++

    (with pkgs-unstable; [
      ripgrep
      fzf
      universal-ctags

      gemini-cli

      uv
      python3
      bun
      go
      rustup
      rustc
      zig
    ]);

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  #   environment.systemPackages = with pkgs; [
  #     	vim 
  # neovim
  # unzip
  # # dconf
  # google-chrome
  # git
  # lazygit
  # ghostty
  # btop
  # htop
  #        wget
  # kitty
  # xorg.xrandr
  # gtkd
  # wofi
  # nautilus
  #    	gnome-themes-extra
  #    	gnome-control-center
  #    	nwg-look
  #    # pkgs.waybar
  #    # pkgs.eww
  #    # libnotify
  #    # pkgs.dunst
  #    # xdg-desktop-portal
  #    # xdg-desktop-portal-hyprland
  #   ];

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

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .

  system.stateVersion = "25.05"; # Did you read the comment?
}
