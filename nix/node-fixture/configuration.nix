{ pkgs, ... }:
{
  boot = {
    loader = {
      grub = {
        devices = [ "nodev" ];
      };
    };
  };
  environment = {
    systemPackages = [ pkgs.git pkgs.curl ];
  };
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
  };
  networking = {
    firewall = {
      allowedTCPPorts = [ 22 8080 ];
    };
    hostName = "blue-node";
  };
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
    };
  };
  system = {
    stateVersion = "25.11";
  };
  time = {
    timeZone = "UTC";
  };
  users = {
    users = {
      operator = {
        description = "the \"operator\" of \${node}";
        extraGroups = [ "wheel" ];
        isNormalUser = true;
      };
    };
  };
}
