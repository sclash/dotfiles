I want to use the nixos home-manager to handle all the programs and their relative configuration
in a declarative way in WSL. We need to port the current user configuration conatined 
in "../nixos" directory to make it work with any new brand instance of WSL.
The programs that we want to port are of course the binaries cli and tui tools and the relative configurations
All the other applications say like firefox of course we don't want as they won't work inside WSL.
The important caveat is that we want opencode not installed through the home-manger. But we want to use 
the nix home-manager for sourcing the configuration from ~/dotfiles/my-opencode/v2.
Before starting give an assesment of the feasibility of the task at hand:
1. which app we will port?
2. are there apps that are already installed in the present wsl instance?
3. Are there any potential conflicts that might arise?

We want to have a flake.nix.
