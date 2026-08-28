# See https://wiki.hyprland.org/Configuring/Monitors/
-- monitor=eDP-1,1920x1080@60.05, 0x0,1
	--
	--
-- local hl = require("hyprland");

hl.monitor({
		output = "",
		-- mode = "1920x1080@60.05",
		mode = "preferred",
		position = "auto",
		scale = "1",
})


-------------------
--- MY PROGRAMS 
-------------------

-- See https://wiki.hyprland.org/Configuring/Keywords/

-- Set programs that you use
local terminal = "ghostty"
local fileManager = "nautilus"
local browser = "google-chrome-stable"
local waybar = "pkill waybar || waybar"
local hyprpaper  = "pkill hyprpaper || hyprpaper"
local menu = "walker"
local lock = "hyprlock"
local notifications = "swaync-client -t -sw"

-------------------
--- MY PROGRAMS 
-------------------

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:


hl.on("hyprland.start", function ()
		hl.exec_cmd("hyprlock")
		-- hl.exec_cmd("waybar")
		hl.exec_cmd("hyprpaper")
		hl.exec_cmd("elephant")
		-- hl.exec_cmd("swaync")
		hl.exec_cmd("swaync-client --daemon")
		hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'") --# for GTK4 apps
		hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'") --# for GTK3 apps
	end
)

-- # exec-once = $terminal
-- # exec-once = nm-applet ~&
-- # exec-once = waybar & hyprpaper & firefox
-- # exec-once = ashell
-- exec-once = waybar
-- exec-once = elephant
-- exec-once = hyprlock
-- exec-once = hyprpaper
-- exec-once = swaync
-- exec-once = swaync-client --daemon


-----------------------------
-- ENVIRONMENT VARIABLES 
-----------------------------
-- See https://wiki.hyprland.org/Configuring/Environment-variables/

hl.env( "XCURSOR_SIZE","24" )
hl.env( "HYPRCURSOR_SIZE","24" )
-- # for Qt apps# Theme 
hl.env( "QT_QPA_PLATFORMTHEME","qt6ct")
-- # env = HYPRCURSOR_THEME,awd-dark
-- #for libadwaita gtk4 apps you can use this command:
-- exec = gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"   # for GTK4 apps
--
-- #for gtk3 apps you need to install adw-gtk3 theme (in arch linux sudo pacman -S adw-gtk-theme)
-- exec = gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"   # for GTK3 apps
--
-- #for kde apps you need to install: sudo pacman -S qt5ct qt6ct kvantum kvantum breeze-icons   
-- #you will need to set dark theme for qt apps from kde more difficult thans with gnome :D:

----------------------------------------------------------------


-- ###################
-- ### PERMISSIONS ###
-- ###################
--
-- # See https://wiki.hyprland.org/Configuring/Permissions/
-- # Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- # for security reasons
--
-- # ecosystem {
-- #   enforce_permissions = 1
-- # }
--
-- # permission = /usr/(bin|local/bin)/grim, screencopy, allow
-- # permission = /usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland, screencopy, allow
-- # permission = /usr/(bin|local/bin)/hyprpm, plugin, allow


-- #####################
-- ### LOOK AND FEEL ###
-- #####################
--
-- # Refer to https://wiki.hyprland.org/Configuring/Variables/
--
-- # https://wiki.hyprland.org/Configuring/Variables/#general
hl.config({

		general  = {
			gaps_in = 3,
			gaps_out = 7,

			border_size = 3,

			-- # https://wiki.hyprland.org/Configuring/Variables/#variable-types for info about colors
			-- col.inactive_border = rgba(595959AA),
			-- col.active_border = rgba(0,0,0,0.0),
			col = {
				active_border = "rgba(0,0,0,0)",
				inactive_border = "rgba(595959AA)"
			},

			-- # Set to true enable resizing windows by clicking and dragging on borders and gaps
			resize_on_border = false,

			-- # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
			allow_tearing = false,

			layout = "dwindle",
	},

})

hl.config({
		group = {
			col = {
				border_active = "rgba(0,0,0,0)",
				border_inactive = "rgba(595959AA)",
				border_locked_inactive = "rgba(595959AA)",
				border_locked_active = "rgba(0,0,0,0.0)",
			},
				groupbar = {
					font_size = 16,
					height = 24,
					-- font_weight_active = "semibold",
					font_weight_active = "normal",
					col = {
						active = "rgba(0,0,0,0)",
						inactive = "rgba(595959AA)",
						locked_inactive = "rgba(595959AA)",
						locked_active = "rgba(0,0,0,0.0)",
					},

					text_color_inactive = "rgba(595959AA)",
					text_color_locked_inactive = "rgba(595959AA)",
					scrolling = false
				},
			},
	})

