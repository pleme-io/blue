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

#
# ## A bidama is built only from canonical source
#
# blue compiles only canonical source (`blue_lang_pkg::canonical`), and a store
# path is read-only, so a non-canonical file in a built bidama could never be
# compiled by anyone who loads it. `mkBidama` therefore REFUSES a package whose
# `.b` files are not `blue fmt` canonical, naming each file — it does not
# format a copy, which would put a second author between the file a human
# reads and the file a program loads. So every bidama in the store is canonical
# by construction, private distributions included, and the loader's check on it
# always passes. That needs a `blue` to say what canonical is: pass it here
# (`blue.lib.bidamas`, `overlays.bidamas` and `lib.project` all do) or per call.
# Red run, 2026-09-27: a misformatted def appended to angou.b → the angou
# derivation failed with `angou.b: not formatted; run blue fmt --write angou.b`;
# restored, it built.

{ lib, runCommand, symlinkJoin ? null, makeWrapper ? null, makeBinaryWrapper ? null, blue ? null }:

let
  topBlue = blue;
  blueFor = what: given:
    if given != null then given
    else throw ''
      ${what} needs `blue`: a bidama is built only from canonical source, and
      blue's formatter is what says what canonical is. Pass `blue` to
      mk-bidama.nix (blue.lib.bidamas, overlays.bidamas and lib.project do).
    '';

  # The wrapper every blue executable gets. makeBinaryWrapper when the caller
  # passes it: a compiled exec wrapper, so no shell runs between the caller and
  # blue. makeWrapper (a bash script) stays as the fallback for callers that
  # pin the older argument set (makoto imports this file from a pinned blue).
  wrapper =
    if makeBinaryWrapper != null then { pkg = makeBinaryWrapper; fn = "makeBinaryWrapper"; }
    else if makeWrapper != null then { pkg = makeWrapper; fn = "makeWrapper"; }
    else null;
  wrapperGiven = what: lib.assertMsg (wrapper != null)
    "${what} needs makeBinaryWrapper (or makeWrapper); pass the full pkgs set";

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
  mkBidama = { name, src, all ? { }, blue ? topBlue }:
    let
      fmt = "${blueFor "mkBidama ${name}" blue}/bin/blue";
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
      # Canonical, or refused: `blue fmt --check` names every file that is not
      # (`<file>: not formatted; run blue fmt --write <file>`), in one command.
      # The package's own top-level `.b` files are the ones the loader reads.
      if ! (cd ${src} && ${fmt} fmt --check *.b); then
        echo "bidama ${name}: blue compiles only canonical source, and the file(s) above are not; run blue fmt --write on each and commit" >&2
        exit 1
      fi

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
  # `--suffix`, not `--prefix` or `--set`: the loader searches BLUE_PATH left
  # to right and the first match wins, so appending puts a caller's own roots
  # FIRST and these pinned ones after. A local checkout stays overridable,
  # which is the difference between a default and a cage. Until 2026-09-23
  # this said `--prefix` and claimed the same thing; it was false — a prefixed
  # distribution shadows every same-named package a caller supplies (measured:
  # a checkout's newer `ran` resolved to the pinned older one). mkOverrideCheck
  # below is the gate that caught it.
  #
  # `bin` names the executable (a project's runner is its own name, so it can
  # sit on a PATH beside `blue`), and `tools` are appended to PATH — appended,
  # like BLUE_PATH, so a node's own copy of a tool wins over the pinned one.
  mkBlueWithBidamas = { blue, bidamas, name ? "blue-with-bidamas", bin ? "blue", tools ? [ ] }:
    assert wrapperGiven "mkBlueWithBidamas";
    runCommand name { nativeBuildInputs = [ wrapper.pkg ]; meta.mainProgram = bin; } ''
      mkdir -p $out/bin
      ${wrapper.fn} ${blue}/bin/blue $out/bin/${bin} ${lib.concatStringsSep " " (
        [ ''--suffix BLUE_PATH : "${mkBluePath { inherit bidamas; }}"'' ]
        ++ lib.optional (tools != [ ]) ''--suffix PATH : "${lib.makeBinPath tools}"''
      )}
    '';

  # Proves the wrapper is a default and not a cage: a root on the caller's
  # BLUE_PATH holding a package with the SAME name as one in the distribution
  # must win. The program calls a marker only the caller's copy defines; the
  # negative control runs it without BLUE_PATH and must fail, so a pass cannot
  # come from a distribution that happens to define the marker too.
  mkOverrideCheck = { blue, bidamas, name ? "blue-path-override" }:
    let wrapped = mkBlueWithBidamas { inherit blue bidamas; }; in
    runCommand name { } ''
      mkdir -p override/retsu
      printf 'def precedence_marker()\n  42\nend\n' > override/retsu/retsu.b
      printf 'use("retsu")\nwrite_file(getenv("MARK", "mark"), to_s(precedence_marker()))\n' > prog.b
      if MARK=$PWD/control ${wrapped}/bin/blue run prog.b > control.log 2>&1; then
        echo "negative control passed: the distribution's retsu defines the marker"; exit 1
      fi
      BLUE_PATH=$PWD/override MARK=$out ${wrapped}/bin/blue run prog.b
      test "$(cat $out)" = 42
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
  # `root` is the one root to catalogue — a project's own packages, so a
  # private distribution's catalogue does not go stale every time the public
  # one changes (makoto's `tools/catalog.b` made the same choice). Without it,
  # every root on BLUE_PATH is catalogued.
  mkCatalog = { blue, bidamas, root ? null, name ? "bidama-catalog" }:
    let
      program = builtins.toFile "catalog.b" ''
        use("mokuroku")
        roots = blue_path_roots(getenv("CATALOG_ROOTS", getenv("BLUE_PATH", "")))
        write_file(getenv("GEN_OUT", ""), render_markdown(catalog_of(roots)))
      '';
    in
    runCommand name { } ''
      ${lib.optionalString (root != null) "CATALOG_ROOTS=${root} "}GEN_OUT=$out BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue run ${program}
    '';

  # Fails when the committed catalogue differs from a fresh render.
  mkCatalogCheck = { blue, bidamas, committed, root ? null, name ? "bidama-catalog-fresh" }:
    mkFreshCheck {
      inherit name committed;
      generated = mkCatalog { inherit blue bidamas root; };
      regenerate = "nix run .#regen";
    };

  # One file generated by a blue program: the program writes it to $GEN_OUT.
  #
  # The general shape behind every committed artifact blue produces: the
  # catalogue, and Rust that blue writes for its own crates through the `sabi`
  # bidama (`crates/blue-lang-syntax/gen/kigou.b`). "We write bluelang, we
  # leverage nix": the program is blue, and nix runs it, caches it, and gates it.
  # `root`, when given, is a directory of the project paths the program
  # declared it reads (the Bluefile's `generate(…, inputs)`), exported as
  # $GEN_ROOT; without it the derivation is exactly what it was before.
  mkGenerated = { blue, bidamas, program, name, tools ? [ ], root ? null }:
    runCommand name { nativeBuildInputs = tools; } ''
      ${lib.optionalString (root != null) "GEN_ROOT=${root} "}GEN_OUT=$out BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue run ${program}
    '';

  # A blue program run as its own cached derivation — the Bluefile's
  # `run(name, file[, reads])`. The program writes into the directory
  # `$RUN_OUT`, and finds each run it reads at `$RUN_READS/<name>`.
  #
  # A run that writes nothing FAILS. An empty output is what a program that
  # ignored `$RUN_OUT` produces, and it would otherwise be cached as a success
  # and read downstream as "no results" rather than as the bug it is.
  #
  # `reads` is an attrset of run derivations keyed by run name; the farm holds
  # one symlink per read, so a reader's inputs are exactly the runs it names
  # and nothing else (makoto's `-- reads:` line, as a declaration).
  mkRun = { blue, bidamas, program, name, reads ? { }, tools ? [ ] }:
    let
      farm = runCommand "${name}-reads" { } ''
        mkdir -p $out
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (r: d: "ln -s ${d} $out/${r}") reads)}
      '';
    in
    runCommand name { nativeBuildInputs = tools; passthru = { inherit reads; }; } ''
      mkdir -p $out
      RUN_OUT=$out RUN_READS=${farm} BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue run ${program}
      if [ -z "$(ls -A $out)" ]; then
        echo "run ${name}: the program wrote nothing into \$RUN_OUT" >&2
        exit 1
      fi
    '';

  # A test file as a check: `blue test`, whose status is the check's. A file
  # with no `test` blocks fails (`blue test` refuses it), so a check cannot
  # pass over nothing. The tally is the output, for reading after the fact.
  mkTestCheck = { blue, bidamas, file, name, tools ? [ ] }:
    runCommand name { nativeBuildInputs = tools; } ''
      BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue test ${file} > $out
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
  # Bluefile's `app` word (`nix/project.nix`, BLUE-STRUCTURE §5.5 P6).
  #
  # The program is a `.b` file (`program`) or its text (`source`, written into
  # the package as share/blue/<name>.b); exactly one. `env` is set on every run
  # as a default, so the caller's own environment wins where it names the same
  # variable. This is the one way a blue program becomes an installable
  # executable: on PATH, behind a launchd agent or a systemd unit (substrate's
  # `services.tehai` is a caller). substrate carried a copy of it,
  # `mkBlueProgramPackage`, for one day (2026-09-27), before recon found this.
  mkBlueApp = { blue, bidamas, name, program ? null, source ? null, tools ? [ ], env ? { } }:
    assert wrapperGiven "mkBlueApp";
    assert lib.assertMsg ((program == null) != (source == null))
      "mkBlueApp ${name}: give exactly one of `program` (a .b file) or `source` (its text)";
    let
      file = if program != null then "${program}" else "$out/share/blue/${name}.b";
      flags =
        [
          ''--suffix BLUE_PATH : "${mkBluePath { inherit bidamas; }}"''
          ''--prefix PATH : "${blue}/bin"''
        ]
        ++ lib.optional (tools != [ ]) ''--suffix PATH : "${lib.makeBinPath tools}"''
        ++ lib.mapAttrsToList (k: v: "--set-default ${lib.escapeShellArg k} ${lib.escapeShellArg v}") env
        ++ [ ''--add-flags "run --quiet ${file} --"'' ];
    in
    runCommand name
      ({ nativeBuildInputs = [ wrapper.pkg ]; meta.mainProgram = name; }
        // lib.optionalAttrs (source != null) { inherit source; passAsFile = [ "source" ]; })
      ''
        mkdir -p $out/bin
        ${lib.optionalString (source != null) ''mkdir -p $out/share/blue && cp "$sourcePath" "${file}"''}
        ${wrapper.fn} ${blue}/bin/blue $out/bin/${name} ${lib.concatStringsSep " " flags}
      '';

  # Fails when two packages define the same name.
  #
  # blue's namespace is flat across imports, so such a pair breaks any program
  # that imports both, and the error surfaces far from its cause (an arity
  # mismatch inside someone else's code). `owned`, when given, limits the
  # gate to collisions touching those packages: a private distribution checks
  # itself against the public one without failing on the public one's choices.
  #
  # With `owned`, the scan must also have READ every owned package (the
  # positive control): a scan that missed them reports zero collisions for
  # them and passes. Taken from makoto's `tools/collisions.b`. Red run,
  # 2026-09-24: owned = [retsu, not-a-package] → red; [retsu, kazu] → green.
  mkCollisionCheck = { blue, bidamas, owned ? null, name ? "bidama-collisions" }:
    let
      ownedList = "[${lib.concatMapStringsSep ", " (o: ''"${o}"'') owned}]";
      query =
        if owned == null
        then "name_collisions(records)"
        else "name_collisions_touching(records, ${ownedList})";
      seen = lib.optionalString (owned != null) ''
          scanned = map(fn(r) pkg_name(r) end, records)
          assert is_empty(filter(fn(o) contains(scanned, o) == false end, ${ownedList})) == true
      '';
    in runCommand name { } ''
      cat > gate.b <<'EOF'
      use("mokuroku")
      test "no two packages define one name"
        records = catalog_of(blue_path_roots(getenv("BLUE_PATH", "")))
        assert size(records) > 0
      ${seen}
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
  mkDistribution = { root, pkgs, blue ? topBlue }:
    lib.fix (all:
      lib.mapAttrs
        (name: _: mkBidama {
          inherit name all blue;
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

  # `roots` for a project with several `packages(...)` roots; `root` for one.
  # Fails when a Bluefile's needs cannot be SOLVED against `bidamas`, the same
  # package set the build composes. `mkLockCheck` proves a lock is blue's
  # evaluation of its Bluefile, and `mkBidama` only that a needed package
  # EXISTS; neither runs the version solver. So an unsatisfiable range passed
  # every gate. Red run 2026-09-25: nupastel's `abura` with
  # `needs("retsu", "^0.9")` against retsu 0.1.0 made `blue deps` exit 1
  # while `nix flake check` stayed green; with this check it goes red.
  mkResolveCheck = { blue, bidamas, manifests, name ? "bidama-deps-resolve" }:
    runCommand name { } ''
      for m in ${lib.escapeShellArgs manifests}; do
        BLUE_PATH=${mkBluePath { inherit bidamas; }} ${blue}/bin/blue deps "$m" >> $out || exit 1
      done
    '';

  # Fails when any `.b` file under `root` is not `blue fmt` canonical, naming
  # each one. blue's own repository holds its whole tree to the one layout this
  # way (the `blue-fmt` flake check); a package is held by `mkBidama` itself.
  # One command over every file, not a loop: `blue fmt --check` takes several.
  # Red run, 2026-09-27: one bad line in spec/arithmetic.b and one in
  # bidamas/angou/angou.b → red, naming both files; restored → green.
  mkFmtCheck = { blue, root, name ? "blue-fmt" }:
    runCommand name { } ''
      cd ${root}
      if ! find . -name '*.b' -exec ${blue}/bin/blue fmt --check {} +; then
        echo "${name}: the file(s) above are not canonical; run blue fmt --write on each" >&2
        exit 1
      fi
      touch $out
    '';

  mkLockCheck = { blue, root ? null, roots ? [ root ], name ? "bidama-locks-fresh" }:
    let
      manifests = lib.concatMap
        (r: map (n: "${r}/${n}/Bluefile") (lib.attrNames (packageDirs r)))
        roots;
    in
    runCommand name { } ''
      ${blue}/bin/blue bluefile --confirm ${lib.escapeShellArgs manifests}
      touch $out
    '';
}
