# The project engine: a blue project's `Bluefile.lock`, lowered to flake outputs.
#
# `theory/BLUE-STRUCTURE.md` §5.5 (P6): a blue project writes no nix. It states
# its build facts in its root `Bluefile`, `blue lock .` evaluates them into
# `Bluefile.lock`, and this file, written once in the blue repository, lowers
# them. A project's whole `flake.nix` is
#
#     outputs = { blue, ... }: blue.lib.project { src = ./.; };
#
# ## Stage 1 — the plan, fixed before the code (2026-09-24)
#
# The `blue-development-cycle` skill's first stage; `theory/BLUE.md` §I.1.
#
# ### The reuse map (read from source)
#
# | Need | Exists | Move |
# |---|---|---|
# | one bidama, one derivation; the graph under `lib.fix` | `bidamas/mk-bidama.nix` `mkBidama`, `mkDistribution` | reuse |
# | a BLUE_PATH root; `blue` wrapped with it (`--suffix`) | `mkBluePath`, `mkBlueWithBidamas`, `mkBlueApp` | extend: a binary name, tools on PATH |
# | lock freshness; generated files; the catalogue; collisions | `mkLockCheck`, `mkBluefileCheck`, `mkGenerated`, `mkFreshCheck`, `mkCatalog`, `mkCollisionCheck` | extend: several roots; the catalogue of the project's own roots; a positive control in the collision scan |
# | lowering a root `Bluefile.lock` (`generate`, `catalog`, the lock gates) | blue's own `flake.nix`, by hand | **move here**; blue's flake becomes this engine's first caller |
# | private bidamas composed over the public distribution; a runner; per-bidama tests; one derivation per program, each program alone in the store | makoto's `flake.nix` (333 hand-written lines) | **extract here**; makoto migrates later |
# | the vocabulary | `blue-lang-pkg` `WORDS`: package, needs, posture, source, packages, run, tool, check, app, generate, catalog | read, never re-derive |
# | rewriting generated files in place | `gen/regen.b`, reading the lock | reuse; it catalogues the lock's `packages` roots |
#
# NuPastel is the second project (after makoto) and blue's own root Bluefile
# is the third lowering, so the shape is extracted, not copied.
#
# ### The shape
#
# `projectFor { pkgs, blue, src, base }`, one system, returns
# `{ packages, checks, apps, runner, bidamas, bluePath }`; `lib.project`
# maps it over blue's systems and adds the runner as `default`. Every output
# is a lowering of one word:
#
# | Word | Lowers to |
# |---|---|
# | `package(name, v)` | `packages.<name>` and `default`: `blue` as `<name>`, with the project's BLUE_PATH and tools |
# | `packages(dir)` | each `dir/<pkg>/` built by `mkBidama` over `base` (blue's public distribution), plus `checks.bidama-test-<pkg>` (`blue test dir/<pkg>/<pkg>.b`), `bidama-collisions` (touching the project's packages), `bidama-locks-fresh` and `bidama-deps-resolve` (the version solver) |
# | the root lock itself | `checks.repository-lock-fresh` |
# | `needs(name, range)` | refused at evaluation when the distribution lacks `name` |
# | `tool(name)` | the nixpkgs attribute, on PATH for the runner, runs, checks and apps |
# | `run(name, file[, reads])` | `packages.<name>`: `blue run file` with `RUN_OUT=$out` and `RUN_READS/<read>` holding each read run's output |
# | `check(name, file)` | `checks.<name>`: `blue test file` |
# | `app(name, file)` | `apps.<name>`: `blue run file` from the caller's directory |
# | `generate(name, output, program)` | `packages.generated-<name>`, `checks.generated-<name>-fresh` |
# | `catalog(path)` | `packages.bidama-catalog`, `checks.bidama-catalog-fresh` |
# | `generate` or `catalog` | `apps.regen` |
# | `source(name, url, dir)` | **refused, not yet lowered** (fetchTree from the lock's pin is the named next step) |
# | `posture(when)` | nothing: a runtime floor, not a build fact |
#
# ### The idioms
#
# - **Closed world.** Every key of the lock's manifest is lowered or refused
#   by name. A word added to `WORDS` fails here until it has a row, so no
#   declared fact is silently dropped.
# - **Disjoint names.** A run, check or app named like an engine output is
#   refused, never merged over.
# - **Each program alone in the store**, so editing one program rebuilds only
#   its own derivation (makoto measured the whole-directory version rebuilding
#   every game on every doc edit). A program sees itself, the bidamas, its
#   tools and its reads; project data reaches it through a `run`.
# - **No vacuous gate.** A test file with no tests fails (`blue test`, since
#   this change); a run that writes nothing fails; the collision scan must see
#   every package it gates.
#
# ### The dependency order
#
# 1. `blue test` refuses a file with no tests (every check below stands on it).
# 2. The primitives in `mk-bidama.nix` gain what the engine needs.
# 3. This engine, and `project-fixture`, which exercises every lowered word.
# 4. blue's own flake lowers its root Bluefile through it.
# 5. NuPastel: a root Bluefile and the stub flake; the red runs.
#
# ## Tier
#
# Eval- and CI-caught, not unrepresentable: a word with no lowering, an unknown
# tool, a missing `needs` or a doubled name stops evaluation with a message
# naming it, and a stale lock fails `repository-lock-fresh`.

