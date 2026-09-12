# CUPS printer configuration for the EPSON XP-2200 Series.
{ pkgs, ... }:

{
  # Enable CUPS printing service. Drivers must be listed here (not in
  # environment.systemPackages) so CUPS picks up their PPDs and filters.
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      epson-escpr
      epson-escpr2
    ];
  };

  # Persist the network printer across rebuilds / reboots.
  hardware.printers = {
    ensureDefaultPrinter = "EPSON_XP-2200_Series";
    ensurePrinters = [
      {
        name = "EPSON_XP-2200_Series";
        location = "Local Printer";
        deviceUri = "socket://192.168.1.103:9100";
        model = "epson-inkjet-printer-escpr/Epson-XP-2200_Series-epson-escpr-en.ppd";
      }
    ];
  };
}
