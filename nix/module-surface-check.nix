# Eval-level gate on blue's NixOS + nix-darwin + home-manager module surface.
#
# Wired as `checks.<system>.module-surface`. The check derivation is a
# `writeText` of the report below, so the BUILD is trivial and all the work
# happens during evaluation — if any claim here is false, evaluation throws and
# `nix flake check` fails. No shell, and nothing to keep in sync with a runner.
#
# ── What this measures, and what it cannot ────────────────────────────────
#
# Home-manager and nix-darwin are not flake inputs of this repo, and adding
# either just to type-check a module would be a heavy dependency for a small
# claim. So the option trees blue's modules WRITE INTO are stubbed here, tightly
# typed, and the modules are evaluated against those stubs.
#
# That makes this a test of blue's module — its options, its types, its
# assertions, and the values it produces — and NOT a test that home-manager
# accepts it. A stub that drifts from the real option (a renamed HM option, a
# changed type) would pass here and fail on a real host. The stubs are
# deliberately narrow so that drift is at least visible in one place.
#
# Tier: parse-time-rejected for the option VALUES (a bad bound has no way
# through `lib.evalModules`), CI-gate-caught for everything else.
{ lib, pkgs, homeManagerModule, nixosModule, darwinModule }:
let
  inherit (lib) mkOption types evalModules;

  # A home.file entry, as home-manager declares it — narrowed to the three
  # fields blue's module and module-trio actually set.
  fileEntry = types.submodule {
    options = {
      text = mkOption { type = types.nullOr types.lines; default = null; };
      source = mkOption { type = types.nullOr types.path; default = null; };
      executable = mkOption { type = types.nullOr types.bool; default = null; };
    };
  };

  assertionEntry = types.submodule {
    options = {
      assertion = mkOption { type = types.bool; };
      message = mkOption { type = types.str; };
    };
  };

  assertionOptions = {
    assertions = mkOption { type = types.listOf assertionEntry; default = [ ]; };
    warnings = mkOption { type = types.listOf types.str; default = [ ]; };
  };

  # Option trees module-trio NAMES but blue never populates — its launchd /
  # systemd / anvil / app-bundle branches are all `mkIf false` for this spec.
  #
  # They still have to be declared. `lib.modules.pushDownProperties` forces an
  # `mkIf`'s content to an attrset to collect its attribute NAMES before the
  # condition is ever consulted, so a disabled branch still registers a
  # definition. An undeclared one then renders "option does not exist", and
  # rendering that message evaluates the definition — which for the anvil branch
  # is `${mcpCfg.package}` with `mcpCfg = null`. The error you get is a null
  # dereference from a branch that is switched off, which is thoroughly
  # misleading; declaring the tree is what makes it discharge to nothing.
  #
  # `types.attrs` here and nowhere else: these are placeholders for other
  # projects' option trees, and the values are unreachable by construction (a
  # false `mkIf` discharges to no definition, so nothing is ever merged into
  # them). Every option BLUE declares is strictly typed.
  foreignTrees = {
    launchd = mkOption { type = types.attrs; default = { }; };
    systemd = mkOption { type = types.attrs; default = { }; };
    blackmatter = mkOption { type = types.attrs; default = { }; };
  };

  # Stub of the home-manager options blue's HM module writes into.
  hmBase = { ... }: {
    options = {
      home = {
        homeDirectory = mkOption { type = types.str; default = "/home/tester"; };
        packages = mkOption { type = types.listOf types.package; default = [ ]; };
        file = mkOption { type = types.attrsOf fileEntry; default = { }; };
        sessionVariables = mkOption { type = types.attrsOf types.str; default = { }; };
        # Named by the app-bundle branch (`appBundle = null`, so never valued).
        activation = mkOption { type = types.attrs; default = { }; };
      };
    } // assertionOptions // foreignTrees;
  };

  # Stub of the NixOS / nix-darwin options blue's system modules write into.
  systemBase = { ... }: {
    options = {
      environment = {
        systemPackages = mkOption { type = types.listOf types.package; default = [ ]; };
        etc = mkOption {
          type = types.attrsOf (types.submodule {
            options.source = mkOption { type = types.path; };
          });
          default = { };
        };
        variables = mkOption { type = types.attrsOf types.str; default = { }; };
      };
    } // assertionOptions // foreignTrees;
  };

  evalWith = base: module: settings:
    (evalModules {
      specialArgs = { inherit pkgs; };
      modules = [ base module settings ];
    }).config;

  # Force the whole config tree; a type error surfaces only when the offending
  # value is demanded.
  rejects = base: module: settings:
    !(builtins.tryEval (builtins.deepSeq (evalWith base module settings) true)).success;

  expect = what: cond: if cond then true else throw "blue module-surface check FAILED: ${what}";

  # ── 1. Each of the three modules evaluates ────────────────────────────
  hm = evalWith hmBase homeManagerModule { programs.blue.enable = true; };
  nixos = evalWith systemBase nixosModule { services.blue.enable = true; };
  darwin = evalWith systemBase darwinModule { services.blue.enable = true; };

  shipped = { solver_max_steps = 100000; max_expr_depth = 256; };

  evaluates = [
    (expect "the HM module deploys the shipped bounds as the shikumi settings"
      (hm.services.blue.settings == shipped))

    # The defect this whole surface was rewritten to fix: module-trio writes the
    # YAML but only exports BLUE_CONFIG from its anvil block, which blue does
    # not use. Without this the config file exists and blue never reads it.
    # `or null`, not a bare attribute access: if the export is dropped entirely
    # — which is precisely the regression this claim guards — a bare access dies
    # with "attribute 'BLUE_CONFIG' missing" and the reader learns nothing about
    # what was supposed to set it.
    (expect "the HM module points BLUE_CONFIG at the YAML it deploys"
      ((hm.home.sessionVariables.BLUE_CONFIG or null)
        == "/home/tester/.config/blue/blue.yaml"))

    (expect "BLUE_TIER is absent unless the operator pins a tier"
      (!(hm.home.sessionVariables ? BLUE_TIER)))

    (expect "no warning fires on a default configuration" (hm.warnings == [ ]))

    (expect "the LSP descriptor is not written unless asked"
      (!(hm.home.file ? ".config/blue/lsp.json")))

    (expect "the NixOS module points BLUE_CONFIG at /etc"
      ((nixos.environment.variables.BLUE_CONFIG or null) == "/etc/blue/blue.yaml"))
    (expect "the NixOS module writes /etc/blue/blue.yaml"
      (nixos.environment.etc ? "blue/blue.yaml"))
    (expect "the Darwin module points BLUE_CONFIG at /etc"
      ((darwin.environment.variables.BLUE_CONFIG or null) == "/etc/blue/blue.yaml"))
  ];

  # ── 2. The LSP surface ────────────────────────────────────────────────
  hmLsp = evalWith hmBase homeManagerModule {
    programs.blue = { enable = true; lsp.enable = true; };
  };
  # `unsafeDiscardStringContext` because the descriptor's `command` is a real
  # store path, and `fromJSON` refuses any string carrying context. Discarding
  # it is safe here and only here: this value is read by the assertions below
  # and never enters a derivation, so there is no build dependency to lose.
  lspJson = builtins.fromJSON
    (builtins.unsafeDiscardStringContext hmLsp.home.file.".config/blue/lsp.json".text);

  lspChecks = [
    (expect "the LSP descriptor names the `lsp` subcommand" (lspJson.args == [ "lsp" ]))
    (expect "the LSP descriptor claims the .b extension" (lspJson.extensions == [ ".b" ]))
    (expect "the LSP descriptor points at the blue binary"
      (lib.hasSuffix "/bin/blue" lspJson.command))
  ];

  # ── 3. A bad value is REFUSED, not silently accepted ──────────────────
  #
  # This is the half that distinguishes a typed surface from a decorated one.
  # Each of these evaluated cleanly under the previous `shikumiDefaults =
  # { … }` surface, because module-trio's `settings` option is `types.attrs`.
  rejections = [
    (expect "a zero solver bound is refused"
      (rejects hmBase homeManagerModule {
        programs.blue = { enable = true; solverMaxSteps = 0; };
      }))
    (expect "a solver bound above the ceiling is refused"
      (rejects hmBase homeManagerModule {
        programs.blue = { enable = true; solverMaxSteps = 100000001; };
      }))
    (expect "a non-integer bound is refused"
      (rejects hmBase homeManagerModule {
        programs.blue = { enable = true; solverMaxSteps = "lots"; };
      }))
    (expect "a nesting bound past the stack-overflow guard is refused"
      (rejects hmBase homeManagerModule {
        programs.blue = { enable = true; maxExprDepth = 99999; };
      }))
    (expect "a tier outside the enum is refused"
      (rejects hmBase homeManagerModule {
        programs.blue = { enable = true; tier = "prescribed"; };
      }))
    (expect "an unknown option is refused"
      (rejects hmBase homeManagerModule {
        programs.blue = { enable = true; formatterWidth = 100; };
      }))
    (expect "the system modules reject a bad bound too"
      (rejects systemBase nixosModule {
        services.blue = { enable = true; maxExprDepth = 0; };
      }))
  ];

  # ── 4. The cross-field invariant the types cannot express ─────────────
  #
  # `tier` bypasses the config file, so pinning one while customizing a bound
  # means the bound is configured and then discarded. Each field is
  # individually valid; only the pair is wrong, which is why this is an
  # assertion rather than a type.
  contradiction = evalWith hmBase homeManagerModule {
    programs.blue = { enable = true; tier = "bare"; solverMaxSteps = 5; };
  };
  agreeable = evalWith hmBase homeManagerModule {
    programs.blue = { enable = true; tier = "bare"; };
  };

  assertionChecks = [
    (expect "a pinned tier plus a customized bound trips the assertion"
      (lib.any (a: !a.assertion) contradiction.assertions))
    (expect "a pinned tier alone is allowed"
      (lib.all (a: a.assertion) agreeable.assertions))
    (expect "a pinned tier is exported as BLUE_TIER"
      ((agreeable.home.sessionVariables.BLUE_TIER or null) == "bare"))
  ];

  # ── 5. Hand-authored settings shadow the typed options, loudly ────────
  shadowed = evalWith hmBase homeManagerModule {
    programs.blue.enable = true;
    services.blue.settings = { solver_max_steps = 7; max_expr_depth = 9; };
  };

  shadowChecks = [
    (expect "an authored settings tree wins over the typed options"
      (shadowed.services.blue.settings == { solver_max_steps = 7; max_expr_depth = 9; }))
    (expect "and says so, rather than discarding the typed options in silence"
      (builtins.length shadowed.warnings == 1))
  ];

  all = evaluates ++ lspChecks ++ rejections ++ assertionChecks ++ shadowChecks;
  total = builtins.length all;
in
# `builtins.deepSeq` forces every `expect`; any throw fails the check.
builtins.deepSeq all (
  pkgs.writeText "blue-module-surface-report"
    ("blue module surface: 3 modules, " + builtins.toString total + " claims verified\n")
)
