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
      # No ripwire source override (unlike nixos/flake.nix): pkgs-master's
      # ripwire is prebuilt on cache.nixos.org, while building the pinned
      # source compiles one huge LTO translation unit that exhausts the WSL VM.
      pkgs-master = import nixpkgs-master {
        inherit system;
        config.allowUnfree = true;
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