-- # https://wiki.hyprland.org/Configuring/Variables/#decoration
	--
	--
	--
hl.config({
		decoration  = {
		rounding = 7,
		rounding_power = 4,

		-- # Change transparency of focused and unfocused windows
		active_opacity = 1.0,
		inactive_opacity = 0.7,

		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},

		-- # https://wiki.hyprland.org/Configuring/Variables/#blur
		blur = {
			enabled = true,
			size = 3,
			passes = 1,
			vibrancy = 0.1696,
		}
	},

		animations = {
			enabled = true,
		},
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })


-- # https://wiki.hyprland.org/Configuring/Variables/#animations
-- animations {
--     enabled = yes, please :)
--
--     -- # Default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more
--
--     bezier = easeOutQuint,0.23,1,0.32,1
--     bezier = easeInOutCubic,0.65,0.05,0.36,1
--     bezier = linear,0,0,1,1
--     bezier = almostLinear,0.5,0.5,0.75,1.0
--     bezier = quick,0.15,0,0.1,1
--
--     animation = global, 1, 10, default
--     animation = border, 1, 5.39, easeOutQuint
--     animation = windows, 1, 4.79, easeOutQuint
--     animation = windowsIn, 1, 4.1, easeOutQuint, popin 87%
--     animation = windowsOut, 1, 1.49, linear, popin 87%
--     animation = fadeIn, 1, 1.73, almostLinear
--     animation = fadeOut, 1, 1.46, almostLinear
--     animation = fade, 1, 3.03, quick
--     animation = layers, 1, 3.81, easeOutQuint
--     animation = layersIn, 1, 4, easeOutQuint, fade
--     animation = layersOut, 1, 1.5, linear, fade
--     animation = fadeLayersIn, 1, 1.79, almostLinear
--     animation = fadeLayersOut, 1, 1.39, almostLinear
--     animation = workspaces, 1, 1.94, almostLinear, fade
--     animation = workspacesIn, 1, 1.21, almostLinear, fade
--     animation = workspacesOut, 1, 1.94, almostLinear, fade
-- }

-- # Ref https://wiki.hyprland.org/Configuring/Workspace-Rules/
-- # "Smart gaps" / "No gaps when only"
-- # uncomment all if you wish to use that.
-- # workspace = w[tv1], gapsout:0, gapsin:0
-- # workspace = f[1], gapsout:0, gapsin:0
-- # windowrule = bordersize 0, floating:0, onworkspace:w[tv1]
-- # windowrule = rounding 0, floating:0, onworkspace:w[tv1]
-- # windowrule = bordersize 0, floating:0, onworkspace:f[1]
-- # windowrule = rounding 0, floating:0, onworkspace:f[1]

-- # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
hl.config({
		dwindle = {
			-- Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
			-- pseudotile = true,
			--# You probably want this
			preserve_split = true ,
		},
	})


-- # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
hl.config({
		master =  {
			new_status = "master",
		},
	})

-- # https://wiki.hyprland.org/Configuring/Variables/#misc
hl.config({
		misc  = {
			-- # Set to 0 or 1 to disable the anime mascot wallpapers
			force_default_wallpaper = 0,
			-- # If true disables the random hyprland logo / anime girl background. :(
			disable_hyprland_logo = true,
			background_color = 0x000000,
			-- # background_color = 0xffffff # White
		}
	})


-- #############
-- ### INPUT ###
-- #############

-- # https://wiki.hyprland.org/Configuring/Variables/#input
hl.config({
		input = {
			kb_layout = "us, it",
			kb_variant = "",
			kb_model = "",
			kb_options = "grp:alt_shift_toggle",
			kb_rules = "",

			follow_mouse = 1,
			-- # -1.0 - 1.0, 0 means no modification.
			sensitivity = 0 ,

			touchpad  = {
				natural_scroll = false,
			},
		},
	})

-- # https://wiki.hyprland.org/Configuring/Variables/#gestures
-- # gestures {
-- #     workspace_swipe = false
-- # }

-- # Example per-device config
-- # See https://wiki.hyprland.org/Configuring/Keywords/#per-device-input-configs for more
hl.device( {
	name = "epic-mouse-v1",
	sensitivity = -0.5,
} )


-- ###################
-- ### KEYBINDINGS ###
-- ###################

