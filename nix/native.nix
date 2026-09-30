# blue native, lowered to flake outputs for one system (theory/BLUE-NATIVE.md).
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

  # The project's own checks under a `native-` prefix, so none meets a name
  # in blue's root project.
  projectChecks = lib.mapAttrs' (n: v: lib.nameValuePair "native-${n}" v) project.checks;
in
{
  packages = lib.mapAttrs' (n: v: lib.nameValuePair "native-${n}" v) built;
  checks = projectChecks
    // lib.mapAttrs' (n: s: lib.nameValuePair "${n}-qemu" (qemuCheck n s)) images;
}
