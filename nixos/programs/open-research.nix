{ pkgs }: pkgs.stdenvNoCC.mkDerivation rec {
  pname = "openresearch-cli"; version = "0.2.3";
  src = pkgs.fetchurl {
    url = "https://github.com/alphaXiv/OpenResearch/releases/download/v${version}/openresearch-cli-x86_64-unknown-linux-musl.tar.xz";
    sha256 = "142nxhk3dszm2z8i9kmzj06z4pyw5hlvx5n0w6vpmdrxmfx3zzxb";
  };
  dontUnpack = false;
  installPhase = ''install -Dm755 orx $out/bin/orx'';
}
