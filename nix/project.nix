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
# | `package(name, v)` | `packages.<name>` and `default`: `blue` as `<name>`, with the project's BLUE_PATH and tools; a service of the project's name takes `packages.<name>` and the runner keeps `default` |
# | `packages(dir)` | each `dir/<pkg>/` built by `mkBidama` over `base` (blue's public distribution), plus `checks.bidama-test-<pkg>` (`blue test dir/<pkg>/<pkg>.b`), `bidama-collisions` (touching the project's packages), `bidama-locks-fresh` and `bidama-deps-resolve` (the version solver) |
# | the root lock itself | `checks.repository-lock-fresh` |
# | `needs(name, range)` | refused at evaluation when the distribution lacks `name` |
# | `tool(name)` | the nixpkgs attribute, on PATH for the runner, runs, checks and apps |
# | `run(name, file[, reads])` | `packages.<name>`: `blue run file` with `RUN_OUT=$out` and `RUN_READS/<read>` holding each read run's output |
# | `check(name, file)` | `checks.<name>`: `blue test file` |
# | `app(name, file)` | `apps.<name>`: `blue run file` from the caller's directory |
# | `generate(name, output, program[, inputs])` | `packages.generated-<name>`, `checks.generated-<name>-fresh`; `inputs` are the project paths the program reads, under `$GEN_ROOT` |
# | `catalog(path)` | `packages.bidama-catalog`, `checks.bidama-catalog-fresh` |
# | `rule(code, file, def[, severity])` | `checks.project-rules-hold`: `blue check` on every `.b` of the project's packages and every run, check and app program, which runs the project rules beside the registry |
# | `generate`, `catalog` or `workload` | `apps.regen` |
# | every project | `checks.project` (every other check, one name for CI) and, on Linux, `apps.scan-images` (each service's scan floor and grype gate) |
# | `image(name, spec)` | Linux only: `packages.image-<name>` through `mkHardenedImageSet` (`nix/image.nix`; the direct `mkPackageImage` / `mkDistrolessImage` path is configured off, revived by `legacy.directImages = true`), `packages.image-<name>-manifest` (the archive's manifest.json, which `blue image build` reads), `checks.image-<name>-distroless` (`image-gate.b` over the closure) |
# | `workload(name, spec)` | configured off (refused) unless `legacy.rawWorkloads = true`; then `packages.workload-<name>` (`blue workload render`), `checks.workload-<name>-fresh` |
# | `service(name, spec)` | `nix/service.nix`: `packages.<name>`, `packages.service-<name>-tree` (haibi), `checks.service-<name>-{fresh,chart,serves}` (+ `-migrations` with a schema); on Linux `packages.image-<name>` through `mkHardenedImageSet`, `checks.image-<name>-distroless`, `apps.grype-scan-<name>`; the module trio and `overlays.default` |
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
#   tools and its reads; project data reaches it through a `run`, or, for a
#   generator, through the `inputs` it names (exactly those paths, and no
#   others, under `$GEN_ROOT`).
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
    "images" "workloads" "rules" "services"
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
  #   oci    substrate's image builders for the system (`substrate.lib.<system>`:
  #          mkPackageImage, mkDistrolessImage, hardenedBases); null where the
  #          caller has none, and an `image(...)` is then refused by name
  projectFor = { pkgs, blue, src, base ? null, oci ? null, moduleTrio ? null, legacy ? { } }:
    assert lib.assertMsg (builtins.isPath src)
      "lib.project: src must be a path; pass `src = ./.` from the project's flake.nix";
    let
      bl = import ../bidamas/mk-bidama.nix {
        inherit (pkgs) lib runCommand symlinkJoin makeWrapper makeBinaryWrapper;
        inherit blue;
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

      # A generator's declared inputs, each at its project-relative path in one
      # directory, so the program reads `$GEN_ROOT/<path>` in the sandbox and
      # `./<path>` under `nix run .#regen`. Each path is its own store object,
      # so the generator rebuilds when a path it reads changes, and not when
      # anything else in the project does.
      inputsRoot = g: ins: pkgs.runCommand "generated-${g}-inputs" { } (lib.concatMapStrings
        (d: ''
          mkdir -p "$out/${dirOf d}"
          ln -s ${builtins.path { path = src + "/${d}"; name = baseNameOf d; }} "$out/${d}"
        '')
        ins);

      generatedPackages = lib.mapAttrs'
        (g: spec: lib.nameValuePair "generated-${g}" (bl.mkGenerated (common // {
          name = "generated-${g}";
          program = programFile spec.program;
        } // lib.optionalAttrs ((spec.inputs or [ ]) != [ ]) {
          root = inputsRoot g spec.inputs;
        })))
        generated;

      images = m.images or { };
      workloads =
        if (m.workloads or { }) != { } && !rawWorkloads then
          throw ''
            lib.project: the Bluefile declares workload ${lib.concatStringsSep ", " (attrNames m.workloads)},
            whose raw Deployment+Service YAML lowering is configured off: a service(...)
            renders a chart with a generated values schema instead. Revive it with
            `blue.lib.project { src = ./.; legacy.rawWorkloads = true; }`.
          ''
        else m.workloads or { };

      # The project's bidamas as one BLUE_PATH root, for the image's runtime
      # and for the gate.
      bluePath = bl.mkBluePath { inherit bidamas; name = "${name}-blue-path"; };

      # `image(name, spec)`: blue, the program, its assets and its bidamas on
      # one of substrate's hardened bases. blue's Linux build is static musl,
      # so the default tier is distroless-static; a declared shell or tools
      # move it to `mkDistrolessImage` (distroless-glibc plus exactly those).
      # Everything the program reaches is under /app, its working directory,
      # in one derivation, so the image's closure (and the gate's) holds it.
      directImages = legacy.directImages or false;
      rawWorkloads = legacy.rawWorkloads or false;

      factoryImageOf = iname: spec:
        let
          program = programFile spec.program;
          app = pkgs.runCommand "image-${iname}-app" { } (''
            mkdir -p $out/app $out/share/blue
            ln -s ${program} $out/app/${baseNameOf spec.program}
            ln -s ${bluePath} $out/share/blue/bidamas
          '' + lib.concatMapStrings
            (a: ''
              mkdir -p "$out/app/${dirOf a}"
              ln -s ${builtins.path { path = src + "/${a}"; name = baseNameOf a; }} "$out/app/${a}"
            '')
            (spec.assets or [ ]));
        in
        (import ./image.nix { inherit lib pkgs oci blue; }).build {
          what = "image(\"${iname}\")";
          name = iname;
          inherit (spec) repository;
          version = m.version;
          program = "${app}/app/${baseNameOf spec.program}";
          args = spec.args or [ ];
          env = { BLUE_PATH = "${bluePath}"; };
          ports = spec.ports or [ ];
          contents = [ app ];
          workdir = "${app}/app";
          deviation = spec.deviation or null;
        };

      directImageOf = iname: spec:
        let
          deviation = spec.deviation or null;
          program = programFile spec.program;
          app = pkgs.runCommand "image-${iname}-app" { } (''
            mkdir -p $out/app $out/share/blue
            ln -s ${program} $out/app/${baseNameOf spec.program}
            ln -s ${bluePath} $out/share/blue/bidamas
          '' + lib.concatMapStrings
            (a: ''
              mkdir -p "$out/app/${dirOf a}"
              ln -s ${builtins.path { path = src + "/${a}"; name = baseNameOf a; }} "$out/app/${a}"
            '')
            (spec.assets or [ ]));
          common = {
            service = iname;
            package = blue;
            publishName = spec.repository;
            publishTag = m.version;
            entrypoint = [ "${blue}/bin/blue" "run" "--quiet" "${program}" ]
              ++ lib.optionals ((spec.args or [ ]) != [ ]) ([ "--" ] ++ spec.args);
            env = [ "BLUE_PATH=${bluePath}" ];
            exposedPorts = lib.listToAttrs (map (p: lib.nameValuePair "${toString p}/tcp" { }) (spec.ports or [ ]));
            workdir = "/app";
            extraContents = [ app ];
            labels = {
              "io.pleme.blue.project" = name;
              "io.pleme.blue.image" = iname;
            };
          };
          image =
            if deviation == null then
              oci.mkPackageImage (common // { base = oci.hardenedBases.distroless-static; })
            else
              oci.mkDistrolessImage (common // {
                shell = deviation.shell or false;
                entrypointTools = map
                  (t: lib.attrByPath (lib.splitString "." t)
                    (throw "lib.project: image(\"${iname}\") tools names `${t}`, no attribute in nixpkgs")
                    pkgs)
                  (deviation.tools or [ ]);
              });
          tier =
            if deviation == null then "distroless-static"
            else if deviation.shell or false then "shell"
            else "distroless-glibc";
        in
        { inherit image tier; };

      builtImages =
        if images == { } || !pkgs.stdenv.isLinux then { }
        else if oci == null then
          throw "lib.project: the Bluefile declares image ${lib.concatStringsSep ", " (attrNames images)}, and this engine was given no image builder (`oci`, substrate.lib.<system>)"
        else lib.mapAttrs (if directImages then directImageOf else factoryImageOf) images;

      # The archive's manifest.json: its layers, read by `blue image build`.
      imagePackages = lib.concatMapAttrs
        (iname: built: {
          "image-${iname}" = built.image;
          "image-${iname}-manifest" = pkgs.runCommand "image-${iname}-manifest" { } ''
            tar -xzOf ${built.image} manifest.json > $out
          '';
        })
        builtImages;

      # `image-gate.b` over the image's closure (substrate's closureInfo
      # passthru: base contents plus the image's own), against the tier the
      # entry declared. `refuses = true` is the positive control: the check
      # passes only when the gate refuses the image, naming a shell.
      imageGate = { name, image, tier, refuses ? false }:
        let gate = "BLUE_PATH=${bluePath} ${blue}/bin/blue run --quiet ${./image-gate.b} -- ${image.closureInfo}/store-paths ${tier}"; in
        pkgs.runCommand name { } (if refuses then ''
          if ${gate} > passed.log 2> refused.log; then
            echo "${name}: the gate passed an image with a shell as ${tier}" >&2
            exit 1
          fi
          grep -q 'a shell, and the image declares none' refused.log
          cp refused.log $out
        '' else ''
          ${gate} > $out
        '');

      imageChecks = lib.mapAttrs'
        (iname: built: lib.nameValuePair "image-${iname}-distroless"
          (imageGate { name = "image-${iname}-distroless"; inherit (built) image tier; }))
        builtImages;

      lockFile = builtins.path { path = src + "/Bluefile.lock"; name = "Bluefile.lock"; };

      lowered = import ./service.nix {
        inherit lib pkgs blue bl common src m name bluePath programFile lockFile imageGate oci moduleTrio;
      };

      # `workload(name, spec)`: the objects `blue workload render` writes from
      # the lock, the bytes the committed `output` must equal.
      workloadPackages = lib.mapAttrs'
        (w: _: lib.nameValuePair "workload-${w}" (pkgs.runCommand "workload-${w}.yaml" { } ''
          ${blue}/bin/blue workload render ${w} --lock ${lockFile} > $out
        ''))
        workloads;

      workloadChecks = lib.mapAttrs'
        (w: spec: lib.nameValuePair "workload-${w}-fresh" (bl.mkFreshCheck {
          name = "workload-${w}-fresh";
          regenerate = "blue workload render --write (or nix run .#regen)";
          committed = src + "/${spec.output}";
          generated = workloadPackages."workload-${w}";
        }))
        workloads;

      packages = disjoint "package" runs
        (disjoint "package" (catalogue // generatedPackages)
          (disjoint "package" (imagePackages // workloadPackages) lowered.packages));

      gates =
        lib.optionalAttrs (ownNames != [ ]) ({
          # Collisions touching the project's packages — with the public
          # distribution as much as with each other, so one package is enough
          # to need it.
          bidama-collisions = bl.mkCollisionCheck { inherit blue bidamas; owned = ownNames; scope = "namespace"; };
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
          generated
        // imageChecks
        // workloadChecks
        // lowered.checks;

      # `rule`: the project's rules hold over its own code. `blue check` finds
      # the rules from the Bluefiles above each file, so the files are checked
      # in a copy of the project (a `.git` marker stops the search at its
      # root); a project whose rules have nothing to check is refused, since
      # the gate would pass over nothing.
      rules = m.rules or { };
      ruleTargets =
        lib.concatMap
          (d: lib.concatMap
            (pkg: map (f: "${d}/${pkg}/${f}")
              (lib.filter (lib.hasSuffix ".b") (attrNames (builtins.readDir (src + "/${d}/${pkg}")))))
            (attrNames (bl.packageDirs (src + "/${d}"))))
          m.packages
        ++ map (r: r.file) (lib.attrValues m.runs ++ lib.attrValues m.checks ++ lib.attrValues m.apps);
      ruleGate = lib.optionalAttrs (rules != { }) {
        project-rules-hold =
          if ruleTargets == [ ] then
            throw "lib.project: the Bluefile declares rules (${lib.concatStringsSep ", " (attrNames rules)}) and has no package, run, check or app for them to check"
          else
            pkgs.runCommand "project-rules-hold" { nativeBuildInputs = tools; } ''
              work=$TMPDIR/project
              cp -r ${src} $work
              chmod -R u+w $work
              mkdir -p $work/.git
              export BLUE_PATH=${bl.mkBluePath { inherit bidamas; }}
              for f in ${lib.concatMapStringsSep " " lib.escapeShellArg ruleTargets}; do
                ${blue}/bin/blue check "$work/$f" > /dev/null
              done
              touch $out
            '';
      };

      checkWords = lib.mapAttrs
        (cn: c: bl.mkTestCheck (common // { name = cn; file = programFile c.file; }))
        m.checks;

      app = an: program: {
        type = "app";
        program = "${bl.mkBlueApp (common // { name = an; inherit program; })}/bin/${an}";
      };

      apps = disjoint "app"
        (lib.mapAttrs (an: a: app an (programFile a.file)) m.apps)
        (lowered.apps // lib.optionalAttrs (m.catalog != null || generated != { } || workloads != { } || lowered.services != { }) {
          # gen/regen.b reads the project's Bluefile.lock from the directory
          # it is run in: `nix run .#regen` from the project root.
          regen = app "regen" ../gen/regen.b;
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          scan-images = {
            type = "app";
            program = "${pkgs.writeShellScript "${name}-scan-images" (''
              set -e
            '' + lib.concatMapStrings (a: "${a.program}\n") (lib.attrValues lowered.apps))}";
          };
        });

      allChecks = disjoint "check" (disjoint "check" gates ruleGate) checkWords;
    in
    if missingNeeds != [ ] then
      throw "lib.project: the Bluefile needs ${lib.concatStringsSep ", " missingNeeds}, which neither the project nor the distribution it composes over provides"
    else {
      inherit name runner bidamas packages apps bluePath imageGate;
      inherit (lowered) services trios executables;
      checks = disjoint "check" allChecks {
        project = pkgs.runCommand "${name}-project" { } ''
          ${lib.concatMapStrings (c: "echo ${c} >> $out\n") (lib.attrValues allChecks)}
        '';
      };
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
  #   ociFor    system -> substrate's image builders, or null
  mkProjectOutputs = { systems, blueFor, pkgsFor, ociFor ? (_: null), moduleTrio ? null }: { src, legacy ? { } }:
    let
      per = lib.genAttrs systems (system: projectFor {
        inherit src moduleTrio legacy;
        pkgs = pkgsFor system;
        blue = blueFor system;
        oci = ociFor system;
      });
      any = per.${builtins.head systems};
      arm = a: lib.mapAttrs (_: t: t."${a}Module") any.trios;
    in
    lib.optionalAttrs (any.services != { }) {
      overlays.default = final: _prev:
        lib.mapAttrs (sn: _: per.${final.stdenv.hostPlatform.system}.executables.${sn}) any.services;
      nixosModules = arm "nixos";
      darwinModules = arm "darwin";
      homeManagerModules = arm "homeManager";
    }
    // {
      packages = lib.mapAttrs
        (_: p: disjoint "package" p.packages ({ default = p.runner; } // lib.optionalAttrs (!(p.services ? ${p.name})) { ${p.name} = p.runner; }))
        per;
      apps = lib.mapAttrs
        (_: p: disjoint "app" p.apps { default = { type = "app"; program = "${p.runner}/bin/${p.name}"; }; })
        per;
      checks = lib.mapAttrs (_: p: p.checks) per;
    };
}
