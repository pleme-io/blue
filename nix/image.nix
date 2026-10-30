{ lib, pkgs, oci, blue }:

let
  scannableBlue =
    let
      data = oci.cargoAudit.mkCargoAuditData pkgs {
        name = "blue";
        lockFile = ../Cargo.lock;
        rootCrate = "blue-lang-cli";
      };
    in
    pkgs.runCommand "blue-scannable" { nativeBuildInputs = [ pkgs.binutils ]; } ''
      mkdir -p $out/bin
      cat ${blue}/bin/blue > $out/bin/blue
      chmod 0755 $out/bin/blue
      ${oci.cargoAudit.injectCommand { auditData = data; target = "$out/bin/blue"; }}
    '';

  sourceOf = what: repository:
    let parts = lib.splitString "/" repository; in
    if builtins.head parts == "ghcr.io" && builtins.length parts == 3 then
      "https://github.com/${builtins.elemAt parts 1}/${builtins.elemAt parts 2}"
    else
      throw "lib.project: ${what} publishes to ${repository}; the image's source label is derived only for ghcr.io/<org>/<repo>";

  toolsOf = what: names: map
    (t: lib.attrByPath (lib.splitString "." t)
      (throw "lib.project: ${what} tools names `${t}`, no attribute in nixpkgs")
      pkgs)
    names;
in
{
  inherit scannableBlue;

  scratch = { name, tag, executable }:
    pkgs.dockerTools.buildLayeredImage {
      inherit name tag;
      config = {
        Entrypoint = [ executable ];
        User = "65532:65532";
        WorkingDir = "/";
      };
    };

  build = { what, name, repository, version, program, args ? [ ], env ? { }, ports ? [ ], contents, workdir, deviation ? null }:
    let
      shell = if deviation == null then false else deviation.shell or false;
      tools = if deviation == null then [ ] else toolsOf what (deviation.tools or [ ]);
      set = oci.mkHardenedImageSet ((oci.hardenedImageSetArgs or { }) // {
        sourceUrl = sourceOf what repository;
        images.${name} = {
          service = name;
          package = scannableBlue;
          base = if deviation == null then "distroless-static" else "distroless-glibc";
          upstreamImage = "none: a blue program run by blue's static binary";
          hardeningRationale =
            if deviation == null then "blue is a static musl binary and the program is data it reads: no shell, no libc, no package manager"
            else "blue's program declares a deviation from distroless: ${deviation.reason}";
          publishName = repository;
          publishTag = version;
          entrypoint = [ "${scannableBlue}/bin/blue" "run" "--quiet" program ]
            ++ lib.optionals (args != [ ]) ([ "--" ] ++ args);
          env = lib.mapAttrsToList (k: v: "${k}=${v}") env;
          exposedPorts = lib.listToAttrs (map (p: lib.nameValuePair "${toString p}/tcp" { }) ports);
          extraContents = contents;
          inherit workdir shell;
          entrypointTools = tools;
          trivyAnalysableTargets = [ "rustbinary" ];
        };
      });
    in
    {
      inherit set;
      image = set.packages."${name}Image";
      tier =
        if deviation == null then "distroless-static"
        else if shell then "shell"
        else "distroless-glibc";
    };
}
