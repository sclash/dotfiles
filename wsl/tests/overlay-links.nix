# Eval-time tests for lib/overlay-links.nix against the fixture trees.
# Built as a flake check: a mismatch throws with the case, actual and expected.
{ pkgs }:
let
  inherit (pkgs) lib;
  overlayLinks = import ../lib/overlay-links.nix { inherit lib; };

  links =
    exclude:
    overlayLinks {
      link = p: p;
      baseSrc = ./fixtures/overlay/base;
      overlaySrc = ./fixtures/overlay/overlay;
      baseLive = "/B";
      overlayLive = "/O";
      inherit exclude;
    };

  src = p: { source = p; };

  cases = [
    {
      case = "overlaid top file";
      actual = links [ ] "top.md";
      expected = {
        "top.md" = src "/O/top.md";
      };
    }
    {
      case = "untouched dir";
      actual = links [ ] "whole";
      expected = {
        "whole" = src "/B/whole";
      };
    }
    {
      case = "deep overlay + new file";
      actual = links [ ] "dir";
      expected = {
        "dir/keep.md" = src "/B/dir/keep.md";
        "dir/new.md" = src "/O/dir/new.md";
        "dir/sub/a.md" = src "/O/dir/sub/a.md";
        "dir/sub/b.md" = src "/B/dir/sub/b.md";
      };
    }
    {
      case = "exclude child";
      actual = links [ "plugins/bad.js" ] "plugins";
      expected = {
        "plugins/good.js" = src "/B/plugins/good.js";
      };
    }
    {
      case = "exclude item";
      actual = links [ "plugins" ] "plugins";
      expected = { };
    }
    {
      case = "missing item";
      actual = links [ ] "missing";
      expected = { };
    }
  ];

  failed = builtins.filter (c: c.actual != c.expected) cases;
in
if failed == [ ] then
  pkgs.runCommand "overlay-links-ok" { } "touch $out"
else
  throw (builtins.toJSON failed)
