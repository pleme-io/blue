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
# ## Nix reads blue's evaluation; it does not re-derive it
#
# A `Bluefile` is *blue code* — `needs("kazu", "^0.1")` is a call, and its
# arguments can be computed. Nix cannot evaluate blue without
# import-from-derivation, so it reads what blue already computed: each
# package's committed `Bluefile.lock`, written by `blue lock` and parsed here
# with `builtins.fromJSON` (`theory/BLUE-STRUCTURE.md` §5.1, phase P1).
#
# This replaced a `builtins.match`/`splitString` scrape of the manifest text,
# which was wrong for a computed `needs` — measured on 2026-08-02 by rewriting
# one `zenbu` entry as `computed = "moji"` / `needs(computed, "^0.1")`: blue
# resolved 17 dependencies, the scrape saw 16, and the facade's closure shipped
# one bidama short with nothing going red. The scrape is DELETED, not kept as a
# fallback: a package with no lock is refused below, loudly.
#
# Tier: **eval- and CI-caught, not unrepresentable.** A stale lock can be
# committed; `mkLockCheck` (the `bidama-locks-fresh` flake check) runs
# `blue bluefile --confirm` over every package and fails on it, and
# `granularity.rs::the_locked_and_evaluated_dependency_views_agree` compares
# every lock against blue's resolver from `cargo test`.

{ lib, runCommand, symlinkJoin ? null, makeWrapper ? null }:

let
  # The lock layout this file reads. `blue_lang_pkg::lock::LOCK_SCHEMA`; a lock
  # from another layout is refused rather than half-read.
  lockSchema = 1;

  # A package's `Bluefile.lock`, parsed. Refuses a package with no lock, or one
  # in a layout this file was not written against.
  lockOf = { name, src }:
    let path = src + "/Bluefile.lock";
    in
    if !builtins.pathExists path then
      throw ''
        bidama "${name}" has no Bluefile.lock. Nix reads blue's evaluation of
        the Bluefile rather than guessing at it; write it with
        `blue lock <dir>` and commit it.
      ''
    else
      let lock = builtins.fromJSON (builtins.readFile path);
      in
      if lock.schema != lockSchema then
        throw ''
          bidama "${name}": Bluefile.lock has schema ${toString lock.schema}, and
          mk-bidama.nix reads schema ${toString lockSchema}. Relock with the blue
          this distribution pins.
        ''
      else if lock.manifest.name != name then
        throw ''
          bidama "${name}": its Bluefile declares package("${lock.manifest.name}", …).
          The directory and the package must agree, or the registry resolves
          the wrong thing.
        ''
      else lock;

  # Dependency names, from the lock's evaluated `needs`.
  depsOf = lock: builtins.attrNames lock.manifest.needs;

  # The version `package(...)` declared — stated once, by the package, in blue.
  # A directory called `kazu-0.1.0` would be a second place for it to be wrong.
  versionOf = lock: lock.manifest.version;

  # Every package directory under a distribution root: a directory holding a
  # Bluefile. One definition, read by `mkDistribution` and `mkLockCheck`, so
  # the packages built and the packages gated cannot differ.
  packageDirs = root:
    lib.filterAttrs
      (n: t: t == "directory" && builtins.pathExists (root + "/${n}/Bluefile"))
      (builtins.readDir root);

