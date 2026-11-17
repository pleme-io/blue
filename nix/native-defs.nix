# Tier T3 (docs/PERFORMANCE.md, 1.7.1): one derivation per def_hash.
#
# A manifest (native/build/defs.b, from `blue ast --resolved --defs`) holds a
# line per definition: its def_hash and its slice, the resolved forms it
# reaches, each named after its own hash. A definition chuuzou compiles for
# the native tier becomes a derivation whose only program input is that
# slice, so its .drvPath moves exactly when the definition, or something it
# reaches, moves: an unrelated edit or a rename builds nothing again, and
# the sui cache serves each hash once to every node.
#
# Nix reads blue's evaluation (the committed, fresh-gated manifest); it never
# re-derives a hash, and nothing here is import-from-derivation.
#
# The layout is the `native` tier of blue's cache (crates/blue-lang-mondou
# store.rs, NATIVE_TIER / NATIVE_LAYOUT): <root>/native/v1/<hex>/def, an
# executable on the host board (seam def64), and def.so beside it, the same
# definition as a library the native tier loads once and calls in process. `root` joins a manifest's
# artifacts into one such root; on BLUE_CACHE_SHARED it is what
# `BLUE_NATIVE=on blue run` answers calls from.
{ pkgs, lib, blue, hostRust, emitter, bluePath, seam, defImage }:

let
  layout = "v1";

  hexOf = hash: lib.removePrefix "b3:" hash;

  rowsOf = manifest:
    map builtins.fromJSON
      (lib.filter (l: l != "") (lib.splitString "\n" (builtins.readFile manifest)));

  artifact = row:
    let dir = "$out/native/${layout}/${hexOf row.hash}"; in
    pkgs.runCommand "blue-native-${hexOf row.hash}"
      {
        nativeBuildInputs = [ hostRust emitter pkgs.stdenv.cc ];
        slice = row.slice;
        passAsFile = [ "slice" ];
        DEF_ENTRY = row.entry;
        DEF_SEAM = seam;
        BLUE_PATH = bluePath;
        passthru = { inherit (row) hash entry; };
      } ''
      DEF_SLICE=$slicePath DEF_OUT=$TMPDIR/def ${blue}/bin/blue run --quiet ${defImage}
      mkdir -p ${dir}
      mv $TMPDIR/def/def.elf ${dir}/def && mv $TMPDIR/def/def.so ${dir}/def.so && mv $TMPDIR/def/def.rs ${dir}/def.rs
    '';

  native = rows: lib.filter (r: r.native) rows;

  defs = { manifest, program ? null }:
    lib.listToAttrs (map (r: lib.nameValuePair (hexOf r.hash) (artifact r))
      (lib.filter (r: program == null || r.program == program) (native (rowsOf manifest))));

  root = { manifest, program ? null, name ? "blue-native-root" }:
    pkgs.symlinkJoin { inherit name; paths = lib.attrValues (defs { inherit manifest program; }); };
in
{
  inherit layout rowsOf artifact defs root;
}
