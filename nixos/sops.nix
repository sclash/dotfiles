{
  username,
  homeDirectory,
  ...
}:
{
  sops = {
    age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    secrets.github_pat = {
      owner = username;
      mode = "0600";
    };
    secrets.openrouter = {
      owner = username;
      mode = "0600";
    };
    secrets.opencode = {
      owner = username;
      mode = "0600";
    };
    secrets.cheaper_inference = {
      owner = username;
      mode = "0600";
    };
  };
}
