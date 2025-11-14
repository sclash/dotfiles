{
  description = "My first flake!";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

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

  # outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, ashell, ... }:
  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, elephant, walker,  ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      username = "asergi";
    in {
      nixosConfigurations = {
        nixos-os = lib.nixosSystem {
          inherit system;
          modules = [ ./configuration.nix ];
          specialArgs = {
            inherit username;
            inherit pkgs-unstable;
            inherit inputs;
          };
        };
      };
    };
}