-- # See https://wiki.hyprland.org/Configuring/Keywords/
local mainMod = "SUPER"  -- Sets "Windows" key as main modifier
local left = "h" -- Sets "Windows" key as main modifier
local right = "l" -- Sets "Windows" key as main modifier
local up = "k" ---[[ - Sets "Windows" key as main modifier
local down = "j" -- Sets "Windows" key as main modifier ]]

-- # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
-- bind = $mainMod, Q, exec, $terminal
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd(lock))
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({action = "toggle"}))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.layout("togglesplit"))    -- dwindle only
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.layout(notifications))    -- dwindle only
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(waybar))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd(hyprpaper))

-- bind = $mainMod, Return, exec, $terminal
-- bind = $mainMod, C, killactive,
-- bind = $mainMod, M, exit,
-- bind = $mainMod, E, exec, $fileManager
-- bind = $mainMod, V, togglefloating,
-- bind = $mainMod, R, exec, $menu
-- bind = $mainMod, X, exec, $lock
-- bind = $mainMod, G, exec, $browser
-- bind = $mainMod, P, pseudo, # dwindle
-- bind = $mainMod SHIFT, J, togglesplit, # dwindle
-- bind = $mainMod SHIFT, F, fullscreen, # dwindle
-- bind = $mainMod, F, exec, $waybar# dwindle
-- bind = $mainMod, Z, exec, $hyprpaper# dwindle
-- bind = $mainMod SHIFT, N, exec, $notifcations# dwindle

-- # Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + " .. left, hl.dsp.focus({direction = "left"}))
-- bind = $mainMod, left, movefocus, l
hl.bind(mainMod .. " + " .. right, hl.dsp.focus({direction = "right"}))
-- bind = $mainMod, right, movefocus, r
hl.bind(mainMod .. " + " .. up, hl.dsp.focus({direction = "up"}))
-- bind = $mainMod, up, movefocus, u
hl.bind(mainMod .. " + " .. down, hl.dsp.focus({direction = "down"}))
-- bind = $mainMod, down, movefocus, d


-- # Swap windows
hl.bind(mainMod .. " + ALT + " .. left, hl.dsp.window.swap({direction = "left"}))
-- bind = $mainMod ALT, left, swapwindow, l
hl.bind(mainMod .. " + ALT + " .. right, hl.dsp.window.swap({direction = "right"}))
-- bind = $mainMod ALT, right, swapwindow, r
hl.bind(mainMod .. " + ALT + " .. up, hl.dsp.window.swap({direction = "up"}))
-- bind = $mainMod ALT, up, swapwindow, u
hl.bind(mainMod .. " + ALT + " .. down, hl.dsp.window.swap({direction = "down"}))
-- bind = $mainMod ALT, down, swapwindow, d
-- bind = $mainMod ALT, $left, swapwindow, l
-- bind = $mainMod ALT, $right, swapwindow, r
-- bind = $mainMod ALT, $up, swapwindow, u
-- bind = $mainMod ALT, $down, swapwindow, d


-- # Move focus
-- bind = $mainMod, $left, movefocus, l
-- bind = $mainMod, $right, movefocus, r
-- bind = $mainMod, $up, movefocus, u
-- bind = $mainMod, $down, movefocus, d
-- # Switch workspaces with mainMod + [0-9]
-- bind = $mainMod, 1, workspace, 1
-- bind = $mainMod, 2, workspace, 2
-- bind = $mainMod, 3, workspace, 3
-- bind = $mainMod, 4, workspace, 4
-- bind = $mainMod, 5, workspace, 5
-- bind = $mainMod, 6, workspace, 6
-- bind = $mainMod, 7, workspace, 7
-- bind = $mainMod, 8, workspace, 8
-- bind = $mainMod, 9, workspace, 9
-- bind = $mainMod, 0, workspace, 10
--
-- # Move active window to a workspace with mainMod + SHIFT + [0-9]
-- bind = $mainMod SHIFT, 1, movetoworkspace, 1
-- bind = $mainMod SHIFT, 2, movetoworkspace, 2
-- bind = $mainMod SHIFT, 3, movetoworkspace, 3
-- bind = $mainMod SHIFT, 4, movetoworkspace, 4
-- bind = $mainMod SHIFT, 5, movetoworkspace, 5
-- bind = $mainMod SHIFT, 6, movetoworkspace, 6
-- bind = $mainMod SHIFT, 7, movetoworkspace, 7
-- bind = $mainMod SHIFT, 8, movetoworkspace, 8
-- bind = $mainMod SHIFT, 9, movetoworkspace, 9
-- bind = $mainMod SHIFT, 0, movetoworkspace, 10
-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))


-- # Example special workspace (scratchpad)
-- bind = $mainMod, S, togglespecialworkspace, magic
-- bind = $mainMod SHIFT, S, movetoworkspace, special:magic


