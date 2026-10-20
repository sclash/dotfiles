{
  description = "asergi WSL home-manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    ripwire-src = {
      url = "github:redhat-et/ripwire/v0.6.1";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-master,
      home-manager,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      # Same ripwire override as nixos/flake.nix: build the pinned v0.6.1 source.
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
          })
        ];
      };
    in
    {
      homeConfigurations."asergi" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home.nix
          sops-nix.homeManagerModules.sops
        ];
        extraSpecialArgs = { inherit pkgs-unstable pkgs-master; };
      };

      checks.${system} = {
        generation = pkgs.runCommand "hm-generation-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
          bash ${./tests/check-generation.sh} ${self.homeConfigurations.asergi.activationPackage}
          touch $out
        '';
      };
    };
}