in
rec {
  inherit lockOf depsOf versionOf packageDirs;

  # Build ONE bidama.
  #
  # `all` is the attrset of every built bidama, passed in so a package can
  # depend on its siblings — the knot `mkDistribution` ties below.
  mkBidama = { name, src, all ? { } }:
    let
      lock = lockOf { inherit name src; };
      version = versionOf lock;
      deps = depsOf lock;
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
    runCommand "bidama-${name}-${version}"
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

  # The catalogue of a distribution: every package, its gloss, and every
  # definition with its doc line, rendered by the `mokuroku` bidama.
  #
  # Discovery without a documentation server. The same markdown is committed
  # beside the distribution (GitHub renders it, codesearch indexes it), and
  # `mkCatalogCheck` below fails when the committed copy is stale. This is the
  # docs.rs / pkg.go.dev role, filled by a derivation.
  #
  # `bidamas` must include `mokuroku` itself, which is what renders the page.
  # A private distribution passes its own packages joined with the public ones,
  # and gets one catalogue covering both.
  mkCatalog = { blue, bidamas, name ? "bidama-catalog" }:
    mkGenerated {
      inherit blue bidamas name;
      program = builtins.toFile "catalog.b" ''
        use("mokuroku")
        write_catalog(getenv("GEN_OUT", ""))
      '';
    };

  # Fails when the committed catalogue differs from a fresh render.
  mkCatalogCheck = { blue, bidamas, committed, name ? "bidama-catalog-fresh" }:
    mkFreshCheck {
      inherit name committed;
      generated = mkCatalog { inherit blue bidamas; };
      regenerate = "nix run .#regen";
    };

  # One file generated by a blue program: the program writes it to $GEN_OUT.
  #
  # The general shape behind every committed artifact blue produces: the
  # catalogue, and Rust that blue writes for its own crates through the `sabi`
  # bidama (`crates/blue-lang-syntax/gen/kigou.b`). "We write bluelang, we
  # leverage nix": the program is blue, and nix runs it, caches it, and gates it.
  mkGenerated = { blue, bidamas, program, name }:
    runCommand name { } ''
      GEN_OUT=$out BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue run ${program}
    '';

  # Fails when a committed generated file differs from a fresh generation. The
  # message names `regenerate`, the command that rewrites the file in place,
  # so a stale file is fixed by that command and never by copying a store path
  # over it; then it shows the first lines of the difference.
  mkFreshCheck = { generated, committed, name, regenerate }:
    runCommand name { } ''
      if ! cmp -s ${generated} ${committed}; then
        echo "${name}: the committed file is stale. Regenerate it: ${regenerate}" >&2
        diff ${committed} ${generated} | head -40 >&2
        exit 1
      fi
      touch $out
    '';

  # A blue program as an executable: `blue run <program>` with the given
  # bidamas on BLUE_PATH, and `blue` itself on PATH so the program can run
  # other blue programs. The shape behind `nix run .#regen`, and behind the
  # Bluefile's `app` word once the engine lands (BLUE-STRUCTURE §5.5 P6).
  mkBlueApp = { blue, bidamas, program, name }:
    assert lib.assertMsg (makeWrapper != null)
      "mkBlueApp needs makeWrapper; pass the full pkgs set";
    runCommand name { nativeBuildInputs = [ makeWrapper ]; } ''
      mkdir -p $out/bin
      makeWrapper ${blue}/bin/blue $out/bin/${name} \
        --prefix BLUE_PATH : "${mkBluePath { inherit bidamas; }}" \
        --prefix PATH : "${blue}/bin" \
        --add-flags "run ${program}"
    '';

  # Fails when two packages define the same name.
  #
  # blue's namespace is flat across imports, so such a pair breaks any program
  # that imports both, and the error surfaces far from its cause (an arity
  # mismatch inside someone else's code). `owned`, when given, limits the
  # gate to collisions touching those packages: a private distribution checks
  # itself against the public one without failing on the public one's choices.
  mkCollisionCheck = { blue, bidamas, owned ? null, name ? "bidama-collisions" }:
    let
      query =
        if owned == null
        then "name_collisions(records)"
        else "name_collisions_touching(records, [${lib.concatMapStringsSep ", " (o: ''"${o}"'') owned}])";
    in runCommand name { } ''
      cat > gate.b <<'EOF'
      use("mokuroku")
      test "no two packages define one name"
        records = catalog_of(blue_path_roots(getenv("BLUE_PATH", "")))
        assert size(records) > 0
        found = ${query}
        println(found)
        assert is_empty(found) == true
      end
      EOF
      BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue test gate.b
      touch $out
    '';

  # Build every bidama in a distribution directory, wiring the graph.
  #
  # `lib.fix` ties the knot: each package receives the finished attrset, so
  # `retsu` can reference `kazu` without the distribution being ordered by hand.
  # A dependency CYCLE therefore surfaces as nix's own infinite-recursion error
  # rather than as a silently truncated graph — the loud failure is the correct
  # one, and blue's solver reports cycles too, so the two agree on rejection.
  mkDistribution = { root, pkgs }:
    lib.fix (all:
      lib.mapAttrs
        (name: _: mkBidama {
          inherit name all;
          src = root + "/${name}";
        })
        (packageDirs root));

  # Fails when any package's committed `Bluefile.lock` is not blue's
  # evaluation of the Bluefile beside it — edited without relocking, edited by
  # hand, or written by a blue that evaluates differently.
  #
  # One `blue bluefile --confirm` over every package: blue reports each one and
  # exits non-zero if any is stale, so this is a single command, not a loop.
  #
  # Red run, 2026-09-23: `needs("moji", "^0.1")` added to `bidamas/kazu/Bluefile`
  # without relocking → `nix build .#checks.aarch64-darwin.bidama-locks-fresh`
  # failed with `{"status":"stale","reason":{"kind":"hash",…}}` naming kazu and
  # `run \`blue lock …/kazu\``; the other 20 packages reported fresh. Reverted.
  # One Bluefile and its lock, confirmed: the lock must be blue's evaluation of
  # the Bluefile. For a project-level Bluefile (a repository's own build facts)
  # rather than a distribution of packages, which `mkLockCheck` covers.
  mkBluefileCheck = { blue, bluefile, lock, name ? "bluefile-lock-fresh" }:
    runCommand name { } ''
      mkdir project
      cp ${bluefile} project/Bluefile
      cp ${lock} project/Bluefile.lock
      ${blue}/bin/blue bluefile --confirm project/Bluefile
      touch $out
    '';

  mkLockCheck = { blue, root, name ? "bidama-locks-fresh" }:
    let
      manifests = map (n: "${root}/${n}/Bluefile") (lib.attrNames (packageDirs root));
    in
    runCommand name { } ''
      ${blue}/bin/blue bluefile --confirm ${lib.escapeShellArgs manifests}
      touch $out
    '';
}
