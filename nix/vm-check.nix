{ lib, pkgs, blue, src, checks }:

let
  inherit (lib) attrNames concatMapStrings mapAttrs' nameValuePair;

  inside = spec: file:
    lib.any (i: file == i || lib.hasPrefix "${i}/" file) spec.inputs;

  tree = vn: spec:
    let outside = lib.filter (f: !inside spec f) [ spec.program spec.control.program ]; in
    if outside != [ ] then
      throw "lib.project: vm_check(\"${vn}\") runs ${lib.concatStringsSep ", " outside}, which `inputs` does not bring into the machine"
    else pkgs.runCommand "vm-${vn}-tree" { } (''
    mkdir -p $out
  '' + concatMapStrings
    (d: ''
      mkdir -p "$out/${dirOf d}"
      cp -r ${builtins.path { path = src + "/${d}"; name = baseNameOf d; }} "$out/${d}"
    '')
    spec.inputs);

  judged = vn: spec: k: kernel: pkgs.writeText "vm-${vn}-${k}.json" (builtins.toJSON {
    inherit (kernel) release;
    inherit (spec) program expect control;
    env = (spec.env or { }) // (kernel.env or { });
  });

  tool = vn: name:
    if lib.hasSuffix ".nix" name then pkgs.callPackage (src + "/${name}") { }
    else lib.attrByPath (lib.splitString "." name)
      (throw "lib.project: vm_check(\"${vn}\") tool `${name}` is no attribute in nixpkgs")
      pkgs;

  booted = vn: spec: k: kernel:
    let
      project = tree vn spec;
      plan = judged vn spec k kernel;
      options = kernel.config or [ ];
      packages = lib.attrByPath (lib.splitString "." kernel.package)
        (throw "lib.project: vm_check(\"${vn}\") kernel ${k} names `${kernel.package}`, no attribute in nixpkgs")
        pkgs;
    in
    pkgs.testers.runNixOSTest {
      name = "vm-${vn}-${k}";
      meta.timeout = spec.seconds + 300;
      nodes.machine = {
        boot.kernelPackages = packages;
        boot.kernelPatches = lib.optional (options != [ ]) {
          name = "vm-${vn}-${k}-config";
          patch = null;
          structuredExtraConfig = lib.genAttrs options (_: lib.kernel.yes);
        };
        boot.kernelParams = spec.params or [ ];
        environment.systemPackages = [ blue ] ++ map (tool vn) (spec.tools or [ ]);
        virtualisation.memorySize = spec.memory_mb;
        virtualisation.cores = spec.cores;
        virtualisation.diskSize = 4096;
      };
      testScript = ''
        machine.wait_for_unit("multi-user.target")
        machine.succeed("cp -r ${project} /root/project && chmod -R u+w /root/project")
        status, _ = machine.execute(
            "cd /root/project && blue run --quiet ${./vm-run.b} -- ${plan} > /tmp/vm-${k}.log 2>&1",
            timeout=${toString spec.seconds},
        )
        machine.copy_from_vm("/tmp/vm-${k}.log", "")
        print(machine.succeed("cat /tmp/vm-${k}.log"))
        assert status == 0, f"vm-${vn}-${k}: exit {status}; the log is vm-${k}.log in the output"
      '';
    };

  linux = pkgs.stdenv.hostPlatform.isLinux;

  declared = vn: spec: nameValuePair "vm-${vn}-absent" (pkgs.writeText "vm-${vn}-absent" ''
    absent on ${pkgs.stdenv.hostPlatform.system}: vm_check("${vn}") ran none of its kernels (${lib.concatStringsSep ", " (attrNames spec.kernels)}) in this check. Each boots in a machine that needs Linux with KVM, so a land does not wait on them: `nix build .#vm-${vn}-<kernel>` runs one.
  '');

  machines = lib.concatMapAttrs
    (vn: spec: mapAttrs'
      (k: kernel: nameValuePair "vm-${vn}-${k}" (booted vn spec k kernel))
      spec.kernels)
    checks;
in
{
  checks = mapAttrs' declared checks;
  packages = lib.optionalAttrs linux machines;
}
