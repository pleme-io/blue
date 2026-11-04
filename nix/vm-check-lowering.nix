{ lib, pkgs, pkgsFor }:

let
  spec = kernels: {
    k = {
      program = "kernel/run.b";
      inputs = [ "kernel" ];
      expect = [ "green" ];
      control = { program = "kernel/control.b"; expect = [ "1 failed" ]; };
      memory_mb = 512;
      cores = 1;
      seconds = 60;
      inherit kernels;
    };
  };
  kernels = {
    booted = { package = "linuxPackages_6_12"; release = "6.12."; };
    built = { package = "linuxPackages_6_12"; release = "6.12."; config = [ "FPROBE" ]; };
  };
  lower = system: checks: import ./vm-check.nix {
    inherit lib;
    pkgs = pkgsFor system;
    blue = (pkgsFor system).hello;
    src = ../.;
    inherit checks;
  };
  linux = lower "x86_64-linux" (spec kernels);
  darwin = lower "aarch64-darwin" (spec kernels);
  outside = lower "x86_64-linux" (spec kernels // {
    k = (spec kernels).k // { inputs = [ "docs" ]; };
  });
  features = linux.packages.vm-k-booted.config.rawTestDerivation.requiredSystemFeatures;
  absent = system: builtins.unsafeDiscardStringContext (lower system (spec kernels)).checks.vm-k-absent.text;
  claims = {
    "each kernel is a package, so a land never boots one" = lib.attrNames linux.packages == [ "vm-k-booted" "vm-k-built" ];
    "the one check names the absence, on Linux too" = lib.attrNames linux.checks == [ "vm-k-absent" ];
    "the machine needs KVM, so no builder runs it without" = lib.elem "kvm" features;
    "the machine boots through nixos-test" = lib.elem "nixos-test" features;
    "elsewhere one check names its absence" = lib.attrNames darwin.checks == [ "vm-k-absent" ];
    "elsewhere no machine is a package" = darwin.packages == { };
    "the absence says what did not run" = lib.hasInfix "booted, built" (absent "aarch64-darwin") && lib.hasPrefix "absent on aarch64-darwin" (absent "aarch64-darwin");
    "a program outside inputs is refused" = !(builtins.tryEval outside.packages.vm-k-booted.drvPath).success;
  };
  broken = lib.attrNames (lib.filterAttrs (_: ok: !ok) claims);
in
if broken != [ ] then throw "vm-check-lowering: ${lib.concatStringsSep "; " broken}"
else pkgs.writeText "vm-check-lowering" (builtins.toJSON (lib.attrNames claims))
