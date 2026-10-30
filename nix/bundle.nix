{ lib, pkgs, oci, blue, runner, src, m, name, bluePath }:

let
  appliance = an: a: pkgs.runCommand "${name}-${an}-appliance" { } ''
    mkdir -p $out/bin
    BLUE_PATH=${bluePath} ${blue}/bin/blue bundle "${src}/${a.file}" --runner ${runner}/bin/blue-appliance -o $out/bin/${an}
  '';

  executables = lib.mapAttrs appliance (m.apps or { });

  images = lib.optionalAttrs pkgs.stdenv.isLinux (lib.mapAttrs
    (an: exe: (import ./image.nix { inherit lib pkgs oci blue; }).scratch {
      name = "${name}-${an}";
      tag = m.version;
      executable = "${exe}/bin/${an}";
    })
    executables);
in
{
  packages = lib.optionalAttrs (runner != null) (
    lib.mapAttrs' (an: exe: lib.nameValuePair "appliance-${an}" exe) executables
    // lib.mapAttrs' (an: image: lib.nameValuePair "appliance-${an}-image" image) images
  );
}
