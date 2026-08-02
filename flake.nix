{
  description = "blue — a Ruby/Elixir surface on tatara-lisp and Rust";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    crate2nix.url = "github:nix-community/crate2nix";
    flake-utils.url = "github:numtide/flake-utils";
    substrate = {
      url = "github:pleme-io/substrate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    crate2nix,
    flake-utils,
    substrate,
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
    # Both are BOUNDS, never preferences: raising or lowering either changes no
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
    base = (import "${substrate}/lib/rust-workspace-release-flake.nix" {
      inherit nixpkgs crate2nix flake-utils;
    }) {
      toolName = "blue";
      packageName = "blue-lang-cli";
      src = self;
      repo = "pleme-io/blue";

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
      devShellPackages = [ "lld" ];

      # The module trio, deploying blue's two configurable BOUNDS as a shikumi
      # YAML at `~/.config/blue/blue.yaml` and pointing `BLUE_CONFIG` at it.
      #
      # ── WHY TWO KEYS AND NOT THE THREE THE OLD WAIVER NAMED ──────────────
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
      #   - execution budget — genuinely unsettled, for a concrete reason: no
      #     default constant exists in blue to expose. `pending-shikumi: M2`.
      #
      # What is left are two BOUNDS, each with a shipped overridable default in
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
    base // {
      checks = lib.mapAttrs (system: existing:
        existing // {
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
        }
      ) base.checks;
    };
}