-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })



-- # Scroll through existing workspaces with mainMod + scroll
-- bind = $mainMod, mouse_down, workspace, e+1
-- bind = $mainMod, mouse_up, workspace, e-1
--
-- # Move/resize windows with mainMod + LMB/RMB and dragging
-- bindm = $mainMod, mouse:272, movewindow
-- bindm = $mainMod, mouse:273, resizewindow
-- # Expand/Shrink to the left
-- binde = $mainMod SHIFT, H, resizeactive, -40 0
--
-- # Expand/Shrink to the right
-- binde = $mainMod SHIFT, L, resizeactive, 40 0

hl.bind(mainMod .. " + SHIFT + " ..  left, hl.dsp.window.resize({ x = -40, y = 0, relative = true,  }))
hl.bind(mainMod .. " + SHIFT + " ..  right, hl.dsp.window.resize({ x = 40, y = 0, relative = true,  }))

-- # Laptop multimedia keys for volume and LCD brightness
-- bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
-- bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
-- bindel = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
-- bindel = ,XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
-- bindel = ,XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+
-- bindel = ,XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-
--
-- # Requires playerctl
-- bindl = , XF86AudioNext, exec, playerctl next
-- bindl = , XF86AudioPause, exec, playerctl play-pause
-- bindl = , XF86AudioPlay, exec, playerctl play-pause
-- bindl = , XF86AudioPrev, exec, playerctl previous

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- ##############################
-- ### WINDOWS AND WORKSPACES ###
-- ##############################

-- # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
-- # See https://wiki.hyprland.org/Configuring/Workspace-Rules/ for workspace rules

-- # Example windowrule
-- # windowrule = float,class:^(kitty)$,title:^(kitty)$
--
-- # # Ignore maximize requests from apps. You'll probably like this.
-- # windowrule = suppressevent maximize, class:.*
-- #
-- # # Fix some dragging issues with XWayland
-- # windowrule = nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0
--
-- # # Ignore maximize requests from apps
-- # windowrulev2 = suppressevent maximize, class:.*
--
-- # Fix dragging issues with XWayland
-- # windowrulev2 = nofocus 1, class:^$, title:^$, xwayland:1, floating:1, fullscreen:0, pinned:0
--
--
-- ######___TABBED WINDOWS BEGIN___
-- ###Create Tabbed Windows and move into/out from one like in i3 
--
-- #Creates a group
-- bind = $mainMod, W , togglegroup

hl.bind(mainMod .. " + SHIFT + W", hl.dsp.group.toggle())    -- dwindle only

-- #Moving focus on the next or previous window inside the group
-- bind = $mainMod, bracketleft, changegroupactive, b
-- bind = $mainMod, bracketright, changegroupactive, f
-- Move to the next tab group window
hl.bind(mainMod .. " + bracketleft",  hl.dsp.group.prev())
hl.bind(mainMod .. " + bracketright", hl.dsp.group.next())
--
-- #Swaping the active window with the next or previous in a group
-- bind = $mainMod Shift, bracketleft, movegroupwindow, b
-- bind = $mainMod Shift, bracketright, movegroupwindow, f
-- bind = $mainMod Shift, $left, movegroupwindow, b
-- bind = $mainMod Shift, $right, movegroupwindow, f
hl.bind(mainMod .. " + SHIFT + bracketleft",  hl.dsp.group.move_window({ window_or_group, direction = "left"}))
hl.bind(mainMod .. " + SHIFT + bracketright", hl.dsp.group.move_window({ window_or_group, direction = "right"}))
hl.bind(mainMod .. " + SHIFT + " .. left,  hl.dsp.group.move_window({ window_or_group, direction = "left"}))
hl.bind(mainMod .. " + SHIFT + " .. right,  hl.dsp.group.move_window({ window_or_group, direction = "right"}))

