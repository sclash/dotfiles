{
  description = "WSL home-manager configuration";

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
        # One LLVM for clang, clangd and lldb: nvim-lsp.nix's clang-tools would
        # otherwise pull a second LLVM (21.x) next to unstable's lldb (~1.4 GB).
        overlays = [
          (final: prev: { clang-tools = pkgs-unstable.llvmPackages_latest.clang-tools; })
        ];
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
      homeConfiguration = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home.nix
          sops-nix.homeManagerModules.sops
        ];
        extraSpecialArgs = { inherit pkgs-unstable pkgs-master; };
      };
    in
    {
      # The account is read from $USER/$HOME by home.nix, so the attribute name
      # is not tied to a username. Switch with --impure to feed it the real one.
      homeConfigurations.default = homeConfiguration;

      # Pinned tools for bootstrap.sh, usable before the first switch.
      packages.${system} = {
        home-manager = home-manager.packages.${system}.home-manager;
        sops = pkgs.sops;
        age = pkgs.age;
      };

      checks.${system} = {
        generation = pkgs.runCommand "hm-generation-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
          bash ${./tests/check-generation.sh} ${self.homeConfigurations.default.activationPackage} \
            ${pkgs.lib.escapeShellArg self.homeConfigurations.default.config.home.homeDirectory}
          touch $out
        '';
        overlay-links = import ./tests/overlay-links.nix { inherit pkgs; };
        overlay = pkgs.runCommand "overlay-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          bash ${./tests/check-overlay.sh} ${../my-opencode/v2} ${./opencode} ${./tests}
          touch $out
        '';
      };
    };
}
