{ pkgs }: pkgs.stdenvNoCC.mkDerivation rec {
  pname = "openresearch-cli"; version = "0.2.22";
  src = pkgs.fetchurl {
    url = "https://github.com/alphaXiv/OpenResearch/releases/download/v${version}/openresearch-cli-x86_64-unknown-linux-musl.tar.xz";
    sha256 = "sha256-GMmp4uj/ePJZHuDOaxE9LEOSIi0TOFtUH2OUHmhQntE=";
    # sha256 = pkgs.lib.fakeSha256;
  };
  dontUnpack = false;
  installPhase = ''install -Dm755 orx $out/bin/orx'';
}
