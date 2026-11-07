{ lib, pkgs, blue, bl, src }:
let
  manifest = builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"));
  version = manifest.workspace.package.version;
  members = lib.filter (m: m.package.publish or true != false)
    (map (m: builtins.fromTOML (builtins.readFile (src + "/${m}/Cargo.toml"))) manifest.workspace.members);
  names = map (m: m.package.name) members;
  shipped = spec: !(builtins.isAttrs spec) || spec.workspace or false || spec ? version;
  sections = m:
    [ (m.dependencies or { }) (m.build-dependencies or { }) (m.dev-dependencies or { }) ]
    ++ lib.concatMap (t: [ (t.dependencies or { }) (t.build-dependencies or { }) (t.dev-dependencies or { }) ])
      (builtins.attrValues (m.target or { }));
  edges = m: lib.unique (lib.filter (d: d != m.package.name && builtins.elem d names)
    (lib.concatMap (s: builtins.attrNames (lib.filterAttrs (_: shipped) s)) (sections m)));
  depsOf = lib.listToAttrs (map (m: lib.nameValuePair m.package.name (edges m)) members);
  sorted = lib.toposort (a: b: builtins.elem a depsOf.${b}) names;
  order = sorted.result or (throw "package-fidelity: the workspace's shipped dependency edges form a cycle: ${builtins.toJSON sorted}");
  crate = c: "${c}-${version}";
  depth = l: builtins.length (lib.splitString "/" l);
  deepest = ls: lib.foldl' (a: b: if depth b > depth a then b else a) (builtins.head ls) ls;
  probes = lib.unique ([ "todokede/motenashi" ] ++ lib.mapAttrsToList (p: ls: "${p}/${deepest ls}")
    (lib.filterAttrs (_: ls: ls != [ ]) (bl.treeLevels (src + "/bidamas"))));
  registered = pkgs.writeText "package-fidelity-checksum.json" ''{"files":{},"package":null}'';
  publish = c: ''
    cargo package -p ${c} --no-verify --offline --registry crates-io
    tar -xzf target/package/${crate c}.crate -C "$vendor"
    cp ${registered} "$vendor/${crate c}/.cargo-checksum.json"
  '';
in
pkgs.stdenv.mkDerivation {
  pname = "package-fidelity";
  inherit version src;

  cargoDeps = pkgs.rustPlatform.importCargoLock {
    lockFile = src + "/Cargo.lock";
    allowBuiltinFetchGit = true;
  };

  nativeBuildInputs = [ pkgs.rustPlatform.cargoSetupHook pkgs.cargo pkgs.rustc ];
  buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];

  buildPhase = ''
    runHook preBuild
    export CARGO_BUILD_JOBS=$NIX_BUILD_CORES
    top=$NIX_BUILD_TOP
    vendor=$top/$(stripHash "$cargoDeps")
    ${lib.concatMapStrings publish order}
    mkdir -p $top/walk-checkout $top/walk-tarball $top/probe $top/home
    rustc --edition 2021 -o $top/walk crates/blue-lang-pkg/build.rs
    CARGO_FEATURE_EMBEDDED=1 CARGO_MANIFEST_DIR=$PWD/crates/blue-lang-pkg OUT_DIR=$top/walk-checkout $top/walk > $top/checkout.walk
    CARGO_FEATURE_EMBEDDED=1 CARGO_MANIFEST_DIR="$vendor/${crate "blue-lang-pkg"}" OUT_DIR=$top/walk-tarball $top/walk > $top/tarball.walk
    ${blue}/bin/blue run --quiet ${./package-gate.b} -- files $top/checkout.walk "$(realpath bidamas)" $top/tarball.walk "$(realpath "$vendor/${crate "blue-lang-pkg"}/bidamas")" > files.out
    cargo build --offline --bin blue --manifest-path "$vendor/${crate "blue-lang-cli"}/Cargo.toml" --target-dir $top/tarball-target
    ${blue}/bin/blue run --quiet ${./package-gate.b} -- resolve $top/tarball-target/debug/blue $top/probe $top/home ${lib.escapeShellArgs probes} > resolve.out
    runHook postBuild
  '';

  installPhase = ''
    cat files.out resolve.out > $out
  '';
}
