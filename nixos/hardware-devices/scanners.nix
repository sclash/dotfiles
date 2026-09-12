# SANE scanner configuration for the EPSON XP-2200 Series.
{ pkgs, ... }:

{
  # SANE backends so CLI tools (scanimage) can use the scanner too.
  # - epsonscan2 + non-free plugin: Epson's own backend (also used by the GUI).
  # - sane-airscan: AirScan/WSD; the free epsonds backend is broken for the
  #   XP-2200 network scanner, whereas WSD works.
  hardware.sane = {
    enable = true;
    extraBackends = [
      (pkgs.epsonscan2.override { withNonFreePlugins = true; })
      pkgs.sane-airscan
    ];
    # v4l makes scanimage pick the webcam; epsonds/epson2 detect the XP-2200
    # but fail mid-scan over the network. Leave airscan as the usable backend.
    disabledDefaultBackends = [ "v4l" "epson2" "epsonds" ];
  };
}
