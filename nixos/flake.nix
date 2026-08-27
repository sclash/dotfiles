{
  description = "NixOS asergi cofniguration";

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
      url = "github:sclash/dotfiles?ref=home-manager";
      # url = "https://github.com/sclash/dotfiles?ref=master";
      # `rev` pins to a specific commit
      # `ref` pins to a branch (optional, defaults to default branch)
      flake = false; # if the repo is not a flake
      # ref = "master";  # track master branch
    };

    neovimrc = {
      url = "github:sclash/neovimrc?ref=master";
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
      neovimrc,
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
      };
      username = "asergi";

    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      debug = true;
      systems = [ system ];
      perSystem = { config, ... }: { };

      flake = {

        nixosConfigurations = {
          nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
          nixos-os = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              ./configuration.nix
              inputs.sops-nix.nixosModules.sops

              {
                # nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
                nixpkgs.overlays = [ nixd.overlays.default ];
                environment.systemPackages = with pkgs; [ nixd ];
              }

              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.asergi = ./home.nix;
                home-manager.extraSpecialArgs = {
                  inherit my-dotfiles;
                  inherit neovimrc;
                  inherit pkgs-unstable;
                  inherit pkgs-master;
                };
                # home-manager.backupCommand = "mv $source $target";
                # home-manager.backupCommand = "false";
                home-manager.backupFileExtension = "hm-backup";
                home-manager.overwriteBackup = true;

                # Optionally, use home-manager.extraSpecialArgs to pass
                # arguments to home.nix
              }
            ];
            specialArgs = {
              username = "asergi";
              inherit pkgs-unstable;
              inherit inputs;
            };
          };
        };

        homeConfigurations = {
          "asergi@nixos-os" = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            # pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
            # imports = [ ./home.nix ];
            modules = [
              ./home.nix
              {
                home.stateVersion = "25.11";
                # home.stateVersion = "25.05";
                home.username = "asergi";
                home.homeDirectory = "/home/asergi";
                nix.package = pkgs.nix;
                # nix.package = pkgs-unstable.nix;
              }
            ];
            extraSpecialArgs = {
              inherit my-dotfiles;
              inherit neovimrc;
              # inherit pkgs;
              # inherit pkgs-unstable;
            };

          };
        };
      };
    };

}