--
-- #Moving non-tabbed window inside tabbed group by direction
-- bind = $mainMod Shift Control, left, moveintogroup, l
-- bind = $mainMod Shift Control, right, moveintogroup, r
-- bind = $mainMod Shift Control, up, moveintogroup, u
-- bind = $mainMod Shift Control, down, moveintogroup, d
-- -- Move current window into an existing tab group or create a new one
hl.bind(mainMod .. " + SHIFT + CTRL + bracketleft",  hl.dsp.window.move({ into_or_create_group = "left" }))
hl.bind(mainMod .. " + SHIFT + CTRL + bracketright",  hl.dsp.window.move({ into_or_create_group = "right" }))
hl.bind(mainMod .. " + SHIFT + CTRL + " .. left,  hl.dsp.window.move({ into_or_create_group = "left" }))
hl.bind(mainMod .. " + SHIFT + CTRL + " .. right,  hl.dsp.window.move({ into_or_create_group = "right" }))
--
-- #Moving non-tabbed window inside tabbed group by direction
-- bind = $mainMod Shift, $left, moveintogroup, l
-- bind = $mainMod Shift, $right, moveintogroup, r
-- bind = $mainMod Shift, $up, moveintogroup, u
-- bind = $mainMod Shift, $down, moveintogroup, d
--
-- #Moving tabbed window out from the group
-- bind = $mainMod Shift Alt, left, moveoutofgroup, l
-- bind = $mainMod Shift Alt, right, moveoutofgroup, r
-- bind = $mainMod Shift Alt, up, moveoutofgroup, u
-- bind = $mainMod Shift Alt, down, moveoutofgroup, d 
--
-- bind = $mainMod Shift Alt, $left, moveoutofgroup, l
-- bind = $mainMod Shift Alt, $right, moveoutofgroup, r
-- bind = $mainMod Shift Alt, $up, moveoutofgroup, u
-- bind = $mainMod Shift Alt, $down, moveoutofgroup, d 
---- Move current window out of the tab group
hl.bind(mainMod .. " + SHIFT + ALT + " .. left,  hl.dsp.window.move({ out_of_group = "left" }))
hl.bind(mainMod .. " + SHIFT + ALT + " .. right,  hl.dsp.window.move({ out_of_group = "right" }))
hl.bind(mainMod .. " + SHIFT + ALT + " .. up,  hl.dsp.window.move({ out_of_group = "up" }))
hl.bind(mainMod .. " + SHIFT + ALT + " .. down,  hl.dsp.window.move({ out_of_group = "down" }))

-- 	######___TABBED WINDOWS END___
-- ######___GROUP PARAMETERS SECTION BEGIN___
-- ###This section describes the parameters for tabbed windows settings
--
--
--
-- 	######___GROUP PARAMETERS SECTION END___        
--
-- #####___SIZE CHANGING BEGIN___
-- ###Changing the size of the active window
--
-- #SHIFT is for more accurate size changing
-- bind=SUPER SHIFT,R,submap,resize
-- submap=resize
--     unbind = ,down
--     binde = , right, resizeactive,  100 0
--     binde = , left,  resizeactive, -100 0
--     binde = , down,  resizeactive,  0 100
--     binde = , up,    resizeactive,  0 -100
--     binde = , $right, resizeactive,  100 0
--     binde = , $left,  resizeactive, -100 0
--     binde = , $down,  resizeactive,  0 100
--     binde = , $up,    resizeactive,  0 -100
--     binde = SHIFT, right, resizeactive,  10 0
--     binde = SHIFT, left,  resizeactive, -10 0
--     binde = SHIFT, down,  resizeactive,  0 10
--     binde = SHIFT, up,    resizeactive,  0 -10
--     binde = SHIFT, $right, resizeactive,  10 0
--     binde = SHIFT, $left,  resizeactive, -10 0
--     binde = SHIFT, $down,  resizeactive,  0 10
--     binde = SHIFT, $up,    resizeactive,  0 -10
--     bind = , escape,submap,reset 
--     bind = , return,submap,reset 
-- submap=reset
hl.bind(mainMod.. " + SHIFT + R", hl.dsp.submap("resize"))

-- Start a submap called "resize".
hl.define_submap("resize", function()

    -- Set repeating binds for resizing the active window.
    hl.bind(right, hl.dsp.window.resize({ x = 100, y = 0, relative = true}), { repeating = true })
    hl.bind(left, hl.dsp.window.resize({ x = -100, y = 0, relative = true}), { repeating = true })
    hl.bind(up, hl.dsp.window.resize({ x = 0, y = 100, relative = true}), { repeating = true })
    hl.bind(down, hl.dsp.window.resize({ x = 0, y = -100, relative = true}), { repeating = true })
    hl.bind("right", hl.dsp.window.resize({ x = 10, y = 0, relative = true}), { repeating = true })
    hl.bind("left", hl.dsp.window.resize({ x = -10, y = 0, relative = true}), { repeating = true })
    hl.bind("up", hl.dsp.window.resize({ x = 0, y = 10, relative = true}), { repeating = true })
    hl.bind("down", hl.dsp.window.resize({ x = 0, y = -10, relative = true}), { repeating = true })

    -- Use `reset` to go back to the global submap
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("return", hl.dsp.submap("reset"))

end)
--
-- ######___SIZE CHANGING END___        
