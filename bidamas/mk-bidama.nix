# `mkBidama` — a bidama IS a derivation.
#
# ## Why this exists
#
# The first version of `bidamas/flake.nix` packaged the whole distribution as
# one store path and called nix "the pinning layer". That was too small a claim
# to be worth making: it pinned bytes without ever modelling a package.
#
# This makes the mapping structural instead. **One bidama, one derivation, and
# the `needs(...)` in its `Bluefile` become that derivation's real nix
# dependencies** — so the dependency graph blue's resolver computes and the
# graph nix builds are the same graph, not two descriptions of one that can
# drift apart.
#
# What that buys, and none of it is new machinery — it is what a derivation
# already is:
#
#   * a bidama is content-addressed by its inputs, so two builds resolving the
#     same package cannot disagree about its contents;
#   * a missing dependency is a build failure, not a runtime "unbound symbol";
#   * `nix build .#kazu` works on one package without materialising the rest;
#   * the fleet's caching applies unchanged — a bidama substitutes like anything
#     else, so the distribution inherits the binary cache for free.
#
# This follows the fleet's `mk<Thing>` builder convention (substrate's
# `rust-tool-release-flake.nix`, `mkDarwinAppBundle`, `mkHelmChartPackages`):
# one function, typed arguments, a complete derivation out.
#
# ## The honest limit on dependency extraction
#
# A `Bluefile` is *blue code* — `needs("kazu", "^0.1")` is a call, and in
# general its arguments could be computed. Nix cannot evaluate blue, so this
# reads the dependency edges with `builtins.match` over the source text.
#
# That is exact for the literal form every bidama uses today and **wrong for a
# computed one**, which is a real ceiling rather than a hypothetical: the
# manifest-is-code property is one of blue's genuine differentiators, so
# computed dependency sets are a thing the language invites. The mitigation is
# that a mismatch cannot go unnoticed — `blue-lang-pkg`'s `GitRegistry` reads
# the same manifests by *evaluating* them, and
# `crates/blue-lang-pkg/tests/git_registry.rs` asserts the edges it finds. If
# nix's regex view and blue's evaluated view ever disagree, that test is the
# thing that says so.
#
# Tier: **only-mitigated** — ceiling is a computed `needs(...)` that the regex
# cannot see. The fix is a `blue bluefile --deps --json` subcommand, so nix
# consumes blue's own evaluation rather than re-deriving it. Named, not built.
#
# **The ceiling is measured, not hypothetical** (2026-08-02). Rewriting one of
# `zenbu`'s seventeen entries as `computed = "moji"` / `needs(computed, "^0.1")`
# left blue's resolver reporting 17 dependencies, this file's `depsOf` seeing 16,
# and `nix build .#zenbu` producing a closure of 17 bidamas instead of 18 — with
# no test anywhere going red. `granularity.rs::the_regex_and_evaluated_dependency_views_agree`
# closes that: it compares this text split against `GitRegistry`'s EVALUATED
# manifest for every package and fails when they disagree. Tier moves from
# *undetected* to **CI-gate-caught**; the fix above is still unbuilt.

{ lib, runCommand, symlinkJoin ? null, makeWrapper ? null }:

