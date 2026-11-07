{
  lib,
  username,
  homeDirectory,
  ...
}:
let
  # Each machine has its own secrets file, encrypted to its own age key. The
  # installer creates both outside this repo, from secrets/template.yaml.
  secretsFile = "${homeDirectory}/.config/sops/secrets.yaml";

  lines = text: lib.filter (line: line != "") (lib.splitString "\n" text);

  # The template is public, so it may only hold `name: null` lines. The error
  # doesn't quote the line, because that could print a real credential.
  templateNames = map (
    line:
    let
      match = builtins.match "([A-Za-z0-9_.-]+): null" line;
    in
    if match == null then
      throw "nixos/secrets/template.yaml: every line must be `name: null`"
    else
      builtins.head match
  ) (lines (builtins.readFile ./secrets/template.yaml));

  # A null value would stop every secret from installing, so only filled-in ones
  # are installed. sops leaves names and nulls readable, so this needs no key.
  # Rebuilds use --impure and can read the file. Pure evaluation such as
  # `nix flake check` can't, so it installs every name.
  filledNames =
    if !(builtins ? currentSystem) then
      templateNames
    else if builtins.pathExists secretsFile then
      lib.flatten (
        lib.remove null (
          map (builtins.match "([A-Za-z0-9_.-]+): ENC\\[.*") (lines (builtins.readFile secretsFile))
        )
      )
    else
      [ ];
in
{
  sops = {
    age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = secretsFile;
    # The file isn't in the Nix store, so it's read at activation, not at build.
    validateSopsFiles = false;
    defaultSopsFormat = "yaml";
    secrets = lib.genAttrs (lib.intersectLists templateNames filledNames) (_: {
      owner = username;
      mode = "0600";
    });
  };
}
