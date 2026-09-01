# Quickshell desktop environment

The goal of the project is to build a minimal desktop environment using quickshell.
We are in an hyprland environment.

You'll use this file to generate a meaningful agentic setup to achieve this goal.
We're not building anything for what concerns the desktop environment. Just the agentic setup.
Use the `/brainstorming` skill to build a plan to generate the agentic setup.

## Goals
1. Architectural setup to implement the quickshell desktop environment.
2. Having all the specs below refinde or defined, so that we know precisely 
how to implement each component.
3. Agentic setup: Do we need subagents? Do we need a team of agents each implementing a component and reporting to
an orchestrator? Propose and select solutions based on accuracy and time efficiency.
4. How much the propose setup costs in terms of memory and cpu?

### Before Starting

Give a thorough review of the project.
Is it feasible with quickshell in a hyprland environment?

## Useful directories
- `/home/asergi/hacking/omarchy/` contains a git clone of the omarchy desktop environment.
You might want to refer to this both for architectural design purpose i.e:
    - Does it make sense to make the configuration modular?
    - Does it make sense to have shell script to spawn processes
- `/home/asergi/dotfiles/hypr/hyprland.lua` contains the current hyprland configuration
- `/home/asergi/dotfiles/waybar` contains the legacy waybar config.
We want to build upoon this as for what concens the styling be we want to add more functionalities
- `/home/asergi/dotfiles/nixos` contains the current NixOs system configuration.
You might need to update this if external dependencies are needed, or somthing becomes superflous.

## Styling

> [./STYLE.md](./STYLE.md) contains the general styling directives extracted from the legacy waybar
config, and omarchy quattro.

We should build this.
- Indicatively colours should be from the legacy waybar config icons and styling 
from omarchy. This is indicative NOT STRICT. Feel free to propose. In any way the styling
should be minimal but meaningful and the colors dark.

- For the launchers we would like to have slightly rounded border, with icons for each options.

## Components

The general idea is to avoid to use the mouse.
Each component either is display-only or should trigger a launcher with the respective command.

### Bar

All the files mentioned in spec are in `./bar`

| Component | Parent Component | Position | Spec |
|-------|---------|-------------|-------------|
| Wifi | Bar | Right | Wifi.md |
| Audio | Bar | Right | Audio.md |
| Bluetooth | Bar | Right | Bluetooth.md |
| KeyBoard | Bar | Right | KeyBoard.md |
| RAM | Bar | Right | Bar-Performance.md |
| CPU | Bar | Right | Bar-Performance.md |
| DISK | Bar | Right | Bar-Performance.md |
| TEMPERATURE | Bar | Right | Bar-Performance.md |
| App-Tray | Bar-Desktop-section | Left | Bar-App-Tray.md |
| Date | Bar | Center | Date.md |


### Launchers

All the files mentioned in spec are in `./launchers`

- All Launchers should be toggled through a `SUPER+<Key>` command.
- All Launchers should be open a window at center stage
- The style should be similar to the bar for what regards the colors and the icons
and to what happens right now when `SUPER+R` toggling the app launcher, just darker.
- The launcher should be interacted with with keyboard only. Vim motions are the default
choice to navigate through them.
- All Launchers should be closed through the `Esc` command.

| Component | Spec | Command |
|---------|-------------|-------------|
| Control-Center | Control-Center.md | SUPER+<SPACE> |
| Notification-Center | Notification-Center.md | SUPER+SHFIT+a |
| Shutdown-Launcher | Shutdown-Launcher.md | SUPER+q |
| Key-Launcher | Key-Launcher.md | SUPER+k |
| App-Launcher | App-Launcher.md | SUPER+r |
| Network-Launcher | Network-Center.md | SUPER+w |
| Bluetooth-Launcher | Bluetooth-Center.md | SUPER+b |
| Audio-Launcher | Audio-Center.md | SUPER+a |
| Display-manager | Display-manager.md | SUPER+d |