let
  # Dependency names declared by a Bluefile, as a list of strings.
  #
  # Splits on `needs("` and takes the identifier that follows, which is a
  # deliberately dull approach: a cleverer regex over the whole file would be
  # harder to read and no more correct, because the real limit is evaluation
  # (above), not pattern power.
  depsOf = manifestText:
    let
      parts = lib.drop 1 (lib.splitString ''needs("'' manifestText);
      nameOf = part: lib.head (lib.splitString ''"'' part);
    in
    map nameOf parts;

  # The version a Bluefile declares, or null.
  #
  # Read from `package(...)` rather than the directory name so identity is
  # stated once, by the package, in blue. A directory called `kazu-0.1.0` would
  # be a second place for the version to be wrong.
  versionOf = manifestText:
    let m = builtins.match ''.*package\("[^"]+", "([^"]+)"\).*'' manifestText;
    in if m == null then null else lib.head m;

in
rec {
  inherit depsOf versionOf;

  # Build ONE bidama.
  #
  # `all` is the attrset of every built bidama, passed in so a package can
  # depend on its siblings — the knot `mkDistribution` ties below.
  mkBidama = { name, src, all ? { } }:
    let
      manifestText = builtins.readFile (src + "/Bluefile");
      version = versionOf manifestText;
      deps = depsOf manifestText;
      resolved = map
        (d:
          all.${d} or (throw ''
            bidama "${name}" needs "${d}", which is not in the distribution.

            A dependency that does not exist must fail HERE, at build time,
            rather than at runtime as an unbound symbol — that is the whole
            reason a bidama is a derivation.
          ''))
        deps;
    in
    runCommand "bidama-${name}${lib.optionalString (version != null) "-${version}"}"
      {
        inherit version;
        buildInputs = resolved;
        passthru = { bidamaDeps = deps; bidamaName = name; };
        meta.description = "blue bidama: ${name}";
      } ''
      mkdir -p $out/${name}
      cp -r ${src}/* $out/${name}/

      # A bidama must carry source. An empty package resolves fine and then
      # fails at import with nothing to point at.
      if [ -z "$(find $out/${name} -name '*.b' -print -quit)" ]; then
        echo "bidama ${name} contains no .b source" >&2
        exit 1
      fi

      # Record the resolved dependency STORE PATHS, not just their names.
      #
      # This is load-bearing and was a real bug: an earlier version wrote only
      # the names, and `nix-store -q --references` on the result returned ZERO.
      # `buildInputs` alone gives build-time ORDERING; a store reference exists
      # only if the output actually mentions the path. So `nix build .#retsu`
      # produced a retsu whose closure did not contain kazu — the dependency
      # was recorded and not delivered, which is the worst of both (it reads as
      # wired and behaves as absent).
      #
      # Writing the paths makes the edge real: the closure now carries every
      # dependency, `nix-store -q --references` shows them, and a consumer that
      # copies a bidama gets its dependencies with it.
      : > $out/${name}/.bidama-deps
      ${lib.concatMapStringsSep "\n"
          (d: ''echo "${d}" >> $out/${name}/.bidama-deps'')
          (map toString resolved)}
    '';

  # A single `BLUE_PATH` root containing the given bidamas.
  #
  # ## Why this is the whole nix-native claim, in one function
  #
  # `blue_lang_pkg::LoadPath` searches roots whose immediate children are
  # package directories, and `mkBidama` above produces exactly `$out/<name>/`.
  # So a bidama's store path is ALREADY a valid root — there is no install
  # step, no manifest translation, no adapter between "what nix built" and
  # "what the runtime loads". Joining several of them yields one root holding
  # a chosen set of packages:
  #
  #     BLUE_PATH=$(nix build --no-link --print-out-paths .#bluePath)
  #
  # The loader cannot tell a store path from a working tree, which is the
  # property worth having: the same code path serves `nix develop` and a
  # developer's checkout, so what CI runs is what the laptop ran.
  #
  # Closure-complete by construction — `mkBidama` writes each dependency's
  # store PATH into the output, so joining a package brings its dependencies
  # whether or not the caller listed them.
  mkBluePath = { bidamas, name ? "blue-path" }:
    assert lib.assertMsg (symlinkJoin != null)
      "mkBluePath needs symlinkJoin; pass the full pkgs set";
    symlinkJoin { inherit name; paths = lib.attrValues bidamas; };

  # `blue`, with a `BLUE_PATH` baked in.
  #
  # The reason to wrap rather than document an export: an operator who has to
  # set an environment variable to make imports work will one day not set it,
  # and the failure — an unresolved package — reads as a broken distribution
  # rather than a missing variable. A wrapper makes the working configuration
  # the only one that ships.
  #
  # `--prefix`, not `--set`: a caller's own BLUE_PATH still wins, because the
  # loader searches left to right and prefixing puts these roots first only
  # relative to nothing. A local checkout stays overridable, which is the
  # difference between a default and a cage.
  mkBlueWithBidamas = { blue, bidamas, name ? "blue-with-bidamas" }:
    assert lib.assertMsg (makeWrapper != null)
      "mkBlueWithBidamas needs makeWrapper; pass the full pkgs set";
    runCommand name { nativeBuildInputs = [ makeWrapper ]; } ''
      mkdir -p $out/bin
      makeWrapper ${blue}/bin/blue $out/bin/blue \
        --prefix BLUE_PATH : "${mkBluePath { inherit bidamas; }}"
    '';

  # Build every bidama in a distribution directory, wiring the graph.
  #
  # `lib.fix` ties the knot: each package receives the finished attrset, so
  # `retsu` can reference `kazu` without the distribution being ordered by hand.
  # A dependency CYCLE therefore surfaces as nix's own infinite-recursion error
  # rather than as a silently truncated graph — the loud failure is the correct
  # one, and blue's solver reports cycles too, so the two agree on rejection.
  mkDistribution = { root, pkgs }:
    let
      dirs = lib.filterAttrs
        (n: t: t == "directory" && builtins.pathExists (root + "/${n}/Bluefile"))
        (builtins.readDir root);
    in
    lib.fix (all:
      lib.mapAttrs
        (name: _: mkBidama {
          inherit name all;
          src = root + "/${name}";
        })
        dirs);
}
