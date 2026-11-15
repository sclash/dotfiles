{ lib, stdenv, fetchFromGitHub, cmake, pkg-config, qt6, libpulseaudio, openssl }:

stdenv.mkDerivation (finalAttrs: {
  pname = "librepods";
  version = "unstable-2026-09-14";

  src = fetchFromGitHub {
    owner = "thisisgm";
    repo = "omarchy-pods";
    rev = "f35dbc451b386d5ecebf50436ee4a49def059735";
    hash = "sha256-Wjg+Iq16abzIQnv0RbnvyHxJYqKYJBMeoSNmLrgMLDc=";
  };

  sourceRoot = "source/daemon";

  patches = [ ../patches/librepods-airpods5.patch ];

  nativeBuildInputs = [ cmake pkg-config qt6.wrapQtAppsHook ];
  buildInputs = [ libpulseaudio openssl qt6.qtbase qt6.qtconnectivity qt6.qtdeclarative qt6.qtquick3d qt6.qttools ];
  cmakeFlags = [ "-DBUILD_TESTING=OFF" ];

  meta = {
    description = "AirPods daemon from omarchy-pods (librepods fork)";
    homepage = "https://github.com/thisisgm/omarchy-pods";
    license = lib.licenses.gpl3Only;
    mainProgram = "librepods";
    platforms = lib.platforms.linux;
  };
})
