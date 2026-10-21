# Map a base tree plus an overlay tree to home.file entries.
#
# For each path, starting at a top-level item `rel`:
#   - excluded                                  -> no entry
#   - missing from both trees                   -> no entry
#   - no overlay entry and no exclude below it  -> one link to the base path
#                                                  (a whole directory is one link)
#   - overlay entry is a file                   -> link to the overlay file
#   - overlay entry is a directory, or an exclude lies below the path
#                                               -> expand: children are the union of
#                                                  both listings, same rules each
#
# Listings come from the flake source (baseSrc, overlaySrc), so the layout is
# fixed at eval time; links point at the live trees (baseLive, overlayLive).
{ lib }:
{
  link,
  baseSrc,
  overlaySrc,
  baseLive,
  overlayLive,
  exclude ? [ ],
}:
let
  isDir = p: builtins.pathExists p && builtins.readFileType p == "directory";
  names = p: if isDir p then builtins.attrNames (builtins.readDir p) else [ ];

  go =
    rel:
    let
      base = baseSrc + "/${rel}";
      overlay = overlaySrc + "/${rel}";
      inBase = builtins.pathExists base;
      inOverlay = builtins.pathExists overlay;
      excludeBelow = lib.any (e: lib.hasPrefix "${rel}/" e) exclude;
    in
    if lib.elem rel exclude || !(inBase || inOverlay) then
      { }
    else if inOverlay && !isDir overlay then
      { ${rel}.source = link "${overlayLive}/${rel}"; }
    else if !inOverlay && !excludeBelow then
      { ${rel}.source = link "${baseLive}/${rel}"; }
    else
      lib.mergeAttrsList (
        map (child: go "${rel}/${child}") (lib.unique (names base ++ names overlay))
      );
in
go
