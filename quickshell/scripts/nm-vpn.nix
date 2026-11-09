# nm-vpn: VPN profiles for the Quickshell Network Center (NetworkService.qml).
# Python + PyGObject, wrapped so libnm's typelib and nmcli are found.
# Tested by quickshell/tests/test-nm-vpn.sh and nixos/tests/test-vpn-vm.sh.
{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  typelibs = pkgs.lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.networkmanager
    pkgs.glib.out
    pkgs.gobject-introspection
  ];
in
pkgs.runCommand "nm-vpn" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  install -Dm644 ${./nm-vpn.py} $out/libexec/nm-vpn.py
  makeWrapper ${python}/bin/python3 $out/bin/nm-vpn \
    --add-flags $out/libexec/nm-vpn.py \
    --prefix GI_TYPELIB_PATH : ${typelibs} \
    --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.networkmanager ]}
''
