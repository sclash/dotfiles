# Dotfiles for custom configuration

This respository contains all the dotfiles, the steps needed, and any useful references for customizng Tmux, i3wm, alacritty and zsh in a Linux (Debian / Arch) environment.

The dotfiles for neovim are contained in a separate Repo: [ neovimrc ]( https://github.com/sclash/neovimrc )


- [NixOs](#NixOS)
    - [Installation](#nixos-installation)
    - [Network](#nixos-network)
    - [Dotfiles](#dotfiles)
- [Alacritty](#alacritty)
- [i3](#i3-window-manger)
    - [Dependencies](#i3-dependencies)
    - [Installation](#i3-installation)
        - [Debian](#installation-debian)
        - [Arch](#installation-arch)
    - [Configuration](#i3-configuration)
        - [Debian](#configuration-debian)
        - [Arch](#configuration-arch)
    - [Useful references](#i3-useful-referencese)
- [ZSH](#zsh)
    - [Dependencies](#zsh-dependencies)
    - [Installation](#zsh-installation)
    - [Configuration](#zsh-configuration)
        - [Plugin Manager](#zsh-plugin-manager)
        - [Plugins](#zsh-plugins)
    - [Useful references](#zsh-useful-referencese)
- [Tmux](#tmux)
    - [Installation](#tmux-installation)
    - [Configuration](#tmux-configuration)
        - [Plugin Manager](#tmux-plugin-manager)
        - [Plugins](#tmux-plugins)
- [Custom Scripts](#custom-scripts)
    - [Tmux Sessionizer](#tmux-sessionizer)
- [Misc](#misc)
    - [Network](#network)
    - [Keyboard layout](#keyboard-layout)
    - [Picom](#picom)
    - [Docker](#Docker)
    - [Ethernet](#Ethernet)
    - [USB Drive](#usb-drive)

## NixOS

Inside the `nixos` directory there are the `configuration.nix` and `flake.nix` files.

### Installation
To install NixOs refer to the [ official guide ](https://nixos.org/manual/nixos/stable/#ch-installation) then cd inside the `~/dotfiles/nixos` directory and run 
```bash
sudo nixos-generate-config
cd /mnt/nixos
sudo cp hardware-configuration.nix ~/dotfiles/nixos
cd ~/dotfiles/nixos
sudo nixos-install --flake .#nixos-os --root
reboot
```

### Network
Use `nmcli`
```bash
nmcli device wifi connect <ssid> <password>
```
### Dotfiles

To update the NixOS configuration we can work in the directory in which this repo is cloned.
The `flake.nix` and `home.nix` files tracks the `master` branch of this repo
After having made changes to the repo staged and commited them, To update the system
```bash
cd ~/dotfiles/nixos #provided this repo has been cloned in ~/
sudo nixos-rebuild switch --flake .#nixos-os --impure
```
if you encounter any problem copy the `hardware-configuration.nix` and `flake.nix` from `/etx/nixos` to `~/dotfiles/nixos` and try again

## Alacritty

> Alacritty is the my default terminal emulator of choice. the `i3` config files are already set to use `Alacritty` as such. the Keyboard shortcut for `Alacritty` is `$mod+<Enter>`

> This step is fundemental to setup both `i3` and `ZSH` in the next sections

- The default configuration directorty is: `~/.config/alacritty`
- The default configuration file is: `~/.config/alacritty/config.yaml` or `~/.config/alacritty/config.toml` depending on the  `Alacritty` version. (New version require `.toml`, which can be easily migrated for the `.yaml`)

Copy the `Alacritty` config files inside this Repo in the paths specified above, create the Files/Directories if they do not yet exist

## i3 Window Manger 

Custom configuration for i3 tiling Window Manager

**NOTE:**  the present configuration for i3 works perfectly on Arch, on Ubuntu there will be problems as the version currently supported by Debian is older and allows less room for customization

The Ubuntu version currently do not support gap between windows, and does not allow for a heavy customization of the status bar. To avoid any errors comment out this parts.

### i3 Dependencies

Install the dependencies either by `apt` / `snap` for Debian or by `pacman` / `yay` for Arch

```bash
xss-lock
i3lock
i3lock-fancy
lxappearance
picom 
feh
materia-gtk-theme
sudo pacman -S ttf-font-awesome
sudo apt instal fonts-font-awesome
sudo pacman -S ttf-ubuntu-font-family
```
### i3 Installation

***Install i3***

#### Installation Debian
```bash
sudo apt install xorg lightdm lightdm-gtk-greeter i3-wm i3lock i3status i3blocks dmenu terminator
sudo systemctl enable lightdm.service
sudo systemctl start lightdm.service
```

#### Installation Arch
```bash
sudo pacman -S xorg lightdm lightdm-gtk-greeter i3-wm i3lock i3status i3blocks dmenu terminator
sudo systemctl enable lightdm.service
sudo systemctl start lightdm.service
```
In Arch before proceeding is best to install `yay` to allow the installation of `AUR` packages. Which are needed for a proper configuration. 

**NOTE:** `yay` needs to be built from his official git repository, hence we need to install git first.

```bash
sudo pacman -S git
git clone https://aur.archlinux.org/yay-git.git && cd yay
makepkg -si
```

### i3 Configuration
- The default configuration directorty is: `~/.config/i3`
- The default configuration file is: `~/.config/i3/config`
- The default configuration file for the status-bar is: `~/.config/i3/i3status/i3status.conf`

**NOTE:** if the following paths/files do not yet exist create them

#### Custom Fonts and Icons
Some fonts and icons are already part od the Dependencies, however if you wish to install some custom fonts not yet available on a package manager you can proceed in the following way

- Downlaod `JetBrains Mono Nerd Font` from [NerdFont](https://www.nerdfonts.com/font-downloads)
- Downlaod the Official `JetBrains Mono Font` from [JetBrains](https://www.jetbrains.com/lp/mono/)

Install the font by unpacking your preferred font in `/usr/share/fonts` or in `~/.local/share/fonts` (if you want to make the font available just for the current user)

#### Configuration Debian
If Ubuntu is already installed some minimum configuration settings are already inherited, however we can still change themes by calling `lxappearance` from terminal.

Copy the i3 config files inside this Repo into the default config i3 paths specified above. Refresh by `$mod+Shift+r` to see your i3 winow manager updated with the settings of your choice.

`!!!` See the note at the start of the section if any problem occours

#### Configuration Arch
Copy the i3 config files inside this Repo into the default config i3 paths specified above. Refresh by `$mod+Shift+r` to see your i3 winow manager updated with the settings of your choice.

### i3 Useful referencese
[ The Ultimate Guide to i3 Customization in Linux ](https://itsfoss.com/i3-customization/)



## ZSH

- The default configuration file is: `~/.zshrc`

A default `.zshrc` file can be generated when zsh run for the first time, and then modified.
Otherwise create it and start from scratch.
### ZSH Dependencies
[eza](https://github.com/eza-community/eza) Display file tree with icons and details, to install it 
```bash
yay -S eza-git
```

### ZSH Installation

```bash
sudo snap zsh
sudo pacman -S zsh
```
### ZSH Configuration

> Before copying the config file in this directory to your machine, install the plugin manager, and the plugins


#### ZSH Plugin Manager
- The plugin manager is `oh-my-zsh` the bash comand to install it can be found on the official website: [ ohMyZsh ](https://ohmyz.sh/#install)
- This will create a diretory: `~/.oh-my-zsh` and a script:  `~/oh-my-zsh.sh`, if you want to remove zsh completely or in case the configuration process doesn't end well and you want to restar remeber to delete both.

#### ZSH Plugins 
To install a Plugin with `oh-my-zsh` we first have to clone a repo in our `.oh-my-zsh/cutsom` directory and update the `~/.zshrc` config file appropriately. 

We want to install the following plugins: `zsh-autosuggestion` , `zsh-syntax-highlighting` and the `power10k` theme:

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```

In this case the config file in this Repo already accounts for the plugins we want to have, so once cloned the official plugin repos we can proceed by copying the `.zhsrc` file contained in this Repo in paths specified above.

The power10k theme will have to be configured the first time we restart `zsh`. If we wish to change configuratihon after we can just enter the `p10k configure` command, to enter the configuration wizard again.

### ZSH Useful referencese
[ Install and Setup ZSH on Ubuntu Linux ](https://itsfoss.com/zsh-ubuntu/)

## Tmux
### Tmux Installation
```bash
sudo apt install tmux
sudo pacman -S tmux
```

### Tmux Configuration
- The default directory path for tmux config is: `~/.config/tmux`
- The default config file path for tmux config file is: `~/.config/tmux/tmux.conf`

> Before copying the config file in this directory to your machine, install the plugin manager, and the plugins

#### Tmux Plugin Manager
Refer to the official repo to intall: ( Tmux Plugin Manager )[https://github.com/tmux-plugins/tpm]

#### Tmux Plugins 
The Plugins we want are already taken account of in the `tmux.conf` file in this repo, so copy it to the tmux config paths specified above, restart tmux hit `Ctrl+b+I` to install them and you're done.


## Custom Scripts

### Tmux-sessionizer

- The file is `tmux-sessionizer.sh` it relies on the fuzzy finder `fzf` specified in the [ Dependencies ](#i3-dependencies) section.
- Is aliased in alacritty by the `ftm` command. It will open a fuzzy finder search for all subdirctories in the path from which the command is run, when one direcotry is selected it opens a new tmux session in the path selected
- The script must be copied to the `~` path

**NOTE: ** remember to run `chmod +x <your_script>.sh` before running the script to make it executable

## Misc

### Network
Connect to a Wi-fi network, needed during instalation of Arch if ethernet not available
```bash
iwctl --passphrase "<your_network_password>" station wlan0 connect <your-network-name>
```
To connect on startup
```bash
sudo systemctl start iwd
sudo systemctl restart systemd-resolved.service
sudo systemctl restart systemd-networkd
sudo systemctl enable iwd
sudo systemctl enable systemd-resolved.service
sudo systemctl enable systemd-networkd
networkctl
```

### Keyboard layout
To change keyboard layout
```bash
setxkbmap -layout it
```

To change keyboard layout automatically at startup add the following command to `$HOME/.profile` (create it if doesn't exist)

```bash
setxkbmap -layout it
```
### Picom
Copy the file `picom.conf` in this repo to `/etc/xdg/picom.conf` to remove shadows under menu windows, dialog boc, etc.

### Docker 
To isntall `docker` and `docker-compose` use `pacman` refere to the official arch page for how to start the services:
```bash
sudo system ctl start docker.service
sudo system ctl start docker.socket
sudo system ctl enable docker.service
sudo system ctl enable docker.socket
```

To run docker without root privileges we have to add the user to group
group are stored in the `/etc/group` file
```bash
sudo groupadd docker
sudo usermod -aG docker <usern_name>
su - <usern_name>
```

### Ethernet

To connect to Ethernet if when plugging the cable it does not get automatically detected:

- Get the ethernet network interface name by running `ip addr show` or `ip link` usually is `enp2s0` or `eth0`
- Check that the interface is `UP`, if it is not run the following `sudo ip link <interface name> up`
- Now you should get an IPv6 address, to get an IPv4 address use a DHCP client e.g. `sudo dhclient <interface_name>`


### USB Drive
[Guide to mount USB Drives]( https://ejmastnak.com/tutorials/arch/usb/#udisk2 )

Using `udisks2`

```bash
# Install usdisks2
sudo pacman -S udisks2

# Mount a drive's data partition
udisksctl mount -b /dev/sdxN

# Unmount a drive's data partition
udisksctl unmount -b /dev/sdxN

# Power off a drive
udisksctl power-off -b /dev/sdx
```

Note: `sdxN` is an alias for your usb drive name as seen by runnign `lsblk`, e.g. `sdb1`

To check where your drive has been mounted run again `lsblk` go to the mount direcotory `/run/media/$USER/$DEVICE_UUID` to access your USB Drive filesystem