{ lib }:

let
  inherit (builtins) attrNames pathExists readFile fromJSON;

  # The lock layout this engine reads (`blue_lang_pkg::lock::LOCK_SCHEMA`,
  # `MANIFEST_SCHEMA`); `mk-bidama.nix` refuses other layouts the same way.
  lockSchema = 1;

  # Every key of a lock's `manifest`, and nothing else. A key outside this
  # list is a Bluefile word this engine does not lower, and is refused below:
  # the closed-world half of the plan above.
  known = [
    "schema" "name" "version" "needs" "when"
    "sources" "packages" "runs" "tools" "checks" "apps" "catalog" "generated"
  ];

  readLock = src:
    let path = src + "/Bluefile.lock"; in
    if !pathExists path then
      throw ''
        lib.project: ${toString src} has no Bluefile.lock. The engine reads
        blue's evaluation of the project's root Bluefile; write it with
        `blue lock .` and commit both.
      ''
    else
      let
        lock = fromJSON (readFile path);
        m = lock.manifest;
        unknown = attrNames (removeAttrs m known);
      in
      if lock.schema != lockSchema || m.schema != lockSchema then
        throw "lib.project: Bluefile.lock has schema ${toString lock.schema}; this engine reads ${toString lockSchema}. Relock with the blue this project pins."
      else if unknown != [ ] then
        throw ''
          lib.project: the Bluefile declares ${lib.concatStringsSep ", " unknown},
          which this engine does not lower. A declared fact is never dropped in
          silence: give the word a row in blue's nix/project.nix.
        ''
      else if m.sources != { } then
        throw ''
          lib.project: `source(...)` (${lib.concatStringsSep ", " (attrNames m.sources)}) is not
          lowered yet. The public distribution comes with the `blue` input;
          another distribution needs fetchTree over the lock's pin, which is
          the next row to build in blue's nix/project.nix.
        ''
      else lock;

  # Merge two attrsets whose names must not meet. A run called `default`, or a
  # check called `bidama-collisions`, is refused rather than laid over.
  disjoint = what: a: b:
    let both = attrNames (builtins.intersectAttrs a b); in
    if both == [ ] then a // b
    else throw "lib.project: ${what} ${lib.concatStringsSep ", " both} is declared twice (a Bluefile word and an engine output share the name)";

  # Every package directory under the project's `packages(...)` roots, as
  # { name, root }. Two roots holding one name are refused: the loader would
  # pick one by root order, and the build would pick one by attrset order.
  packagesOf = bl: src: dirs:
    let
      found = lib.concatMap
        (d:
          let root = src + "/${d}"; in
          if !pathExists root then throw "lib.project: packages(\"${d}\") names a directory the project does not have"
          else map (name: { inherit name root; }) (attrNames (bl.packageDirs root)))
        dirs;
      names = map (p: p.name) found;
      twice = lib.unique (lib.filter (n: lib.count (x: x == n) names > 1) names);
    in
    if twice != [ ] then throw "lib.project: package ${lib.concatStringsSep ", " twice} is in more than one packages(...) root"
    else found;

  # The whole lowering, for one system.
  #
  #   pkgs   nixpkgs for the system (tools resolve here)
  #   blue   the `blue` executable
  #   src    the project root, a path (`./.` in the project's flake)
  #   base   the distribution the project composes over; blue's public one by
  #          default, `{ }` for blue itself (its packages ARE that distribution)
  projectFor = { pkgs, blue, src, base ? null }:
    assert lib.assertMsg (builtins.isPath src)
      "lib.project: src must be a path; pass `src = ./.` from the project's flake.nix";
    let
      bl = import ../bidamas/mk-bidama.nix {
        inherit (pkgs) lib runCommand symlinkJoin makeWrapper;
      };
      lock = readLock src;
      m = lock.manifest;
      name = m.name;
      generated = m.generated or { };

      public = if base == null then bl.mkDistribution { root = ../bidamas; inherit pkgs; } else base;

      # Each program alone in the store: a derivation that runs it depends on
      # that file and nothing else in the project.
      programFile = f: builtins.path { path = src + "/${f}"; name = baseNameOf f; };

      tools = map
        (t: lib.attrByPath (lib.splitString "." t)
          (throw "lib.project: tool(\"${t}\") names no attribute in nixpkgs")
          pkgs)
        m.tools;

      # The project's own packages, composed over `public` in one graph, so a
      # private package's needs(...) on a public one resolves at build time.
      found = packagesOf bl src m.packages;
      ownNames = map (p: p.name) found;
      bidamas = lib.fix (all: public // lib.listToAttrs (map
        (p: lib.nameValuePair p.name (bl.mkBidama { inherit (p) name; inherit all; src = p.root + "/${p.name}"; }))
        found));
      own = lib.getAttrs ownNames bidamas;

      missingNeeds = lib.filter (d: !(bidamas ? ${d})) (attrNames m.needs);

      common = { inherit blue bidamas tools; };

      runner = bl.mkBlueWithBidamas { inherit blue bidamas tools name; bin = name; };

      runs = lib.fix (self: lib.mapAttrs
        (rn: r: bl.mkRun (common // {
          name = rn;
          program = programFile r.file;
          reads = lib.getAttrs r.reads self;
        }))
        m.runs);

      catalogue = lib.optionalAttrs (m.catalog != null) {
        bidama-catalog = bl.mkCatalog {
          inherit blue bidamas;
          root = bl.mkBluePath { bidamas = own; name = "${name}-packages"; };
        };
      };

      generatedPackages = lib.mapAttrs'
        (g: spec: lib.nameValuePair "generated-${g}" (bl.mkGenerated (common // {
          name = "generated-${g}";
          program = programFile spec.program;
        })))
        generated;

      packages = disjoint "package" runs (catalogue // generatedPackages);

      gates =
        lib.optionalAttrs (ownNames != [ ]) ({
          # Collisions touching the project's packages — with the public
          # distribution as much as with each other, so one package is enough
          # to need it.
          bidama-collisions = bl.mkCollisionCheck { inherit blue bidamas; owned = ownNames; };
          bidama-locks-fresh = bl.mkLockCheck { inherit blue; roots = map (d: src + "/${d}") m.packages; };
          # The version solver over every own package's needs, against the
          # same graph the build uses (mk-bidama.nix, mkResolveCheck).
          bidama-deps-resolve = bl.mkResolveCheck {
            inherit blue bidamas;
            manifests = map (p: p.root + "/${p.name}/Bluefile") found;
          };
        } // lib.listToAttrs (map
          (n: lib.nameValuePair "bidama-test-${n}" (bl.mkTestCheck (common // {
            name = "bidama-test-${n}";
            file = "${own.${n}}/${n}/${n}.b";
          })))
          ownNames))
        // {
          repository-lock-fresh = bl.mkBluefileCheck {
            inherit blue;
            name = "repository-lock-fresh";
            bluefile = src + "/Bluefile";
            lock = src + "/Bluefile.lock";
          };
        }
        // lib.optionalAttrs (m.catalog != null) {
          bidama-catalog-fresh = bl.mkFreshCheck {
            name = "bidama-catalog-fresh";
            committed = src + "/${m.catalog}";
            generated = catalogue.bidama-catalog;
            regenerate = "nix run .#regen";
          };
        }
        // lib.mapAttrs'
          (g: spec: lib.nameValuePair "generated-${g}-fresh" (bl.mkFreshCheck {
            name = "generated-${g}-fresh";
            regenerate = "nix run .#regen";
            committed = src + "/${spec.output}";
            generated = generatedPackages."generated-${g}";
          }))
          generated;

      checkWords = lib.mapAttrs
        (cn: c: bl.mkTestCheck (common // { name = cn; file = programFile c.file; }))
        m.checks;

      app = an: program: {
        type = "app";
        program = "${bl.mkBlueApp (common // { name = an; inherit program; })}/bin/${an}";
      };

      apps = disjoint "app"
        (lib.mapAttrs (an: a: app an (programFile a.file)) m.apps)
        (lib.optionalAttrs (m.catalog != null || generated != { }) {
          # gen/regen.b reads the project's Bluefile.lock from the directory
          # it is run in: `nix run .#regen` from the project root.
          regen = app "regen" ../gen/regen.b;
        });
    in
    if missingNeeds != [ ] then
      throw "lib.project: the Bluefile needs ${lib.concatStringsSep ", " missingNeeds}, which neither the project nor the distribution it composes over provides"
    else {
      inherit name runner bidamas packages apps;
      bluePath = bl.mkBluePath { inherit bidamas; name = "${name}-blue-path"; };
      checks = disjoint "check" gates checkWords;
    };
in
{
  inherit projectFor disjoint;

  # `blue.lib.project { src = ./.; }`: the flake outputs of a blue project,
  # for every system blue itself is built for. The runner is `packages.default`
  # and `apps.default`, and `packages.<project name>`.
  #
  #   systems   the systems to emit (blue's own)
  #   blueFor   system -> the `blue` executable
  #   pkgsFor   system -> nixpkgs
  mkProjectOutputs = { systems, blueFor, pkgsFor }: { src }:
    let
      per = lib.genAttrs systems (system: projectFor {
        inherit src;
        pkgs = pkgsFor system;
        blue = blueFor system;
      });
    in
    {
      packages = lib.mapAttrs
        (_: p: disjoint "package" p.packages { default = p.runner; ${p.name} = p.runner; })
        per;
      apps = lib.mapAttrs
        (_: p: disjoint "app" p.apps { default = { type = "app"; program = "${p.runner}/bin/${p.name}"; }; })
        per;
      checks = lib.mapAttrs (_: p: p.checks) per;
    };
}
