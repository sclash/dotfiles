{
  sops = {
    age.keyFile = "/home/asergi/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    secrets.github_pat = {
      owner = "asergi";
      mode = "0600";
    };
  };
}
