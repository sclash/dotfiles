{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  # my-dotfiles,
  ...
}:

{
  programs.sioyek = {
    enable = true;
    bindings = {
    
  "move_up" = "k";
  "move_down" = "j";
  "move_lef" = "h";
  "move_right" = "l";
  "screen_down" = [ "d" "<c-d>" ];
  "screen_up" = [ "u" "<c-u>" ];
  "goto_tab" = [ "a"  "<C-a" ];
  "goto_next_tab" = [ "k" "K" ];
  "goto_prev_tab" = [ "j" "J" ];
  "goto_mark" = "'";
    }; }; }
