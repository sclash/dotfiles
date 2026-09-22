{ pkgs }: pkgs.stdenvNoCC.mkDerivation rec {
  pname = "openresearch-cli"; version = "0.2.8";
  src = pkgs.fetchurl {
    url = "https://github.com/alphaXiv/OpenResearch/releases/download/v${version}/openresearch-cli-x86_64-unknown-linux-musl.tar.xz";
    sha256 = "0gbxwd5dsvylyz8dxv1d8cdfxam8wqgihwka5abm5zbfing8i1vq";
    # sha256 = pkgs.lib.fakeSha256;
  };
  dontUnpack = false;
  installPhase = ''install -Dm755 orx $out/bin/orx'';
}
