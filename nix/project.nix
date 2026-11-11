# The project engine: a blue project's `Bluefile.lock`, lowered to flake outputs.
#
# Phase P6: a blue project writes no nix. It states
# its build facts in its root `Bluefile`, `blue lock .` evaluates them into
# `Bluefile.lock`, and this file, written once in the blue repository, lowers
# them. A project's whole `flake.nix` is
#
#     outputs = { blue, ... }: blue.lib.project { src = ./.; };
#
# ## Stage 1 — the plan, fixed before the code (2026-09-24)
#
# The `blue-development-cycle` skill's first stage.
#
# ### The reuse map (read from source)
#
# | Need | Exists | Move |
# |---|---|---|
# | one bidama, one derivation; the graph under `lib.fix` | `bidamas/mk-bidama.nix` `mkBidama`, `mkDistribution` | reuse |
# | a BLUE_PATH root; `blue` wrapped with it as `BLUE_DIST` (`--suffix`) | `mkBluePath`, `mkBlueWithBidamas`, `mkBlueApp` | extend: a binary name, tools on PATH |
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
# | `packages(dir)` | each `dir/<pkg>/` built by `mkBidama` over `base` (blue's public distribution), plus `checks.bidama-test-<pkg>` (`blue test dir/<pkg>/<pkg>.b`), `checks.bidama-form-<pkg>` (the producer's form: `blue fmt --check` and `BLUE_FORM=own blue check`, under the blue this project pins; the build judges meaning only), `bidama-collisions` (touching the project's packages), `bidama-locks-fresh` and `bidama-deps-resolve` (the version solver) |
# | the root lock itself | `checks.repository-lock-fresh` |
# | `needs(name, range)` | refused at evaluation when the distribution lacks `name` |
# | `tool(name[, platforms])` | the nixpkgs attribute, on PATH for the runner, runs, checks and apps; with `platforms`, only on those (`linux`, `darwin`), and skipped elsewhere |
# | `run(name, file[, reads[, inputs]])` | `packages.<name>`: `blue run file` with `RUN_OUT=$out`, `RUN_READS/<read>` holding each read run's output, and `inputs` under `$GEN_ROOT` |
# | `check(name, file[, inputs])` | `checks.<name>`: `blue test file`; `inputs` are the project paths the tests read, under `$GEN_ROOT` |
# | `app(name, file)` | `apps.<name>` and `packages.<name>`: the program installed as a command (`mkBlueApp`, the project's bidamas and tools) that runs `blue run file` from the caller's directory, and an `overlays.default` entry `<name>` for a consumer's package set; with a runner, `packages.appliance-<name>` (`nix/bundle.nix`: `blue bundle` seals the program and the lock's verified capabilities onto `blue-appliance`, one executable held to them, pure when the lock records none) and, on Linux, `packages.appliance-<name>-image` (that executable alone in a scratch image) |
# | `generate(name, output, program[, inputs])` | `packages.generated-<name>`, `checks.generated-<name>-fresh`; `inputs` are the project paths the program reads, under `$GEN_ROOT` |
# | `catalog(path)` | `packages.bidama-catalog`, `checks.bidama-catalog-fresh` |
# | `rule(code, file, def[, severity])` | `checks.project-rules-hold`: `blue check` on every `.b` of the project's packages and every run, check and app program, which runs the project rules beside the registry |
# | `generate`, `catalog` or `workload` | `apps.regen` |
# | `projectFor { postMerge = [ name … ]; }` | those checks leave `checks` and `checks.project` and are `postMergeChecks`, run after the merge |
# | every project | `checks.project` (every other pre-merge check, one name for CI) and, on Linux, `apps.scan-images` (each service's scan floor and grype gate) |
# | `image(name, spec)` | Linux only: `packages.image-<name>` through `mkHardenedImageSet` (`nix/image.nix`; the direct `mkPackageImage` / `mkDistrolessImage` path is configured off, revived by `legacy.directImages = true`), `packages.image-<name>-manifest` (the archive's manifest.json, which `blue image build` reads), `checks.image-<name>-distroless` (`image-gate.b` over the closure) |
# | `workload(name, spec)` | configured off (refused) unless `legacy.rawWorkloads = true`; then `packages.workload-<name>` (`blue workload render`), `checks.workload-<name>-fresh` |
# | `service(name, spec)` | `nix/service.nix`: `packages.<name>`, `packages.service-<name>-tree` (haibi), `checks.service-<name>-{fresh,chart,serves}` (+ `-migrations` with a schema); a `runtime: :wasm` service (the default) also `packages.service-<name>-component` (blue's engine component plus the program bundle at `app/`) and `checks.service-<name>-component-serves` (the component under wasmtime answers its probe); on Linux `packages.image-<name>` through `mkHardenedImageSet`, `checks.image-<name>-distroless`, `apps.grype-scan-<name>`; the module trio and `overlays.default` |
# | `frontend(name, spec)` | `checks.frontend-<name>-declared`: every `views`, `tokens` and `schema` path must exist in the project, and the declaration is written out as JSON; the renderers it lowers to come with FRONTEND-PLAN F11 |
# | `vm_check(name, spec)` | `nix/vm-check.nix`: on Linux `packages.vm-<name>-<kernel>` (`testers.runNixOSTest`, requiring `kvm` and `nixos-test`: `vm-run.b` runs the control, then the program, and judges the release, the expected text and both exits; its output is the log); everywhere `checks.vm-<name>-absent`, a file saying none of it ran in this check |
# | `registry(backend, spec)` | `packages.registry-<backend>` (`blue registry render`, judged by `touroku`), `checks.registry-<backend>-fresh` against the committed `output`; `package`'s `visibility` is recorded and read only by `touroku` (docs/REGISTRY.md) |
# | `source(name, url, dir)` | `builtins.fetchTree` over the lock's pin (`rev` and `narHash`; FlakeHub's `fetch` tarball when the pin has one); every package under `dir` joins the graph beside the project's own. A name two roots hold is refused. A source the lock refused adds nothing, and a `needs` it would meet names its reason |
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
    "sources" "packages" "runs" "tools" "tool_platforms" "checks" "apps" "catalog" "generated"
    "images" "workloads" "rules" "services" "frontends" "vm_checks"
    "visibility" "registries" "reach" "allow" "virtualized" "receipts" "floors"
    "bounds" "tier" "target" "verify"
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
      else if (m ? allow || m ? virtualized) && !(lock ? capabilities) then
        throw ''
          lib.project: the Bluefile declares `allow` or a `virtualize` provider,
          and Bluefile.lock records no verified capabilities. `blue lock .`
          verifies every package's floor fits under the ceiling and writes the
          record, or refuses and names the path to the breach.
        ''
      else lock;

  fetchArgs = pin:
    if (pin.fetch or null) != null then { type = "tarball"; url = pin.fetch; inherit (pin) narHash; }
    else
      let
        ref = removeAttrs (builtins.parseFlakeRef pin.url) [ "dir" ];
        hosted = builtins.elem ref.type [ "github" "gitlab" "sourcehut" ];
      in
      (if hosted then removeAttrs ref [ "ref" ] else ref) // { inherit (pin) rev narHash; };

  sourcesOf = fetchTree: lock: lib.mapAttrs
    (sn: s:
      let pin = lock.sources.${sn} or null; in
      if pin == null then { refused = lock.refused.${sn} or "Bluefile.lock holds no pin; run `blue lock .`"; }
      else if pin.url != s.url then { refused = "the lock pins ${pin.url}, the Bluefile declares ${s.url}; run `blue lock .`"; }
      else { root = "${fetchTree (fetchArgs pin)}/${s.dir}"; })
    lock.manifest.sources;

  # Merge two attrsets whose names must not meet. A run called `default`, or a
  # check called `bidama-collisions`, is refused rather than laid over.
  disjoint = what: a: b:
    let both = attrNames (builtins.intersectAttrs a b); in
    if both == [ ] then a // b
    else throw "lib.project: ${what} ${lib.concatStringsSep ", " both} is declared twice (a Bluefile word and an engine output share the name)";

  # Every package directory under the project's `packages(...)` roots, as
  # { name, root }. Two roots holding one name are refused: the loader would
  # pick one by root order, and the build would pick one by attrset order.
  packagesOf = bl: src: dirs: fetched:
    let
      own = lib.concatMap
        (d:
          let root = src + "/${d}"; in
          if !pathExists root then throw "lib.project: packages(\"${d}\") names a directory the project does not have"
          else map (name: { inherit name root; source = null; }) (attrNames (bl.packageDirs root)))
        dirs;
      sourced = lib.concatLists (lib.mapAttrsToList
        (sn: f:
          if f ? refused then [ ]
          else if !pathExists f.root then throw "lib.project: source(\"${sn}\") names a directory its pinned tree does not have (${f.root})"
          else map (name: { inherit name; inherit (f) root; source = sn; }) (attrNames (bl.packageDirs f.root)))
        fetched);
      all = own ++ sourced;
      names = map (p: p.name) all;
      twice = lib.unique (lib.filter (n: lib.count (x: x == n) names > 1) names);
      whereIs = n: lib.concatStringsSep " and " (map (p: if p.source == null then "packages(...)" else "source(\"${p.source}\")") (lib.filter (p: p.name == n) all));
    in
    if twice != [ ] then throw "lib.project: package ${lib.concatMapStringsSep ", " (n: "${n} (in ${whereIs n})") twice} is in more than one root; one root holds a name"
    else { inherit own sourced; };

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
  #   appliance  the `blue-appliance` runner for the system (static musl on
  #          Linux), or null, and an `app` then lowers to no appliance
  projectFor = { pkgs, blue, src, fetchTree ? builtins.fetchTree, base ? null, oci ? null, moduleTrio ? null, legacy ? { }, chartLibraries ? { }, component ? null, appliance ? null, tameshi ? null, postMerge ? [ ], shards ? { } }:
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

      platform = if pkgs.stdenv.isLinux then "linux" else if pkgs.stdenv.isDarwin then "darwin" else pkgs.stdenv.hostPlatform.parsed.kernel.name;
      onThisPlatform = t: !((m.tool_platforms or { }) ? ${t}) || lib.elem platform m.tool_platforms.${t};

      tools = map
        (t: lib.attrByPath (lib.splitString "." t)
          (throw "lib.project: tool(\"${t}\") names no attribute in nixpkgs")
          pkgs)
        (lib.filter onThisPlatform m.tools);

      # The project's own packages, composed over `public` in one graph, so a
      # private package's needs(...) on a public one resolves at build time.
      fetched = sourcesOf fetchTree lock;
      roots = packagesOf bl src m.packages fetched;
      found = roots.own;
      ownNames = map (p: p.name) found;
      bidamas = lib.fix (all: public // lib.listToAttrs (map
        (p: lib.nameValuePair p.name (bl.mkBidama { inherit (p) name; inherit all; src = if p.source == null then p.root + "/${p.name}" else "${p.root}/${p.name}"; }))
        (roots.sourced ++ found)));
      own = lib.getAttrs ownNames bidamas;
      reachOf = n: lib.getAttrs (bl.closureOf bidamas [ n ]) bidamas;
      # The levels below a bidama, each tested by its own file: a directory
      # holding `<d>/<d>.b`, or a file opening with `namespace()`. A level with
      # no tests fails its check, as a bidama does.
      levelsOf = dir: rel:
        let entries = builtins.readDir dir;
        in lib.concatMap
          (e:
            let
              sub = dir + "/${e}";
              at = name: if rel == "" then name else "${rel}/${name}";
            in
            if entries.${e} == "directory" && pathExists (sub + "/${e}.b")
            then [{ path = at e; file = "${at e}/${e}.b"; }] ++ levelsOf sub (at e)
            else if entries.${e} == "regular" && lib.hasSuffix ".b" e && builtins.elem "namespace()" (lib.splitString "\n" (readFile sub))
            then [{ path = at (lib.removeSuffix ".b" e); file = at e; }]
            else [ ])
          (attrNames entries);

      missingNeeds = lib.filter (d: !(bidamas ? ${d})) (attrNames m.needs);
      refusedSources = lib.filterAttrs (_: f: f ? refused) fetched;

      common = { inherit blue bidamas tools; };

      runner = bl.mkBlueWithBidamas { inherit blue bidamas tools name; bin = name; };

      runs = lib.fix (self: lib.mapAttrs
        (rn: r: bl.mkRun (common // {
          name = rn;
          program = programFile r.file;
          reads = lib.getAttrs r.reads self;
        } // lib.optionalAttrs ((r.inputs or [ ]) != [ ]) {
          root = inputsRoot "run-${rn}" r.inputs;
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
      inputsRoot = g: ins: pkgs.runCommand "${g}-inputs" { } (lib.concatMapStrings
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
          root = inputsRoot "generated-${g}" spec.inputs;
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

      registries = m.registries or { };

      registryPackages = lib.mapAttrs'
        (b: _: lib.nameValuePair "registry-${b}" (pkgs.runCommand "registry-${b}.yml" { } ''
          ${blue}/bin/blue registry render ${b} --lock ${lockFile} > $out
        ''))
        registries;

      registryChecks = lib.mapAttrs'
        (b: spec: lib.nameValuePair "registry-${b}-fresh" (bl.mkFreshCheck {
          name = "registry-${b}-fresh";
          regenerate = "blue registry render --write (or nix run .#regen)";
          committed = src + "/${spec.output}";
          generated = registryPackages."registry-${b}";
        }))
        registries;

      frontendChecks = lib.mapAttrs'
        (fname: spec:
          let
            paths = spec.views ++ lib.optional (spec ? tokens) spec.tokens ++ lib.optional (spec ? schema) spec.schema;
            missing = lib.filter (p: !pathExists (src + "/${p}")) paths;
          in
          lib.nameValuePair "frontend-${fname}-declared" (
            if missing != [ ] then
              throw "lib.project: frontend(\"${fname}\") names ${lib.concatStringsSep ", " missing}, which the project does not have"
            else pkgs.writeText "frontend-${fname}-declared.json" (builtins.toJSON spec)))
        (m.frontends or { });

      bundled = import ./bundle.nix {
        inherit lib pkgs oci blue src m name bluePath;
        runner = appliance;
      };

      vms = import ./vm-check.nix { inherit lib pkgs blue src; checks = m.vm_checks or { }; };

      lowered = import ./service.nix {
        inherit lib pkgs blue bl common src m name bluePath programFile lockFile imageGate oci moduleTrio chartLibraries component;
        projectBidamas =
          let carried = map (p: p.name) (roots.sourced ++ found); in
          if carried == [ ] then null
          else bl.mkBluePath { bidamas = lib.getAttrs carried bidamas; name = "${name}-component-bidamas"; };
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

      commands = lib.mapAttrs
        (an: a: bl.mkBlueApp (common // { name = an; program = programFile a.file; }))
        m.apps;

      packages = disjoint "package" runs
        (disjoint "package" commands
          (disjoint "package" (catalogue // generatedPackages)
            (disjoint "package" (imagePackages // workloadPackages // registryPackages)
              (disjoint "package" vms.packages (disjoint "package" bundled.packages lowered.packages)))));

      gates =
        lib.optionalAttrs (ownNames != [ ]) ({
          # Collisions touching the project's packages — with the public
          # distribution as much as with each other, so one package is enough
          # to need it.
          bidama-collisions = bl.mkCollisionCheck { inherit blue bidamas; owned = ownNames; scope = "namespace"; };
          bidama-locks-fresh = bl.mkLockCheck { inherit blue bluePath; roots = map (d: src + "/${d}") m.packages; };
          # The version solver over every own package's needs, against the
          # same graph the build uses (mk-bidama.nix, mkResolveCheck).
          bidama-deps-resolve = bl.mkResolveCheck {
            inherit blue bidamas;
            manifests = map (p: p.root + "/${p.name}/Bluefile") found;
          };
        } // lib.listToAttrs (map
          (n: lib.nameValuePair "bidama-test-${n}" (bl.mkTestCheck (common // {
            name = "bidama-test-${n}";
            bidamas = reachOf n;
            file = "${own.${n}}/${n}/${n}.b";
          })))
          ownNames)
        // lib.listToAttrs (lib.concatMap
          (p: map
            (level: lib.nameValuePair "bidama-test-${p.name}-${lib.replaceStrings [ "/" ] [ "-" ] level.path}" (bl.mkTestCheck (common // {
              name = "bidama-test-${p.name}-${lib.replaceStrings [ "/" ] [ "-" ] level.path}";
              bidamas = reachOf p.name;
              file = "${own.${p.name}}/${p.name}/${level.file}";
            })))
            (levelsOf (p.root + "/${p.name}") ""))
          found)
        // lib.listToAttrs (map
          (n: lib.nameValuePair "bidama-form-${n}" own.${n}.formCheck)
          ownNames))
        // {
          repository-lock-fresh = bl.mkBluefileCheck {
            inherit blue;
            name = "repository-lock-fresh";
            bluefile = src + "/Bluefile";
            lock = src + "/Bluefile.lock";
          };
          reuse-ratchet = pkgs.runCommand "reuse-ratchet" { } ''
            BLUE_PATH=${bl.mkBluePath { inherit bidamas; }} ${blue}/bin/blue census --reuse ${src} > $out || { cat $out; exit 1; }
          '';
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
        // registryChecks
        // frontendChecks
        // vms.checks
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

      testCheck = cn: c: extra: bl.mkTestCheck (common // { name = cn; file = programFile c.file; }
        // lib.optionalAttrs ((c.inputs or [ ]) != [ ]) { root = inputsRoot "check-${cn}" c.inputs; }
        // extra);

      filesUnder = dir: rel:
        lib.concatLists (lib.mapAttrsToList
          (n: t:
            let r = if rel == "" then n else "${rel}/${n}"; in
            if t == "directory" then filesUnder dir r else [ r ])
          (builtins.readDir (if rel == "" then dir else dir + "/${rel}")));

      shardChecks = cn: c: s:
        let
          parts = lib.filter (lib.hasSuffix s.suffix) (filesUnder (src + "/${s.dir}") "");
          slug = p: lib.replaceStrings [ "/" ] [ "-" ] (lib.removeSuffix s.suffix p);
          each = lib.listToAttrs (map
            (p: lib.nameValuePair "${cn}-${slug p}" (testCheck "${cn}-${slug p}" c { env.${s.env} = p; }))
            parts);
        in
        if parts == [ ] then
          throw "lib.project: shards.${cn} finds no ${s.suffix} file under ${s.dir}"
        else if lib.length (lib.attrNames each) != lib.length parts then
          throw "lib.project: shards.${cn} names two files under ${s.dir} with one check name"
        else
          each // {
            ${cn} = pkgs.runCommand cn { } ''
              ${lib.concatMapStrings (d: "echo ${d} >> $out\n") (lib.attrValues each)}
            '';
          };

      checkWords =
        let unknownShards = attrNames (removeAttrs shards (attrNames m.checks)); in
        if unknownShards != [ ] then
          throw "lib.project: shards names ${lib.concatStringsSep ", " unknownShards}, which the Bluefile declares no check(...) for"
        else
          lib.concatMapAttrs
            (cn: c: if shards ? ${cn} then shardChecks cn c shards.${cn} else { ${cn} = testCheck cn c { }; })
            m.checks;

      receiptChecks = lib.mapAttrs'
        (cn: r: lib.nameValuePair "${cn}-receipt" (
          if tameshi == null then
            throw "lib.project: the Bluefile declares receipt(\"${cn}\", …), and this engine was given no `tameshi`: blue's flake input `tameshi`, passed to projectFor or mkProjectOutputs as `tameshi`"
          else
            let
              system = pkgs.stdenv.hostPlatform.system;
              inherit (checkWords.${cn} or (throw "lib.project: receipt(\"${cn}\") names no check(...) of this Bluefile")) test;
              attested = tameshi.lib.wrapTest {
                inherit system;
                inherit (r) controls;
                inherit (test) command;
                name = "${cn}-attested";
                target = { kind = "nix-output"; path = if test.root != null then test.root else test.bluePath; };
                test = { runner = "blue"; path = test.file; };
                nativeBuildInputs = test.tools;
              };
              receipt = "${attested}/tameshi-receipt.v1.json";
            in
            pkgs.runCommand "${cn}-receipt" { nativeBuildInputs = [ tameshi.packages.${system}.tameshi ]; passthru = { inherit attested; }; } (''
              mkdir -p $out
              cp ${attested}/* $out/
              tameshi ledger fold $out/ledger.json ${receipt}
            '' + lib.concatMapStrings
              (c: ''
                tameshi ledger prove $out/ledger.json --receipt ${receipt} --control ${c} --out $out/${c}.proof.json
                tameshi ledger verify $out/${c}.proof.json --ledger $out/ledger.json --receipt ${receipt} --control ${c} --expect-status PASS || {
                  echo "${cn}-receipt: the receipt does not record ${cn} as PASS for ${c}; the run is ${attested.run}" >&2
                  cat ${attested.run}/stdout.log ${attested.run}/stderr.log >&2
                  exit 1
                }
              '')
              r.controls)))
        (m.receipts or { });

      app = an: program: {
        type = "app";
        program = "${bl.mkBlueApp (common // { name = an; inherit program; })}/bin/${an}";
      };

      apps = disjoint "app"
        (lib.mapAttrs (an: c: { type = "app"; program = "${c}/bin/${an}"; }) commands)
        (lowered.apps // lib.optionalAttrs (m.catalog != null || generated != { } || workloads != { } || registries != { } || lowered.services != { }) {
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

      allChecks = disjoint "check" (disjoint "check" (disjoint "check" gates ruleGate) checkWords) receiptChecks;
      postMergeNames = lib.concatMap
        (cn: if shards ? ${cn} && m.checks ? ${cn} then attrNames (shardChecks cn m.checks.${cn} shards.${cn}) else [ cn ])
        postMerge;
      preMergeChecks = builtins.removeAttrs allChecks postMergeNames;
      postMergeChecks = lib.filterAttrs (n: _: lib.elem n postMergeNames) allChecks;
    in
    if missingNeeds != [ ] then
      throw "lib.project: the Bluefile needs ${lib.concatStringsSep ", " missingNeeds}, which neither the project nor the distribution it composes over provides${lib.concatStrings (lib.mapAttrsToList (sn: f: "; source(\"${sn}\") added nothing: ${f.refused}") refusedSources)}"
    else {
      inherit name runner bidamas packages apps commands bluePath imageGate postMergeChecks postMergeNames shards;
      toolchain = pkgs.symlinkJoin { name = "${name}-toolchain"; paths = tools; };
      inherit (lowered) services trios executables;
      checks = disjoint "check" preMergeChecks {
        project = pkgs.runCommand "${name}-project" { } ''
          ${lib.concatMapStrings (c: "echo ${c} >> $out\n") (lib.attrValues preMergeChecks)}
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
  #   applianceFor  system -> the `blue-appliance` runner, or null
  mkProjectOutputs = { systems, blueFor, pkgsFor, ociFor ? (_: null), moduleTrio ? null, chartLibraries ? { }, componentFor ? (_: null), applianceFor ? (_: null), tameshi ? null }: { src, legacy ? { }, shards ? { } }:
    let
      per = lib.genAttrs systems (system: projectFor {
        inherit src moduleTrio legacy chartLibraries tameshi shards;
        pkgs = pkgsFor system;
        blue = blueFor system;
        oci = ociFor system;
        component = componentFor system;
        appliance = applianceFor system;
      });
      any = per.${builtins.head systems};
      arm = a: lib.mapAttrs (_: t: t."${a}Module") any.trios;
    in
    lib.optionalAttrs (any.services != { } || any.commands != { }) {
      overlays.default = final: _prev:
        let at = per.${final.stdenv.hostPlatform.system}; in
        disjoint "overlay entry"
          (lib.mapAttrs (sn: _: at.executables.${sn}) any.services)
          (lib.mapAttrs (an: _: at.commands.${an}) any.commands);
    }
    // lib.optionalAttrs (any.services != { }) {
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
