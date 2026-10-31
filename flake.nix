{
  description = "blue — a Ruby/Elixir surface on tatara-lisp and Rust";

  inputs = {
    nixpkgs.follows = "substrate/nixpkgs";
    crate2nix.url = "github:nix-community/crate2nix";
    flake-utils.url = "github:numtide/flake-utils";
    substrate = {
      url = "github:pleme-io/substrate";
    };
    helmworks = {
      url = "github:pleme-io/helmworks";
      flake = false;
    };
    # blue native's emitter: a typed Rust AST as JSON in, Rust out
    # (nix/native.nix).
    tatara-rust-ast = {
      url = "github:pleme-io/tatara-rust-ast";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.substrate.follows = "substrate";
      inputs.crate2nix.follows = "crate2nix";
      inputs.flake-utils.follows = "flake-utils";
    };
    tameshi = {
      url = "github:pleme-io/tameshi";
      inputs.substrate.follows = "substrate";
    };
  };

  outputs = {
    self,
    nixpkgs,
    crate2nix,
    flake-utils,
    substrate,
    helmworks,
    tatara-rust-ast,
    tameshi,
  }: let
    inherit (nixpkgs) lib;
    inherit (lib) mkOption types;

    # ── The bounds, declared ONCE ─────────────────────────────────────────
    #
    # Each entry drives four things that would otherwise be four places to
    # forget: the Nix option, its type, its default, and the YAML key serde
    # reads on the Rust side. The `yaml` field is the whole translation layer
    # between nixpkgs' camelCase option convention and `BlueConfig`'s snake_case
    # fields — stated here, once, instead of relied on implicitly by spelling
    # the two names the same.
    #
    # All are BOUNDS, never preferences: raising or lowering one changes no
    # program's meaning, only whether a pathological input is refused. That rule
    # is what decides admission here, and it is argued in full in
    # `blue-lang-cli/src/config.rs`. Do not add a third knob without reading it.
    #
    # The defaults are the numbers `BlueConfig::prescribed_default()` returns by
    # naming `blue_lang_pkg::DEFAULT_MAX_STEPS` / `blue_lang_syntax::MAX_EXPR_DEPTH`.
    # Nix cannot read a Rust constant, so this is the one unavoidable restatement
    # — `prescribed_default_is_the_constants_themselves` pins the Rust side and
    # `every_field_is_emitted_by_the_module_trio` pins the key names against this
    # file.
    bounds = {
      solverMaxSteps = {
        yaml = "solver_max_steps";
        default = 100000;
        # An upper limit, not decoration: the solver is a search, and a value
        # large enough to run for hours is indistinguishable from the hang the
        # bound exists to prevent.
        type = types.ints.between 1 100000000;
        description = ''
          Search steps `blue deps` allows the version solver before it reports
          rather than keeps looking. Raising it never changes which resolution
          is correct — only how long blue is willing to search for one.
        '';
      };
      maxExprDepth = {
        yaml = "max_expr_depth";
        default = 256;
        # The ceiling is deliberately far below the measured stack-overflow
        # point. Above it the failure stops being a typed `Err` and becomes a
        # SIGABRT that `catch_unwind` cannot catch, so this is the line between
        # "refused" and "the process dies".
        type = types.ints.between 1 4096;
        description = ''
          Expression/statement nesting the parser accepts before refusing.
          Raising it never changes what a program means; it moves the line
          between a typed error and a stack overflow.
        '';
      };
      maxCallDepth = {
        yaml = "max_call_depth";
        # tatara-lisp-eval's `vm::DEFAULT_MAX_DEPTH`, named on the Rust side by
        # `ExecutionBounds::DEFAULT`.
        default = 100000;
        # The evaluator grows its stack on demand, so this bounds memory rather
        # than a thread's stack: about 3 KB a frame, measured at 100k frames
        # (310 MB resident). The ceiling keeps a typo from asking for tens of GB.
        type = types.ints.between 1 10000000;
        description = ''
          Nested (non-tail) calls a program may have alive at once. Past it the
          call is refused with a catchable `depth-exceeded` error naming the
          function. Tail calls do not count.
        '';
      };
      maxSteps = {
        yaml = "max_steps";
        # Unbounded: a run longer than any finite count worked before this
        # bound existed (simulations, tools on nodes), and a default must not
        # take that away. A host running untrusted code sets one.
        default = null;
        type = types.nullOr types.ints.positive;
        description = ''
          Evaluation steps a run may take, or null for unbounded. Past it the
          run ends in a `fuel-exhausted` error naming the function; a `try`
          observes it but cannot spend past it. A long simulation raises it.
        '';
      };
      maxAllocBytes = {
        yaml = "max_alloc_bytes";
        # Unbounded, for the reason maxSteps is: a run that holds a lot of
        # memory worked before this bound existed.
        default = null;
        type = types.nullOr types.ints.positive;
        description = ''
          Live bytes one evaluation of code its caller wrote may hold (`blue
          run`, an appliance, each test of `blue test`, each process they
          spawn), or null for unbounded.
          Past it the run ends in a fatal `memory-exhausted` error and a
          process exits a runaway its supervisor sees.
        '';
      };
      guestMaxAllocBytes = {
        yaml = "guest_max_alloc_bytes";
        # `blue_lang_runtime::memory::GUEST_MAX_ALLOC_BYTES`: 1 GiB, a runaway
        # guard for code a door did not write, not a quota.
        default = 1073741824;
        type = types.nullOr types.ints.positive;
        description = ''
          Live bytes one evaluation may hold at a door that runs code it did
          not write: a session (`eval`, `repl`, `serve`), live evaluation in
          the editor, a project rule, a Bluefile. Null lifts it.
        '';
      };
    };

    boundOptions = lib.mapAttrs (_: b: mkOption { inherit (b) type default description; }) bounds;

    # cfg → { solver_max_steps = <int>; max_expr_depth = <int>; }, the exact
    # shape `BlueConfig` deserializes.
    boundsYaml = cfg: lib.mapAttrs' (nixName: b: lib.nameValuePair b.yaml cfg.${nixName}) bounds;

    # True when the operator has moved any bound off its shipped default.
    boundsCustomized = cfg: lib.any (nixName: cfg.${nixName} != bounds.${nixName}.default)
      (lib.attrNames bounds);

    tierOption = mkOption {
      type = types.nullOr (types.enum [ "bare" "default" ]);
      default = null;
      description = ''
        Pin `BLUE_TIER`, forcing blue onto a built-in tier instead of the
        deployed YAML — `bare` is the zero-opinion floor, `default` the
        prescribed constants.

        Leave this `null` (the default) for normal use. `BLUE_TIER` outranks
        `BLUE_CONFIG` in `blue_lang_cli::config::resolve`, so setting it at all
        means the config file this module writes is not read. The assertion
        below refuses the combination where that silence would matter.
      '';
    };

    lspOptions = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Write a descriptor telling an editor how to launch blue's language
          server (`blue lsp`, speaking LSP over stdin/stdout).

          This publishes the launch facts as typed data; it deliberately does
          NOT install a `blue-lsp` shim on PATH. module-trio owns exactly one
          shim generator (`withMcp`, hard-named `<tool>-mcp`) and a second,
          hand-rolled one here would be the duplication the fleet treats as a
          defect. A generic subcommand shim belongs in module-trio.
        '';
      };
      descriptorPath = mkOption {
        type = types.str;
        default = ".config/blue/lsp.json";
        description = "Path, relative to $HOME, for the language-server descriptor.";
      };
    };

    # The launch facts, derived from the package rather than restated.
    lspDescriptor = package: {
      command = "${package}/bin/blue";
      args = [ "lsp" ];
      languageId = "blue";
      extensions = [ ".b" ];
    };

    # `tier` bypasses the config file entirely. Setting a bound AND pinning a
    # tier is a contradiction the type system cannot see: each field is
    # individually valid, and together they mean "configure this bound, then
    # ignore it". Neither value is wrong; the PAIR is.
    tierAssertion = cfg: {
      assertion = cfg.tier == null || !(boundsCustomized cfg);
      message = ''
        blue: `tier` is set to "${toString cfg.tier}" while a bound has been
        moved off its default, and those cannot both take effect. BLUE_TIER
        outranks BLUE_CONFIG, so blue would run on the built-in "${toString cfg.tier}"
        tier and never read the value you configured.

        Fix: either unset `tier` (so the deployed YAML is used), or return every
        bound to its default (so nothing is silently discarded).
      '';
    };

    # System (NixOS + nix-darwin) config, shared verbatim — the two module
    # bodies differ only in which daemon helper they would call, and blue
    # declares no daemon.
    systemConfigFor = { cfg, pkgs, lib, ... }: {
      environment = {
        etc."blue/blue.yaml".source =
          (pkgs.formats.yaml { }).generate "blue.yaml" (boundsYaml cfg);
        # One attrset, not `// optionalAttrs { environment.variables = …; }` —
        # that `//` is shallow and would drop `etc` along with it.
        variables = {
          BLUE_CONFIG = "/etc/blue/blue.yaml";
        } // lib.optionalAttrs (cfg.tier != null) { BLUE_TIER = cfg.tier; };
      };
      assertions = [ (tierAssertion cfg) ];
    };
    # fenix is passed explicitly, as tatara-lisp does: the builder takes it as
    # `fenix ? null`, and without it the static-musl Linux package has no
    # prebuilt rust-std, so nixpkgs builds rustc and LLVM from source for the
    # musl target, and llvm-static-x86_64-unknown-linux-musl fails to link
    # (substrate lib/build/rust/overlay.nix documents the class). That was the
    # 52-minute red on every blue `ci` run: the Linux `blue` every check runs
    # never built.
    base = (import "${substrate}/lib/rust-workspace-release-flake.nix" {
      inherit nixpkgs crate2nix flake-utils;
      inherit (substrate.inputs) fenix;
    }) {
      toolName = "blue";
      packageName = "blue-lang-cli";
      src = self;
      repo = "pleme-io/blue";
      memberSource = "own";

      # `lld`, because a test needs it and the shell is where that belongs.
      #
      # `blue-lang-wasm/tests/in_engine.rs` shells out to
      # `cargo build --target wasm32-unknown-unknown` and runs the artifact in
      # a real engine with zero host imports. That build needs a wasm linker.
      #
      # It passed on every laptop and failed on the first CI run that ever
      # executed it — `error: linker 'lld' not found` — because a laptop has an
      # ambient toolchain and a nix shell has exactly what it declares. The
      # test was right; the shell was short. "Passes locally" had meant "passes
      # on machines that happen to have it", which is the property a hermetic
      # shell exists to remove.
      #
      # `devShellPackages` is dev-shell-only and distinct from
      # `nativeBuildInputs`: this is tooling the TESTS need, not the build.
      #
      # `duckdb` for the same reason: `bidamas/kueri`'s end-to-end test runs
      # its rendered SQL through the `duckdb` binary, and the distribution
      # gate (`cargo test`, in this shell on CI) runs every bidama's tests.
      devShellPackages = [ "lld" "duckdb" ];

      # The same test needs the wasm32 standard library in the shell's
      # toolchain. nixpkgs' rustc carried it implicitly; the fenix toolchain
      # this flake now passes (so the static-musl build stops compiling LLVM)
      # carries only the host, and CI's wasm tests failed with `can't find
      # crate for core` until the target was stated here.
      devShellTargets = [ "wasm32-unknown-unknown" ];

      devShellHook = "git rev-parse --git-dir >/dev/null 2>&1 && git config core.hooksPath .githooks && git config alias.land '!.githooks/blue run --quiet gen/land.b --' || true";

      # The module trio, deploying blue's configurable BOUNDS as a shikumi
      # YAML at `~/.config/blue/blue.yaml` and pointing `BLUE_CONFIG` at it.
      #
      # ── WHY THESE KEYS AND NOT THE THREE THE OLD WAIVER NAMED ────────────
      #
      # This block previously said blue had "no configuration surface to
      # deploy" and named three blocked knobs. Measured 2026-08-01, two of the
      # three were not blocked — they were settled AGAINST being configurable,
      # which is a stronger statement than "not yet decided":
      #
      #   - formatter width  — `blue-lang-fmt`'s own module docs: "There is no
      #     configuration type in this crate, and that is the feature… there is
      #     nowhere to put a knob." §0 (one way to write a thing) plus the
      #     content-addressed identity of §V.16.1 both rest on the single
      #     rendering. Typing it would be a REGRESSION.
      #   - posture ceiling  — §V.24 moved ceilings to the ROOT as a Bluefile
      #     input. `blue_lang_waku::Waku` deliberately carries none, and
      #     `blue_lang_bidama::resolve(bidama, ceiling)` takes it as an
      #     argument. A daemon knob would re-create the anti-pattern §V.24
      #     removed.
      #   - execution budget — was unsettled because no default constant
      #     existed; tatara-lisp-eval 0.3.63 gave both executors one, so it is
      #     now two bounds (`max_call_depth`, `max_steps`).
      #   - memory — two bounds on live bytes (`max_alloc_bytes` for `blue run`,
      #     `guest_max_alloc_bytes` for doors that run code they did not write).
      #
      # What is left are six BOUNDS, each with a shipped overridable default in
      # code. Raising either changes no program's meaning — only whether a
      # pathological input is refused — so exposing them cannot freeze a design
      # guess as a public interface, which was the whole objection.
      #
      # The values are NOT restated defaults; see the `bounds` block at the top
      # of this file, which is now the single declaration driving the option,
      # its type, its default and its YAML key.
      # `every_field_is_emitted_by_the_module_trio` (in `blue-lang-cli`'s
      # `config` module) reads THIS FILE and fails if a field is renamed on the
      # Rust side without being renamed here — serde ignores unknown keys, so
      # the drift would otherwise be silent and blue would run on defaults
      # while an operator read their own config and believed it.
      #
      # ── WHAT CHANGED, AND THE DEFECT THAT MOTIVATED IT ───────────────────
      #
      # This block used to be `shikumiDefaults = { solver_max_steps = …; … }`.
      # That is an UNTYPED surface: module-trio's `settings` option is
      # `types.attrs`, so `solver_max_steps = "lots"` or a misspelled key
      # evaluated cleanly, deployed cleanly, and was then dropped in silence by
      # serde. Every value now arrives through a typed option instead, so a bad
      # one is refused at module-eval time.
      #
      # It also fixes a defect that made the whole config surface inert:
      # module-trio writes `~/.config/blue/blue.yaml` but only ever exports
      # `BLUE_CONFIG` from inside its ANVIL-MCP registration block
      # (module-trio.nix:747), which blue does not use. blue therefore shipped a
      # config file that blue itself could not find, and ran on its compiled-in
      # defaults while an operator read their own YAML and believed it — exactly
      # the failure `every_field_is_emitted_by_the_module_trio` was written to
      # prevent, one level further out. `home.sessionVariables` below closes it.
      module = {
        description = "blue — the pleme-io language";

        withShikumiConfig = true;

        # Deliberately EMPTY. module-trio gives an authored `settings` priority
        # over every other source (`recursiveUpdate typedValues authored`), so a
        # default stated here would outrank the typed options below and they
        # would never take effect. The typed options are the only source.
        shikumiDefaults = { };

        # Do not write a config file for a tool the host did not ask for.
        shikumiGateOnEnable = true;

        extraHmOptions = boundOptions // {
          tier = tierOption;
          lsp = lspOptions;
        };

        extraSystemOptions = boundOptions // { tier = tierOption; };

        extraHmConfigFn = { cfg, pkgs, lib, config }: let
          typed = boundsYaml cfg;
        in {
          # mkDefault so an operator can still override the whole tree via
          # `services.blue.settings`; the warning below makes that override
          # loud rather than silent.
          services.blue.settings = lib.mkDefault typed;

          home.sessionVariables = {
            BLUE_CONFIG = "${config.home.homeDirectory}/.config/blue/blue.yaml";
          } // lib.optionalAttrs (cfg.tier != null) { BLUE_TIER = cfg.tier; };

          home.file = lib.optionalAttrs cfg.lsp.enable {
            ${cfg.lsp.descriptorPath}.text =
              builtins.toJSON (lspDescriptor cfg.package);
          };

          assertions = [ (tierAssertion cfg) ];

          # Not an assertion: overriding `settings` wholesale is legitimate.
          # Doing it WITHOUT noticing that the typed options stopped mattering
          # is the failure, so this reports rather than refuses.
          warnings = lib.optional (config.services.blue.settings != typed) ''
            blue: `services.blue.settings` has been set by hand, so it outranks
            the typed options under `programs.blue` and those are no longer
            being used. Configure the bounds through `programs.blue.*`, or
            accept that the authored tree is now the whole config.
          '';
        };

        extraNixosConfigFn = systemConfigFor;
        extraDarwinConfigFn = systemConfigFor;
      };
    };
  in
    # `nix flake check` already compiles the workspace (substrate's `build`) and
    # confirms the gen lock (`gen-confirm`). Neither of those looks at the module
    # trio, which until now had no gate of any kind — the modules were exported,
    # and nothing ever evaluated them. `module-surface` closes that.
    #
    # mapAttrs over the systems substrate actually emitted, rather than a fresh
    # system list that could drift from it.
    let
      # The project engine (`nix/project.nix`): a Bluefile.lock lowered to
      # packages, checks and apps. Every blue project's flake is one call to
      # it (`lib.project` below), and blue's own root Bluefile is lowered by
      # the same function, so the repository holds no second lowering of any
      # word — generate, catalog, packages, tool — to drift from the first.
      engine = import ./nix/project.nix { inherit lib; };
      systems = lib.attrNames base.packages;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      blueFor = system: base.packages.${system}.default;
      # substrate's image builders (mkPackageImage, mkDistrolessImage,
      # hardenedBases) for a Linux system: what a Bluefile `image(...)` lowers
      # through. Images are Linux; elsewhere there is none to give.
      ociFor = system: if lib.hasSuffix "-linux" system then substrate.lib.${system} // {
        cargoAudit = import "${substrate}/lib/build/rust/cargo-audit-data.nix" { };
        hardenedImageSetArgs = {
          docaPkg = substrate.packages.${system}.oci-push;
          tataraScript = substrate.inputs.tatara-lisp.packages.${system}.tatara-script;
        };
      } else null;
      moduleTrio = import "${substrate}/lib/module-trio.nix" { inherit lib; };
      chartLibraries = { pleme-lib = "${helmworks}/charts/pleme-lib"; };

      componentFor = system:
        let
          pkgs = pkgsFor system;
          fx = substrate.inputs.fenix.packages.${system};
          toolchain = fx.combine [ fx.stable.rustc fx.stable.cargo fx.targets.wasm32-wasip2.stable.rust-std ];
          rust = pkgs.makeRustPlatform { cargo = toolchain; rustc = toolchain; };
        in
        pkgs.stdenv.mkDerivation {
          pname = "blue-component";
          version = (lib.importTOML ./Cargo.toml).workspace.package.version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./crates ./bidamas ];
          };
          cargoDeps = rust.importCargoLock { lockFile = ./Cargo.lock; };
          nativeBuildInputs = [ rust.cargoSetupHook toolchain ];
          buildPhase = ''
            runHook preBuild
            cargo build --release --offline --locked -p blue-lang-component --target wasm32-wasip2
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            cp target/wasm32-wasip2/release/blue-component.wasm $out
            runHook postInstall
          '';
          dontFixup = true;
        };

      applianceRelease = (import "${substrate}/lib/rust-workspace-release-flake.nix" {
        inherit nixpkgs crate2nix flake-utils;
        inherit (substrate.inputs) fenix;
      }) {
        toolName = "blue-appliance";
        packageName = "blue-lang-appliance";
        src = self;
        repo = "pleme-io/blue";
        memberSource = "own";
      };
      applianceFor = system: applianceRelease.packages.${system}.default;

      # This repository as a blue project. `base = { }` because its packages
      # ARE the public distribution every other project composes over.
      repository = lib.genAttrs systems (system: engine.projectFor {
        pkgs = pkgsFor system;
        blue = blueFor system;
        src = ./.;
        base = { };
        oci = ociFor system;
        appliance = applianceFor system;
        inherit tameshi;
      });

      # The bidama library bound to a package set: every nix function blue has
      # for bidamas and blue programs (mkBidama, mkDistribution, mkBluePath,
      # mkBlueWithBidamas, mkBlueApp, and the gates). ONE implementation,
      # `bidamas/mk-bidama.nix`; `lib.bidamas` and `overlays.bidamas` are its
      # doors, and substrate composes over them rather than keeping a copy.
      bidamaLibFor = pkgs: import ./bidamas/mk-bidama.nix {
        inherit (pkgs) lib runCommand symlinkJoin makeWrapper makeBinaryWrapper;
        # The formatter mkBidama holds every package canonical with: this
        # flake's own blue for the package set's system.
        blue = base.packages.${pkgs.stdenv.hostPlatform.system}.default or null;
      };

      # The fleet's blue commands, each a bidama's entry function installed by
      # mkBlueApp. This table is the only place a command is named; a new one
      # is a row. `tools` are what the program execs (suffixed to PATH, so a
      # node's own copy wins).
      commands = {
        souji = { entry = "main"; tools = _: [ ]; }; # clean nix and Rust targets
        heni = { entry = "main"; tools = _: [ ]; }; # mutation testing for a blue package
        # macOS keeps /usr/bin/ssh, which reads /etc/ssh/ssh_config as nix does.
        tehai = { entry = "main"; tools = pkgs: lib.optionals pkgs.stdenv.isLinux [ pkgs.openssh pkgs.curl ]; }; # live nix builders and substituters
        keiyu = { entry = "main"; tools = _: [ ]; };
        ukai = { entry = "main"; tools = pkgs: lib.optionals pkgs.stdenv.isLinux [ pkgs.iproute2 pkgs.tailscale ]; };
        kijun = { entry = "main"; tools = pkgs: [ pkgs.git ]; };
        kirikae = { entry = "main"; tools = _: [ ]; };
        shinchoku = { entry = "main"; tools = _: [ ]; };
      };

      # Everything blue gives a package set, from one blue and one distribution.
      blueSetFor = { pkgs, blue }:
        let
          bl = bidamaLibFor pkgs;
          distribution = bl.mkDistribution { root = ./bidamas; inherit pkgs; };
          blueApp = args: bl.mkBlueApp ({ inherit blue; bidamas = distribution; } // args);
        in
        {
          blueLib = bl // { inherit distribution; };
          blue-with-bidamas = bl.mkBlueWithBidamas { inherit blue; bidamas = distribution; };
          inherit blueApp;
        }
        // lib.mapAttrs (name: c: blueApp {
          inherit name;
          source = "use(\"${name}\", [:${c.entry}])\n${c.entry}\n";
          tools = c.tools pkgs;
        }) commands;

      bidamasOverlay = final: _prev: blueSetFor { pkgs = final; blue = blueFor final.stdenv.hostPlatform.system; };

      # blue's tree-sitter grammar, built from the grammar.js that kiwari emits
      # (bidamas/kiwari, gen/kiwari/); its version is the one the emitted
      # tree-sitter.json states, so the two cannot disagree.
      treeSitterBlueFor = pkgs: pkgs.tree-sitter.buildGrammar {
        language = "blue";
        version = (lib.importJSON ./tree-sitter-blue/tree-sitter.json).metadata.version;
        src = ./tree-sitter-blue;
        generate = true;
      };

      # blue native (theory/BLUE-NATIVE.md): native/ as a project, plus each
      # image and its QEMU check (nix/native.nix).
      native = lib.genAttrs systems (system: import ./nix/native.nix {
        inherit lib engine;
        pkgs = pkgsFor system;
        blue = blueFor system;
        inherit (substrate.inputs) fenix;
        emitter = tatara-rust-ast.packages.${system}.default;
      });

    in
    base // {
      # `blue.lib.project { src = ./.; }` — a blue project's whole flake body.
      lib.project = engine.mkProjectOutputs { inherit systems pkgsFor blueFor ociFor moduleTrio chartLibraries componentFor applianceFor tameshi; };

      # `blue.lib.bidamas pkgs` — the bidama library for any package set.
      lib.bidamas = bidamaLibFor;

      # `overlays.bidamas` adds pkgs.blueLib (the library, plus the standard
      # distribution as `blueLib.distribution`), pkgs.blue-with-bidamas,
      # pkgs.blueApp { name; program | source; tools; env; } and one package
      # per command (souji, tehai). `default` is blue itself plus that.
      overlays.bidamas = bidamasOverlay;
      overlays.default = lib.composeExtensions base.overlays.default bidamasOverlay;

      # `nix run .#regen`: rewrite every generated file in place (gen/regen.b).
      # Bluefile.lock files have their own command, `blue lock <dir>`.
      apps = lib.mapAttrs (system: existing:
        engine.disjoint "app" existing repository.${system}.apps
      ) base.apps;

      # `bidama-catalog` and every `generated-<name>`, from ./Bluefile.
      # Plus each command, so `nix run github:pleme-io/blue#souji -- rust` works
      # with no overlay.
      packages = lib.mapAttrs (system: existing:
        engine.disjoint "package"
          (engine.disjoint "package" existing repository.${system}.packages)
          (engine.disjoint "package"
            (lib.getAttrs (lib.attrNames commands)
              (blueSetFor { pkgs = pkgsFor system; blue = blueFor system; }))
            (engine.disjoint "package" native.${system}.packages {
              tree-sitter-blue = treeSitterBlueFor (pkgsFor system);
              blue-appliance = applianceFor system;
            }))
      ) base.packages;

      checks = lib.mapAttrs (system: existing:
        let
          pkgs = pkgsFor system;
          blue = blueFor system;
          bl = import ./bidamas/mk-bidama.nix { inherit (pkgs) lib runCommand symlinkJoin makeWrapper makeBinaryWrapper; inherit blue; };
        in
        engine.disjoint "check" (engine.disjoint "check" (engine.disjoint "check" existing repository.${system}.checks) native.${system}.checks) ({
          # Every .b file in the repository is in the one layout; each file
          # that is not is named. `mkBidama` holds each package the same way,
          # so this is the rest of the tree: specs, generators, fixtures.
          blue-fmt = bl.mkFmtCheck { inherit blue; root = ./.; };

          # The executable specification: every row in spec/rows/ on every
          # evaluator (walker, vm, wasm ABI, the shipped binary, the front
          # end), and the missing-row gate over RULES, FORMS, INFIX, the
          # keywords, docs::NAMES and okite's card. `cargo test` over the
          # Cargo.lock-vendored workspace, through substrate's runner, since
          # the lockfile build path runs no tests. STRICT makes a blind `cli`
          # column red, so the gate cannot pass without the binary it names.
          conformance =
            (import "${substrate}/lib/build/rust/workspace-tests.nix" { inherit lib; }).mkWorkspaceTests pkgs {
              src = ./.;
              name = "blue-conformance";
              config = {
                runs = [ { args = [ "-p" "blue-lang-test" "--test" "conformance" ]; } ];
                env = {
                  BLUE_BIN = "${blue}/bin/blue";
                  BLUE_CONFORMANCE_STRICT = "1";
                };
              };
            };

          # The network primitives against real peers: a nats-server child
          # and a std TCP listener (`blue-lang-runtime/tests/net.rs`), a
          # PostgreSQL, a valkey-server (`tests/resp.rs`) and a JetStream
          # nats-server with a PostgreSQL for the outbox (`tests/jetstream.rs`).
          # REQUIRE makes a missing nats-server red rather than a skip.
          network =
            (import "${substrate}/lib/build/rust/workspace-tests.nix" { inherit lib; }).mkWorkspaceTests pkgs {
              src = ./.;
              name = "blue-network";
              config = {
                runs = [
                  { args = [ "-p" "blue-lang-runtime" "--features" "sys" "--test" "net" ]; }
                  { args = [ "-p" "blue-lang-runtime" "--features" "sys" "--test" "pg" ]; }
                  { args = [ "-p" "blue-lang-runtime" "--features" "sys" "--test" "resp" ]; }
                  { args = [ "-p" "blue-lang-runtime" "--features" "sys" "--test" "jetstream" ]; }
                ];
                nativeBuildInputs = [ "nats-server" "postgresql" "valkey" ];
                env = {
                  BLUE_VALKEY_SERVER = "${pkgs.valkey}/bin/valkey-server";
                  BLUE_REQUIRE_VALKEY = "1";
                  BLUE_NATS_SERVER = "${pkgs.nats-server}/bin/nats-server";
                  BLUE_REQUIRE_NATS_SERVER = "1";
                  BLUE_POSTGRES_BIN = "${pkgs.postgresql}/bin";
                  BLUE_REQUIRE_POSTGRES = "1";
                };
              };
            };

          # kiwari's differential: the parser built from the emitted grammar
          # against blue's own, over every corpus file and every prefix of one
          # (`blue-lang-kiwari/src/agree.rs` defines agreement), plus the spec's
          # tables against parse.rs's. REQUIRE makes a missing parser red
          # rather than a skip.
          kiwari =
            (import "${substrate}/lib/build/rust/workspace-tests.nix" { inherit lib; }).mkWorkspaceTests pkgs {
              src = ./.;
              name = "blue-kiwari";
              config = {
                runs = [
                  {
                    args = [ "--release" "-p" "blue-lang-kiwari" ];
                    harnessArgs = [ "--nocapture" ];
                  }
                ];
                env = {
                  KIWARI_RUNTIME = "${pkgs.tree-sitter}/lib/libtree-sitter${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
                  KIWARI_PARSER = "${treeSitterBlueFor pkgs}/parser";
                  KIWARI_REQUIRE = "1";
                };
              };
            };

          # Every rule being ratcheted in (`blue_lang_check::RULES`'
          # `ratchet`) measures EXACTLY its row's count over the repository:
          # a new violation, or progress the row has not recorded, is red.
          namespace-census = pkgs.runCommand "namespace-census" { } ''
            ${blue}/bin/blue census ${./.} > $out
          '';

          # A bidama whose code does not check does not build.
          bidama-check-refuses = bl.mkCheckRefusalCheck { inherit blue; };

          # A caller's BLUE_PATH overrides the wrapper's pinned distribution.
          blue-path-override = bl.mkOverrideCheck { inherit blue; inherit (repository.${system}) bidamas; };

          # The installed distribution never shadows the file's own project.
          blue-project-first = bl.mkProjectFirstCheck { inherit blue; inherit (repository.${system}) bidamas; };

          # The distribution the wrapper ships is this binary's revision: the
          # overlay's wrapper must wrap the blue this flake builds.
          distribution-is-the-binarys =
            let wrapped = (bidamasOverlay (pkgsFor system) (pkgsFor system)).blue-with-bidamas; in
            if wrapped.passthru.blue.outPath == blue.outPath
            then pkgs.runCommand "distribution-is-the-binarys" { } "touch $out"
            else throw "overlays.bidamas wraps ${wrapped.passthru.blue.outPath}, not this flake's blue ${blue.outPath}: the distribution and the binary come from different revisions";

          # The binary nix builds runs a bare script with no Bluefile and no
          # BLUE_PATH, and the script's `use("retsu")` reaches the standard
          # distribution compiled into it (`blue_lang_pkg::embedded`).
          script-standard = pkgs.runCommand "script-standard" { } ''
            ${blue}/bin/blue ${./examples/00_script.b} standard > $out
            grep -qx STANDARD $out
          '';

          # Every word the engine lowers, read back from a built project: the
          # fixture states the words this repository's own Bluefile does not
          # (a root `needs`, a tool, runs reading runs, a check, an app).
          project-fixture = import ./nix/project-fixture/check.nix {
            inherit pkgs blue engine;
            src = ./nix/project-fixture;
            appliance = applianceFor system;
          };

          # The golden corpus: examples/ is a blue project of its own, lowered
          # by the same engine every project uses. Its checks are this check's
          # inputs, so each example's tests, the example bidama's tests, its
          # collision gate against the public distribution and both lock gates
          # must pass. An example that stops working is a red build.
          examples =
            let ex = engine.projectFor { inherit pkgs blue; src = ./examples; };
            in pkgs.runCommand "examples" { } ''
              ${lib.concatMapStrings (c: "echo ${c} >> $out\n") (lib.attrValues ex.checks)}
            '';

          # The worked image-and-workload project (examples/service): its
          # workload file gated fresh everywhere and, on Linux, its image
          # built through substrate and gated distroless. The packages are
          # inputs too, so the image tarball itself is built, not only its
          # closure scanned.
          example-service =
            let ex = engine.projectFor { inherit pkgs blue; src = ./examples/service; oci = ociFor system; legacy = { directImages = true; rawWorkloads = true; }; };
            in pkgs.runCommand "example-service" { } ''
              ${lib.concatMapStrings (d: "echo ${d} >> $out\n") (lib.attrValues ex.checks ++ lib.attrValues ex.packages)}
            '';

          example-service-factory =
            let ex = engine.projectFor { inherit pkgs blue; src = ./examples/service; oci = ociFor system; legacy.rawWorkloads = true; };
            in pkgs.runCommand "example-service-factory" { } ''
              ${lib.concatMapStrings (d: "echo ${d} >> $out\n") (lib.attrValues ex.checks ++ lib.attrValues ex.packages)}
            '';

          example-service-workload-off =
            let
              ex = engine.projectFor { inherit pkgs blue; src = ./examples/service; oci = ociFor system; };
              refused = builtins.tryEval (builtins.deepSeq (builtins.attrNames ex.checks) true);
            in
            assert lib.assertMsg (!refused.success) "example-service-workload-off: a workload lowered with rawWorkloads off";
            pkgs.writeText "example-service-workload-off" "refused";

          example-http =
            let ex = engine.projectFor { inherit pkgs blue moduleTrio chartLibraries; src = ./examples/http; oci = ociFor system; component = componentFor system; };
            in pkgs.runCommand "example-http" { } ''
              ${lib.concatMapStrings (d: "echo ${d} >> $out\n") (lib.attrValues ex.checks ++ lib.attrValues ex.packages)}
            '';

          example-frontend =
            let ex = engine.projectFor { inherit pkgs blue; src = ./examples/frontend; };
            in pkgs.runCommand "example-frontend" { } ''
              ${lib.concatMapStrings (d: "echo ${d} >> $out\n") (lib.attrValues ex.checks ++ lib.attrValues ex.packages)}
            '';

          # The worked ibuki docking project (examples/docking, theory/IBUKI.md):
          # a pure ceiling, a stepped clock and a seeded provider scoped to
          # shomei; its test docks its own lock's capability record as a
          # crystal, and its app is sealed into an appliance.
          example-docking =
            let ex = engine.projectFor { inherit pkgs blue; src = ./examples/docking; appliance = applianceFor system; };
            in pkgs.runCommand "example-docking" { } ''
              ${lib.concatMapStrings (d: "echo ${d} >> $out\n") (lib.attrValues ex.checks ++ lib.attrValues ex.packages)}
            '';
        } // lib.optionalAttrs (ociFor system != null) {
          # The distroless gate's positive control: an image built with a
          # shell must be refused as distroless-static, naming the shell, or
          # the gate above could be passing over a closure it cannot read.
          image-gate-refuses =
            let
              oci = ociFor system;
              ex = engine.projectFor { inherit pkgs blue oci; src = ./examples/service; legacy = { directImages = true; rawWorkloads = true; }; };
            in
            ex.imageGate {
              name = "image-gate-refuses";
              tier = "distroless-static";
              refuses = true;
              image = oci.mkDistrolessImage {
                service = "image-gate-control";
                package = blue;
                publishName = "localhost/image-gate-control";
                publishTag = "0";
                entrypoint = [ "${blue}/bin/blue" ];
                shell = true;
              };
            };
        } // {
          module-surface = import ./nix/module-surface-check.nix {
            inherit lib;
            # blue's own overlay, because `programs.blue.package` defaults to
            # `pkgs.blue` (module-trio.nix:367) — a bare nixpkgs has no such
            # attribute and the module cannot be evaluated at all without it.
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ base.overlays.default ];
            };
            homeManagerModule = base.homeManagerModules.default;
            nixosModule = base.nixosModules.default;
            darwinModule = base.darwinModules.default;
          };
        })
      ) base.checks;
    };
}
