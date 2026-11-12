@moduledoc """
node: a NixOS node's configuration authored in blue. configuration.nix beside it is its rendering (the root Bluefile's generate("node-nix")), and checks.node-from-blue evaluates that rendering and oracle.nix, written by hand, to the same system.

    blue run nix/node-fixture/node.b
"""

use("kakehashi/nikkusu", %i[module nix_ref])

@doc """
node: the node's configuration as data.

    node["networking"]["hostName"] #=> "blue-node"
"""
def node()
  {
    "networking" => {
      "hostName" => "blue-node",
      "firewall" => {"allowedTCPPorts" => [22, 8080]}
    },
    "services" => {
      "openssh" => {
        "enable" => true,
        "settings" => {"PasswordAuthentication" => false}
      }
    },
    "users" => {
      "users" => {
        "operator" => {
          "isNormalUser" => true,
          "extraGroups" => ["wheel"],
          "description" => "the \"operator\" of ${node}"
        }
      }
    },
    "environment" => {
      "systemPackages" => [nix_ref("pkgs.git"), nix_ref("pkgs.curl")]
    },
    "boot" => {"loader" => {"grub" => {"devices" => ["nodev"]}}},
    "fileSystems" => {
      "/" => {"device" => "/dev/disk/by-label/nixos", "fsType" => "ext4"}
    },
    "time" => {"timeZone" => "UTC"},
    "system" => {"stateVersion" => "25.11"}
  }
end

@doc """
rendering: the node as a NixOS module's source.

    starts_with?(rendering, "{ pkgs, ... }:") #=> true
"""
def rendering()
  module(["pkgs"], node)
end

write_file(getenv("GEN_OUT", "nix/node-fixture/configuration.nix"), rendering)
