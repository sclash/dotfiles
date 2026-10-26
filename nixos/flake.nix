{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    # nixpkgs.url = "github:nixos/nixpkgs";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    # flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-unstable";

    # home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.url = "github:nix-community/home-manager";
    # home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixd.url = "github:nix-community/nixd";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # my-dotfiles.url = "https://github.com/sclash/dotfiles";
    # my-dotifiles.inputs = { ref = "master"; };
    # my-dotfiles.url = "github:sclash/dotfiles";

    my-dotfiles = {
      url = "github:sclash/dotfiles?ref=quickshell";
      # url = "github:sclash/dotfiles?ref=home-manager";
      # url = "https://github.com/sclash/dotfiles?ref=master";
      # `rev` pins to a specific commit
      # `ref` pins to a branch (optional, defaults to default branch)
      flake = false; # if the repo is not a flake
      # ref = "master";  # track master branch
    };

    neovimrc = {
      url = "github:sclash/neovimrc?ref=native";
      # url = "github:sclash/neovimrc?ref=master";
      # url = "https://github.com/sclash/neovimrc?ref=master";
      flake = false; # if the repo is not a flake
    };
    #    ashell = {
    # url = "github:MalpenZibo/ashell";
    #    };
    #
    elephant = {
      url = "github:abenz1267/elephant";
    };

    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };

    ripwire-src = {
      url = "github:redhat-et/ripwire/v0.6.1";
      flake = false;
    };

    opencode-src = {
      url = "github:anomalyco/opencode/v1.18.31";
      flake = false;
    };

  };

  # outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, flake-parts, home-manager
  #   , nixd, elephant, walker, my-dotfiles, neovimrc, ... }:
  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-master,
      home-manager,
      my-dotfiles,
      # neovimrc,
      nixd,
      sops-nix,
      ...
    }:

    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      # pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      # pkgs-master = nixpkgs-master.legacyPackages.${system};
      pkgs-unstable = import nixpkgs-unstable {
        # <-- changed
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-master = import nixpkgs-master {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (final: prev: {
            ripwire = prev.ripwire.overrideAttrs (finalAttrs: prevAttrs: {
              version = builtins.head (
                builtins.match ".*project\\(ripwire VERSION ([0-9]+\\.[0-9]+\\.[0-9]+).*" (
                  builtins.readFile "${inputs.ripwire-src}/CMakeLists.txt"
                )
              );
              src = inputs.ripwire-src;
            });
            # opencode = prev.opencode.overrideAttrs (finalAttrs: prevAttrs: {
            #   version =
            #     (builtins.fromJSON (
            #       builtins.readFile "${inputs.opencode-src}/packages/opencode/package.json"
            #     )).version;
            #   src = inputs.opencode-src;
            #   passthru = prevAttrs.passthru // {
            #     node_modules = prevAttrs.passthru.node_modules.overrideAttrs (old: {
            #       outputHash = "sha256-3BXy+zxgav8IZCBtMS3cUZc3Vq/1WPQ8msGriwxUXmw=";
            #     });
            #   };
            # });
          })
        ];
      };
      user = import ../lib/user.nix;
      inherit (user) username homeDirectory dotfiles;

    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      debug = true;
      systems = [ system ];
      perSystem =
        { pkgs, ... }:
        {
          checks.generation = pkgs.runCommand "nixos-generation-check" { } ''
            bash ${./tests/check-generation.sh} \
              ${pkgs.lib.escapeShellArg self.nixosConfigurations.nixos-os.config.home-manager.users.${username}.home.activationPackage} \
              ${pkgs.lib.escapeShellArg self.homeConfigurations.default.config.home.homeDirectory} \
              ${pkgs.lib.escapeShellArg self.nixosConfigurations.nixos-os.config.sops.age.keyFile} \
              ${../my-opencode/v2/opencode.jsonc}
            touch $out
          '';

          checks.portable = pkgs.runCommand "nixos-portable-check" { } ''
            bash ${./tests/check-generation.sh} \
              ${pkgs.lib.escapeShellArg self.homeConfigurations.check.activationPackage} \
              ${pkgs.lib.escapeShellArg "/tmp/checkuser"} \
              ${pkgs.lib.escapeShellArg "/tmp/checkuser/.config/sops/age/keys.txt"} \
              ${../my-opencode/v2/opencode.jsonc}
            touch $out
          '';

          checks.identity =
            assert self.nixosConfigurations.nixos-os.config.users.users.${username}.home == homeDirectory;
            assert self.nixosConfigurations.nixos-os.config.services.greetd.settings.initial_session.user == username;
            assert self.nixosConfigurations.nixos-os.config.sops.secrets.github_pat.owner == username;
            assert builtins.hasAttr username self.nixosConfigurations.nixos-os.config.home-manager.users;
            pkgs.runCommand "nixos-identity-check" { } "touch $out";
        };

      flake = {

        nixosConfigurations = {
          nixos-os = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              ./configuration.nix
              inputs.sops-nix.nixosModules.sops

              {
                nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
                nixpkgs.overlays = [ nixd.overlays.default ];
                environment.systemPackages = with pkgs; [ nixd ];
              }

              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.${username} = ./home.nix;
                home-manager.extraSpecialArgs = {
                  inherit my-dotfiles;
                  # inherit neovimrc;
                  inherit pkgs-unstable;
                  inherit pkgs-master;
                  inherit (user) username homeDirectory dotfiles;
                };
                # home-manager.backupCommand = "mv $source $target";
                # home-manager.backupCommand = "false";
                # home-manager.backupFileExtension = "hm-backup";
                # home-manager.overwriteBackup = true;

                # Optionally, use home-manager.extraSpecialArgs to pass
                # arguments to home.nix
              }
            ];
            specialArgs = {
              inherit (user) username homeDirectory dotfiles;
              inherit pkgs-unstable;
              inherit inputs;
            };
          };
        };

        homeConfigurations = {
          default = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            modules = [
              ./home.nix
              {
                home.username = username;
                home.homeDirectory = homeDirectory;
                nix.package = pkgs.nix;
              }
            ];
            extraSpecialArgs = {
              inherit my-dotfiles;
              inherit pkgs-unstable pkgs-master;
              inherit (user) username homeDirectory dotfiles;
            };
          };
          check = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            modules = [
              ./home.nix
              {
                home.username = "checkuser";
                home.homeDirectory = "/tmp/checkuser";
                nix.package = pkgs.nix;
              }
            ];
            extraSpecialArgs = {
              inherit my-dotfiles pkgs-unstable pkgs-master;
              username = "checkuser";
              homeDirectory = "/tmp/checkuser";
              dotfiles = "/tmp/checkuser/dotfiles";
            };
          };
        };
      };
    };

}
