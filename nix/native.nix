# blue native, lowered to flake outputs for one system.
#
# native/ is a blue project: its Bluefile declares the bidamas (kiban, chuuzou)
# and, per image, the emitted Rust as a `generate` (committed, gated fresh).
# This file adds the two things the Bluefile has no word for until N1's
# `firmware` and `board`: the image (program x board -> ELF + size.tsv) and
# the QEMU check. Both are one derivation each, and both run blue programs
# (native/build/image.b, native/checks/*.b); nix supplies the toolchain.
#
# An image is built from `packages.generated-<name>`, the FRESH output of the
# compiler, never from the committed copy, so the image is red when the
# compiler is absent and wrong when the emitter is wrong.
{ pkgs, lib, blue, engine, fenix, emitter }:

let
  src = ../native;

  # tool("tatara-rust-emit") resolves here: the emitter's CLI from
  # tatara-rust-ast's flake. N1's firmware word owns the toolchain instead.
  project = engine.projectFor {
    pkgs = pkgs.extend (_: _: { tatara-rust-emit = emitter; });
    inherit blue src;
  };

  generated = (builtins.fromJSON (builtins.readFile (src + "/Bluefile.lock"))).manifest.generated;

  # Each image's board and the text its UART must print. The program is the
  # generate entry's one input, read from the lock, never restated.
  images = {
    hello-virt32 = { board = "qemu-virt32"; target = "riscv32imac-unknown-none-elf"; expect = "hi\n"; };
  };

  fx = fenix.packages.${pkgs.stdenv.hostPlatform.system};
  rustFor = target: fx.combine [ fx.stable.rustc fx.targets.${target}.stable.rust-std ];
  hostRust = fx.combine [ fx.stable.rustc fx.stable.rust-std ];

  image = name: spec: pkgs.runCommand "native-${name}" {
    nativeBuildInputs = [ (rustFor spec.target) pkgs.llvm ];
    IMAGE_OUT = placeholder "out";
    IMAGE_RS = project.packages."generated-${name}";
    IMAGE_BOARD = spec.board;
    IMAGE_SEAM = src + "/seam";
    IMAGE_NAME = name;
    BLUE_PATH = project.bluePath;
  } "${blue}/bin/blue run --quiet ${src + "/build/image.b"}";

  built = lib.mapAttrs image images;

  qemuCheck = name: spec: pkgs.runCommand "native-${name}-qemu" {
    nativeBuildInputs = [ pkgs.qemu pkgs.coreutils ];
    BOOT_ELF = "${built.${name}}/${name}.elf";
    BOOT_PROGRAM = src + "/${builtins.head generated.${name}.inputs}";
    BOOT_EXPECT = spec.expect;
    BLUE_PATH = project.bluePath;
  } "${blue}/bin/blue test ${src + "/checks/${lib.replaceStrings [ "-" ] [ "_" ] name}_qemu.b"} > $out";

  corpusCheck = pkgs.runCommand "native-corpus" {
    nativeBuildInputs = [ hostRust emitter pkgs.stdenv.cc ];
    CORPUS_DIR = src + "/corpus";
    CORPUS_SEAM = src + "/seam";
    BLUE_PATH = project.bluePath;
  } "${blue}/bin/blue test ${src + "/checks/corpus.b"} > $out";

  wasmCheck = pkgs.runCommand "native-wasm" {
    nativeBuildInputs = [ (rustFor "wasm32-wasip2") emitter pkgs.wasmtime ];
    WASM_PROGRAM = src + "/corpus/hex.b";
    WASM_SEAM = src + "/seam";
    BLUE_PATH = project.bluePath;
  } ''
    export HOME=$TMPDIR XDG_CACHE_HOME=$TMPDIR/cache
    ${blue}/bin/blue test ${src + "/checks/wasm.b"} > $out
  '';

  # Tier T3: one derivation per def_hash (nix/native-defs.nix). The seam is
  # the files a definition image links, so a board's own seam changing
  # rebuilds no definition.
  defSeam = lib.fileset.toSource {
    root = src + "/seam";
    fileset = lib.fileset.unions [
      (src + "/seam/kiban_io.rs")
      (src + "/seam/kiban_heap.rs")
      (src + "/seam/host_io.rs")
      (src + "/seam/def64")
    ];
  };

  t3 = import ./native-defs.nix {
    inherit pkgs lib blue hostRust emitter;
    inherit (project) bluePath;
    defImage = src + "/build/def.b";
    seam = defSeam;
  };

  # The node's builder (W1 of docs/FACTS.md): it builds the definitions runs
  # asked for (native/build/wanted.b) into this node's native tier. A run
  # starts it when BLUE_NATIVE_BUILDER names it.
  builder = pkgs.runCommand "blue-native-build" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
    meta.mainProgram = "blue-native-build";
  } ''
    makeWrapper ${blue}/bin/blue $out/bin/blue-native-build \
      --set BLUE_PATH ${project.bluePath} --set DEF_SEAM ${defSeam} \
      --prefix PATH : ${lib.makeBinPath [ hostRust emitter pkgs.stdenv.cc ]} \
      --add-flags "run --quiet ${src + "/build/wanted.b"}"
  '';

  manifest = src + "/defs/manifest.jsonl";

  defsRoot = t3.root { inherit manifest; program = "base"; name = "native-defs-base"; };

  # The key is the content, read off .drvPath at evaluation: an edited
  # definition and every definition reaching it move; an unrelated one and a
  # renamed one do not.
  keyCheck =
    let
      rows = t3.rowsOf manifest;
      row = program: key: lib.findFirst (r: r.program == program && r.key == key)
        (throw "native/defs/manifest.jsonl has no ${program} ${key}")
        rows;
      drv = at: builtins.unsafeDiscardStringContext (t3.artifact (row (lib.head at) (lib.last at))).drvPath;
      fact = what: same: a: b: { inherit what same; a = drv a; b = drv b; };
      facts = [
        (fact "the edited definition" false [ "base" "%root/square" ] [ "edited" "%root/square" ])
        (fact "a definition reaching the edit" false [ "base" "%root/sum_squares" ] [ "edited" "%root/sum_squares" ])
        (fact "a definition the edit does not reach" true [ "base" "%root/fib" ] [ "edited" "%root/fib" ])
        (fact "a renamed definition" true [ "base" "%root/fib" ] [ "renamed" "%root/fibonacci" ])
        (fact "a definition beside a rename" true [ "base" "%root/square" ] [ "renamed" "%root/square" ])
      ];
      wrong = lib.filter (f: (f.a == f.b) != f.same) facts;
      tab = lib.concatStringsSep "\t";
      line = f: tab [ f.what (if f.same then "same" else "moved") f.a f.b ];
    in
    assert lib.assertMsg (wrong == [ ])
      "native def keys: ${lib.concatMapStringsSep "; " (f: f.what) wrong} broke the content key";
    pkgs.writeText "native-def-keys.tsv"
      (lib.concatMapStrings (l: l + "\n") ([ (tab [ "what" "drv" "base" "other" ]) ] ++ map line facts));

  defsCheck = pkgs.runCommand "native-defs" {
    nativeBuildInputs = [ pkgs.coreutils ];
    DEFS_ROOT = defsRoot;
    DEFS_PROGRAM = src + "/defs/base.b";
    BLUE_PATH = project.bluePath;
  } "${blue}/bin/blue test ${src + "/checks/defs.b"} > $out";

  # The project's own checks under a `native-` prefix, so none meets a name
  # in blue's root project.
  projectChecks = lib.mapAttrs' (n: v: lib.nameValuePair "native-${n}" v) project.checks;
in
{
  packages = lib.mapAttrs' (n: v: lib.nameValuePair "native-${n}" v) built
    // { native-defs-base = defsRoot; native-build = builder; };
  inherit (project) toolchain;
  checks = projectChecks
    // lib.mapAttrs' (n: s: lib.nameValuePair "${n}-qemu" (qemuCheck n s)) images
    // {
      native-corpus = corpusCheck;
      native-wasm = wasmCheck;
      native-def-keys = keyCheck;
      native-defs = defsCheck;
    };
}
