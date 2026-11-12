{ pkgs, ... }:
{
  networking.hostName = "blue-node";
  networking.firewall.allowedTCPPorts = [ 22 8080 ];
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  users.users.operator = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    description = "the \"operator\" of \${node}";
  };
  environment.systemPackages = with pkgs; [ git curl ];
  boot.loader.grub.devices = [ "nodev" ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  time.timeZone = "UTC";
  system.stateVersion = "25.11";
}
